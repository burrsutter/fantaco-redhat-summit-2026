#!/usr/bin/env bash
# manage-proxy-allowlist.sh — Add, remove, or list domains in the proxy allowlist
#
# Patches the Claw CR (spec.credentials) so the claw-operator generates the
# correct proxy config. Direct ConfigMap patches get overwritten by the operator.
#
# For each allowed domain, creates a Secret + credential entry with type=apiKey
# using a harmless no-op header (X-Proxy-Passthrough). The operator sees a valid
# credential and adds the domain to the proxy allowlist.
#
# Supports multi-cluster via clusters.csv (same format as update-broker.sh).
# Multi-site: use --site backup to target backup site clusters.
#
# Usage:
#   ./manage-proxy-allowlist.sh list                                  # all namespaces (primary)
#   ./manage-proxy-allowlist.sh --site backup list                    # backup site
#   ./manage-proxy-allowlist.sh list 3                                # just user3
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov                   # all namespaces
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov 3                 # just user3
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov 1 5               # user1-user5
#   ./manage-proxy-allowlist.sh allow xkcd.com,imgs.xkcd.com 2       # multiple domains
#   ./manage-proxy-allowlist.sh revoke apod.nasa.gov                  # all namespaces
#   ./manage-proxy-allowlist.sh revoke apod.nasa.gov 3                # just user3
#   ./manage-proxy-allowlist.sh revoke xkcd.com,imgs.xkcd.com        # multiple domains
#
# Requires: jq
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAX_PARALLEL="${MAX_PARALLEL:-10}"

# ── Require jq ────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  exit 1
fi

