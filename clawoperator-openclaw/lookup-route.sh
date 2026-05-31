#!/usr/bin/env bash
# lookup-route.sh — Resolve a public broker URL to its cluster and namespace
#
# Usage:
#   ./lookup-route.sh https://claw-22b44-7b27bf.yougetaclaw.com
#   ./lookup-route.sh claw-22b44-7b27bf.yougetaclaw.com
#   ./lookup-route.sh 7b27bf                 # shorthand — searches by suffix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Extract --site flag before positional args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="$2"; shift 2 ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Load site config (BROKER_DOMAIN, CLUSTERS_CSV, etc.)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--site NAME] <url|hostname|suffix>"
  echo ""
  echo "Examples:"
  echo "  $0 https://claw-22b44-7b27bf.${BROKER_DOMAIN}"
  echo "  $0 claw-22b44-7b27bf.${BROKER_DOMAIN}"
  echo "  $0 7b27bf"
  exit 1
fi

# Normalize input — extract the search token from URL, hostname, or bare suffix
INPUT="$1"
INPUT="${INPUT#https://}"
INPUT="${INPUT#http://}"
INPUT="${INPUT%%/*}"
# Strip broker domain to get the subdomain prefix (e.g. claw-22b44-7b27bf)
INPUT="${INPUT%.${BROKER_DOMAIN}}"
SEARCH="$INPUT"

# ── Build cluster list ────────────────────────────────────────────────
CLUSTER_ENTRIES=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}ERROR: Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}${RESET}" >&2
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
  done < "$CLUSTERS_CSV"
else
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged in to OpenShift. Run 'oc login' first.${RESET}" >&2
    exit 1
  fi
  CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
  CLUSTER_ENTRIES+=("${CLUSTER_GUID:-default} ${KUBECONFIG:-$HOME/.kube/config}")
fi

# ── Search routes across clusters ─────────────────────────────────────
for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  MATCH=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get route -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace} {.spec.host}{"\n"}{end}' 2>/dev/null \
    | grep "$SEARCH" || true)

  if [[ -n "$MATCH" ]]; then
    while IFS= read -r line; do
      NS="${line%% *}"
      HOST="${line#* }"
      echo -e "${BOLD}Match found${RESET}"
      echo -e "  Cluster:   ${CYAN}${CLUSTER_ID}${RESET}"
      echo -e "  Namespace: ${CYAN}${NS}${RESET}"
      echo -e "  Route:     ${DIM}${HOST}${RESET}"
      echo -e "  KUBECONFIG: ${DIM}${CLUSTER_KUBECONFIG}${RESET}"
    done <<< "$MATCH"
    exit 0
  fi
done

echo -e "${RED}No route matching '${SEARCH}' found across ${#CLUSTER_ENTRIES[@]} cluster(s).${RESET}" >&2
exit 1
