#!/usr/bin/env bash
# rotate-api-key.sh — Rotate the OpenRouter API key across all clusters/namespaces
#
# Updates the K8s Secret and restarts proxy pods to pick up the new key.
# Gateway pods stay up — no route disruption, no session loss.
#
# Usage:
#   ./rotate-api-key.sh                    # reads new key from .env (OPENROUTER_API_KEY)
#   ./rotate-api-key.sh --key sk-or-v1-... # pass new key directly
#   ./rotate-api-key.sh --dry-run          # show what would change without applying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ──────────────────────────────────────────────────
NEW_KEY=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)
      SITE_NAME="$2"
      shift 2
      ;;
    --key)
      NEW_KEY="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--site NAME] [--key NEW_KEY] [--dry-run]"
      echo ""
      echo "  --site NAME  Site config to use (default: primary)"
      echo "  --key KEY    New OpenRouter API key (otherwise reads from .env)"
      echo "  --dry-run    Show what would change without applying"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      exit 1
      ;;
  esac
done

# Load site config (CLUSTERS_CSV, etc.)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

# ── Load key ──────────────────────────────────────────────────────────
if [[ -z "$NEW_KEY" ]]; then
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
  elif [[ -f "${SCRIPT_DIR}/../.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/../.env"
  fi
  NEW_KEY="${OPENROUTER_API_KEY:-}"
fi

if [[ -z "$NEW_KEY" ]]; then
  echo -e "${RED}ERROR: No API key provided. Use --key or set OPENROUTER_API_KEY in .env${RESET}"
  exit 1
fi

# Sanity check — OpenRouter keys start with sk-or-
if [[ "$NEW_KEY" != sk-or-* ]]; then
  echo -e "${YELLOW}WARNING: Key does not start with 'sk-or-' — are you sure this is an OpenRouter key?${RESET}"
  read -rp "Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

KEY_PREFIX="${NEW_KEY:0:10}..."
KEY_SUFFIX="...${NEW_KEY: -4}"

# ── Build cluster list ────────────────────────────────────────────────
CLUSTER_ENTRIES=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}ERROR: Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}${RESET}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}ERROR: Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})${RESET}"
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_ENTRIES[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
else
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged in to OpenShift. Run 'oc login' first.${RESET}"
    exit 1
  fi
  CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
  CLUSTER_ENTRIES+=("${CLUSTER_GUID:-default} ${KUBECONFIG:-$HOME/.kube/config}")
fi

# ── Header ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  OpenRouter API Key Rotation${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  New key: ${CYAN}${KEY_PREFIX}${KEY_SUFFIX}${RESET}  (${#NEW_KEY} chars)"
echo -e "  Clusters: ${CYAN}${#CLUSTER_ENTRIES[@]}${RESET}"
$DRY_RUN && echo -e "  Mode: ${YELLOW}DRY RUN${RESET}"
echo ""

if $DRY_RUN; then
  echo -e "${BOLD}Would update:${RESET}"
  for entry in "${CLUSTER_ENTRIES[@]}"; do
    CLUSTER_ID="${entry%% *}"
    CLUSTER_KUBECONFIG="${entry#* }"
    NS_COUNT=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get ns --no-headers -o name 2>/dev/null | grep agentic-user | wc -l | xargs)
    echo -e "  ${CYAN}${CLUSTER_ID}${RESET}: ${NS_COUNT} namespaces — update Secret + restart proxy"
  done
  echo ""
  echo -e "${DIM}Run without --dry-run to apply.${RESET}"
  exit 0
fi

# ── Rotate on each cluster ────────────────────────────────────────────
TOTAL_UPDATED=0
TOTAL_FAILED=0

for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  export KUBECONFIG="$CLUSTER_KUBECONFIG"

  NAMESPACES=$(oc get ns --no-headers -o name 2>/dev/null | grep agentic-user | sed 's|namespace/||' | sort -t- -k2 -n)
  NS_COUNT=$(echo "$NAMESPACES" | wc -l | xargs)

  echo -e "${BOLD}--- ${CLUSTER_ID} (${NS_COUNT} namespaces) ---${RESET}"

  # Phase 1: Update secrets in all namespaces
  echo -e "  ${DIM}Phase 1: Updating secrets...${RESET}"
  UPDATED=0
  FAILED=0
  for NS in $NAMESPACES; do
    if oc create secret generic openrouter-api-key \
      --from-literal=api-key="$NEW_KEY" \
      -n "$NS" \
      --dry-run=client -o yaml 2>/dev/null | oc apply -f - -n "$NS" &>/dev/null; then
      UPDATED=$((UPDATED + 1))
    else
      echo -e "    ${RED}✗ ${NS}: failed to update secret${RESET}"
      FAILED=$((FAILED + 1))
    fi
  done
  echo -e "  ${GREEN}✓${RESET} Secrets updated: ${UPDATED}/${NS_COUNT}"

  # Phase 2: Rolling restart proxy pods (picks up new secret value)
  echo -e "  ${DIM}Phase 2: Restarting proxy pods...${RESET}"
  RESTARTED=0
  for NS in $NAMESPACES; do
    if oc rollout restart deployment/instance-proxy -n "$NS" &>/dev/null; then
      RESTARTED=$((RESTARTED + 1))
    else
      echo -e "    ${RED}✗ ${NS}: failed to restart proxy${RESET}"
      FAILED=$((FAILED + 1))
    fi
  done
  echo -e "  ${GREEN}✓${RESET} Proxy restarts triggered: ${RESTARTED}/${NS_COUNT}"

  # Phase 3: Wait for rollouts to complete
  echo -e "  ${DIM}Phase 3: Waiting for rollouts...${RESET}"
  READY=0
  for NS in $NAMESPACES; do
    if oc rollout status deployment/instance-proxy -n "$NS" --timeout=60s &>/dev/null; then
      READY=$((READY + 1))
    else
      echo -e "    ${YELLOW}⚠ ${NS}: rollout timed out (may still be progressing)${RESET}"
    fi
  done
  echo -e "  ${GREEN}✓${RESET} Rollouts ready: ${READY}/${NS_COUNT}"

  TOTAL_UPDATED=$((TOTAL_UPDATED + UPDATED))
  TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
  echo ""
done

# ── Verify ────────────────────────────────────────────────────────────
echo -e "${BOLD}--- Verification (spot check) ---${RESET}"
for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  # Check 3 random namespaces per cluster
  for NS in $(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get ns --no-headers -o name 2>/dev/null \
    | grep agentic-user | sed 's|namespace/||' | shuf | head -3); do
    STORED=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get secret openrouter-api-key -n "$NS" \
      -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d)
    if [[ "${STORED:0:10}" == "${NEW_KEY:0:10}" ]]; then
      echo -e "  ${GREEN}✓${RESET} ${CLUSTER_ID}/${NS}: key matches"
    else
      echo -e "  ${RED}✗${RESET} ${CLUSTER_ID}/${NS}: key mismatch!"
    fi
  done
done

echo ""
echo -e "${BOLD}Done.${RESET} Updated ${TOTAL_UPDATED} secrets, ${TOTAL_FAILED} failures."