# ── Parse arguments ───────────────────────────────────────────────
# Extract --site flag before positional args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--site NAME] list [user# | start end]"
      echo "       $0 [--site NAME] allow <domain>[,domain2,...] [user# | start end]"
      echo "       $0 [--site NAME] revoke <domain>[,domain2,...] [user# | start end]"
      echo ""
      echo "  --site NAME  Site config to use (default: primary)"
      exit 0
      ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Load site config (sets CLUSTERS_CSV to per-site file if it exists)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--site NAME] list [user# | start end]"
  echo "       $0 [--site NAME] allow <domain>[,domain2,...] [user# | start end]"
  echo "       $0 [--site NAME] revoke <domain>[,domain2,...] [user# | start end]"
  exit 1
fi

ACTION="$1"
shift

DOMAINS=()
if [[ "$ACTION" == "allow" || "$ACTION" == "revoke" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: $ACTION requires a domain argument"
    echo "Usage: $0 $ACTION <domain>[,domain2,...] [user# | start end]"
    exit 1
  fi
  IFS=',' read -ra DOMAINS <<< "$1"
  shift
fi

# ── Argument parsing (namespace selection) ────────────────────────
# Defer actual namespace discovery to per-cluster function
NS_MODE="auto"
NS_START=""
NS_END=""
if [[ $# -ge 1 ]]; then
  if [[ $# -le 2 ]]; then
    NS_MODE="range"
    NS_START=$1
    NS_END=${2:-$NS_START}
    if [[ $NS_START -gt $NS_END ]]; then
      echo "Error: start ($NS_START) must be <= end ($NS_END)"
      exit 1
    fi
  else
    echo "Usage: $0 $ACTION <domain>[,domain2,...] [user# | start end]"
    exit 1
  fi
fi

# ── Build cluster list ──────────────────────────────────────────────
# Each entry: "cluster_id kubeconfig_path"
CLUSTER_ENTRIES=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}Error: Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}${RESET}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}Error: Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})${RESET}"
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_ENTRIES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
else
  # Single-cluster fallback
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  CLUSTER_ENTRIES+=("default ${KUBECONFIG:-$HOME/.kube/config}")
fi

MULTI_CLUSTER=false
[[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]] && MULTI_CLUSTER=true

# ── Helper: discover namespaces for a given kubeconfig ────────────
discover_namespaces() {
  local kc="$1"
  NAMESPACES=()
  if [[ "$NS_MODE" == "auto" ]]; then
    while IFS= read -r ns; do
      NAMESPACES+=("$ns")
    done < <(KUBECONFIG="$kc" oc get namespaces --no-headers 2>/dev/null \
      | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
      echo -e "  ${YELLOW}No ${NAMESPACE_PREFIX}* namespaces found on this cluster${RESET}"
    fi
  else
    for i in $(seq "$NS_START" "$NS_END"); do
      NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
    done
  fi
}

# ── Helper: domain → credential name ─────────────────────────────
# Converts "apod.nasa.gov" → "allow-apod-nasa-gov"
domain_to_name() {
  echo "allow-${1//./-}"
}

# ══════════════════════════════════════════════════════════════════
# LIST
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "list" ]]; then
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Proxy Allowlist${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""

  for entry in "${CLUSTER_ENTRIES[@]}"; do
    CLUSTER_ID="${entry%% *}"
    CLUSTER_KUBECONFIG="${entry#* }"

    $MULTI_CLUSTER && echo -e "${BOLD}── Cluster: ${CLUSTER_ID} ──${RESET}" && echo ""

    discover_namespaces "$CLUSTER_KUBECONFIG"

    for NS in "${NAMESPACES[@]}"; do
      echo -e "${BOLD}${CYAN}$NS:${RESET}"

      CONFIG=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get configmap instance-proxy-config -n "$NS" \
        -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)

      if [[ -z "$CONFIG" ]]; then
        echo -e "  ${YELLOW}(ConfigMap instance-proxy-config not found)${RESET}"
        echo ""
        continue
      fi

      ROUTES=$(echo "$CONFIG" | jq -r '.routes[] | if .allowedPaths then "  \(.domain)  (allowedPaths: \(.allowedPaths | join(", ")))" else "  \(.domain)  (\(.injector // "none"))" end' 2>/dev/null || true)
      if [[ -n "$ROUTES" ]]; then
        echo "$ROUTES"
      else
        echo -e "  ${DIM}(no routes configured)${RESET}"
      fi
      echo ""
    done
  done
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# ALLOW
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "allow" ]]; then
  echo ""
  echo -e "${BOLD}Adding ${YELLOW}${DOMAINS[*]}${RESET}${BOLD} to proxy allowlist...${RESET}"
  echo ""

  for entry in "${CLUSTER_ENTRIES[@]}"; do
    CLUSTER_ID="${entry%% *}"
    CLUSTER_KUBECONFIG="${entry#* }"

    $MULTI_CLUSTER && echo -e "${BOLD}── Cluster: ${CLUSTER_ID} ──${RESET}" && echo ""

    discover_namespaces "$CLUSTER_KUBECONFIG"

    ALLOW_TMPDIR=$(mktemp -d)
    JOB_COUNT=0

    for DOMAIN in "${DOMAINS[@]}"; do
      CRED_NAME=$(domain_to_name "$DOMAIN")
      SECRET_NAME="${CRED_NAME}-key"
      CRED_JSON=$(jq -n \
        --arg name "$CRED_NAME" \
        --arg domain "$DOMAIN" \
        --arg secret "$SECRET_NAME" \
        '{
          name: $name,
          domain: $domain,
          type: "apiKey",
          apiKey: { header: "X-Proxy-Passthrough", valuePrefix: "" },
          secretRef: [{ key: "api-key", name: $secret }]
        }')

      for NS in "${NAMESPACES[@]}"; do
        (
          # 1. Create the passthrough secret if needed
          if ! KUBECONFIG="$CLUSTER_KUBECONFIG" oc get secret "$SECRET_NAME" -n "$NS" &>/dev/null; then
            if ! KUBECONFIG="$CLUSTER_KUBECONFIG" oc create secret generic "$SECRET_NAME" -n "$NS" \
              --from-literal=api-key=PASSTHROUGH 2>/dev/null; then
              echo -e "  ${RED}$NS: failed to create secret for ${DOMAIN}${RESET}" > "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}"
              exit 0
            fi
          fi

          # 2. Check if credential already exists in the Claw CR
          EXISTS=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get claw instance -n "$NS" -o json 2>/dev/null \
            | jq -r --arg n "$CRED_NAME" '.spec.credentials[]? | select(.name == $n) | .name' || true)

          if [[ -n "$EXISTS" ]]; then
            echo -e "  ${DIM}$NS: ${DOMAIN} already in allowlist${RESET}" > "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}"
            exit 0
          fi

          # 3. Patch the Claw CR to add the credential
          if KUBECONFIG="$CLUSTER_KUBECONFIG" oc patch claw instance -n "$NS" --type json \
            -p "[{\"op\":\"add\",\"path\":\"/spec/credentials/-\",\"value\":${CRED_JSON}}]" &>/dev/null; then
            echo -e "  ${GREEN}$NS: added ${DOMAIN}${RESET}" > "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}"
          else
            echo -e "  ${RED}$NS: failed to patch Claw CR for ${DOMAIN}${RESET}" > "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}"
          fi
        ) &
        JOB_COUNT=$((JOB_COUNT + 1))
        if (( JOB_COUNT >= MAX_PARALLEL )); then
          wait
          JOB_COUNT=0
        fi
      done
    done
    wait

    # Print results in namespace order
    for NS in "${NAMESPACES[@]}"; do
      for DOMAIN in "${DOMAINS[@]}"; do
        CRED_NAME=$(domain_to_name "$DOMAIN")
        [[ -f "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}" ]] && cat "${ALLOW_TMPDIR}/${NS}_${CRED_NAME}"
      done
    done
    rm -rf "$ALLOW_TMPDIR"

    echo ""
    echo -e "${DIM}Waiting for operator to reconcile...${RESET}"
    sleep 5

    # Verify all domains on first namespace of this cluster
    if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
      FIRST_NS="${NAMESPACES[0]}"
      for DOMAIN in "${DOMAINS[@]}"; do
        VERIFY=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get configmap instance-proxy-config -n "$FIRST_NS" \
          -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null \
          | jq -r --arg d "$DOMAIN" '.routes[]? | select(.domain == $d) | .domain' || true)

        VERIFY_SUFFIX=""
        $MULTI_CLUSTER && VERIFY_SUFFIX=" (${CLUSTER_ID})"

        if [[ "$VERIFY" == "$DOMAIN" ]]; then
          echo -e "${GREEN}Verified: ${DOMAIN} is in the proxy config for ${FIRST_NS}${VERIFY_SUFFIX}${RESET}"
        else
          echo -e "${YELLOW}Warning: ${DOMAIN} not yet in proxy config for ${FIRST_NS}${VERIFY_SUFFIX} — operator may still be reconciling${RESET}"
        fi
      done
    fi

    echo ""
  done
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# REVOKE
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "revoke" ]]; then
  echo ""
  echo -e "${BOLD}Removing ${YELLOW}${DOMAINS[*]}${RESET}${BOLD} from proxy allowlist...${RESET}"
  echo ""

  for entry in "${CLUSTER_ENTRIES[@]}"; do
    CLUSTER_ID="${entry%% *}"
    CLUSTER_KUBECONFIG="${entry#* }"

    $MULTI_CLUSTER && echo -e "${BOLD}── Cluster: ${CLUSTER_ID} ──${RESET}" && echo ""

    discover_namespaces "$CLUSTER_KUBECONFIG"

    REVOKE_TMPDIR=$(mktemp -d)
    JOB_COUNT=0

    for DOMAIN in "${DOMAINS[@]}"; do
      CRED_NAME=$(domain_to_name "$DOMAIN")
      SECRET_NAME="${CRED_NAME}-key"

      for NS in "${NAMESPACES[@]}"; do
        (
          # 1. Find the credential index in the Claw CR
          CRED_INDEX=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get claw instance -n "$NS" -o json 2>/dev/null \
            | jq --arg n "$CRED_NAME" '[.spec.credentials[]? | .name] | to_entries[] | select(.value == $n) | .key' || true)

          if [[ -z "$CRED_INDEX" ]]; then
            echo -e "  ${DIM}$NS: ${DOMAIN} not in allowlist — skipping${RESET}" > "${REVOKE_TMPDIR}/${NS}_${CRED_NAME}"
            exit 0
          fi

          # 2. Remove the credential from the Claw CR
          if KUBECONFIG="$CLUSTER_KUBECONFIG" oc patch claw instance -n "$NS" --type json \
            -p "[{\"op\":\"remove\",\"path\":\"/spec/credentials/${CRED_INDEX}\"}]" &>/dev/null; then
            echo -e "  ${GREEN}$NS: removed ${DOMAIN}${RESET}" > "${REVOKE_TMPDIR}/${NS}_${CRED_NAME}"
          else
            echo -e "  ${RED}$NS: failed to patch Claw CR for ${DOMAIN}${RESET}" > "${REVOKE_TMPDIR}/${NS}_${CRED_NAME}"
          fi

          # 3. Clean up the secret
          KUBECONFIG="$CLUSTER_KUBECONFIG" oc delete secret "$SECRET_NAME" -n "$NS" &>/dev/null || true
        ) &
        JOB_COUNT=$((JOB_COUNT + 1))
        if (( JOB_COUNT >= MAX_PARALLEL )); then
          wait
          JOB_COUNT=0
        fi
      done
    done
    wait

    # Print results in namespace order
    for NS in "${NAMESPACES[@]}"; do
      for DOMAIN in "${DOMAINS[@]}"; do
        CRED_NAME=$(domain_to_name "$DOMAIN")
        [[ -f "${REVOKE_TMPDIR}/${NS}_${CRED_NAME}" ]] && cat "${REVOKE_TMPDIR}/${NS}_${CRED_NAME}"
      done
    done
    rm -rf "$REVOKE_TMPDIR"

    echo ""
    echo -e "${DIM}Waiting for operator to reconcile...${RESET}"
    sleep 5

    # Verify all domains on first namespace of this cluster
    if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
      FIRST_NS="${NAMESPACES[0]}"
      for DOMAIN in "${DOMAINS[@]}"; do
        VERIFY=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get configmap instance-proxy-config -n "$FIRST_NS" \
          -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null \
          | jq -r --arg d "$DOMAIN" '.routes[]? | select(.domain == $d) | .domain' || true)

        VERIFY_SUFFIX=""
        $MULTI_CLUSTER && VERIFY_SUFFIX=" (${CLUSTER_ID})"

        if [[ -z "$VERIFY" ]]; then
          echo -e "${GREEN}Verified: ${DOMAIN} removed from proxy config for ${FIRST_NS}${VERIFY_SUFFIX}${RESET}"
        else
          echo -e "${YELLOW}Warning: ${DOMAIN} still in proxy config for ${FIRST_NS}${VERIFY_SUFFIX} — operator may still be reconciling${RESET}"
        fi
      done
    fi

    echo ""
  done
  exit 0
fi

# ── Unknown action ────────────────────────────────────────────────
echo "Error: unknown action '$ACTION'"
echo "Usage: $0 list|allow|revoke ..."
exit 1
