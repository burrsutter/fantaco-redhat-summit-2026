#!/usr/bin/env bash
# manage-heartbeat.sh — Enable or disable the OpenClaw heartbeat across namespaces
#
# The heartbeat runs every 30 minutes per instance and consumes LLM tokens.
# With 50 instances that's 100 LLM calls/hour even with no humans active.
# Use this script to disable heartbeat when the cluster is idle.
#
# Multi-cluster mode:
#   If clusters.csv exists (see clusters.csv.example), the action is applied
#   across all listed clusters. Otherwise, uses the current oc context.
#
# Usage:
#   ./manage-heartbeat.sh disable          # disable on all agentic-user namespaces
#   ./manage-heartbeat.sh enable           # enable on all
#   ./manage-heartbeat.sh disable 1 5      # disable on user1 through user5
#   ./manage-heartbeat.sh enable 3         # enable on just user3
#   ./manage-heartbeat.sh status           # show heartbeat state on all
#   ./manage-heartbeat.sh status 1 5       # show state on user1 through user5

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <enable|disable|status> [start] [end]"
  echo ""
  echo "  enable   — enable heartbeat (default 30-min interval)"
  echo "  disable  — disable heartbeat (stops LLM token consumption)"
  echo "  status   — show current heartbeat state"
  exit 1
fi

ACTION="$1"
shift

if [[ "$ACTION" != "enable" && "$ACTION" != "disable" && "$ACTION" != "status" ]]; then
  echo "Error: action must be 'enable', 'disable', or 'status'"
  exit 1
fi

NS_START=""
NS_END=""
if [[ $# -ge 1 ]]; then
  NS_START="$1"
  NS_END="${2:-$NS_START}"
fi

# ── Build cluster list ──────────────────────────────────────────────
CLUSTER_IDS=()
CLUSTER_KUBECONFIGS=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})"
      exit 1
    fi
    CLUSTER_IDS+=("$cluster_id")
    CLUSTER_KUBECONFIGS+=("$kubeconfig_path")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_IDS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
  echo -e "${BOLD}Multi-cluster mode:${RESET} ${#CLUSTER_IDS[@]} cluster(s)"
  echo ""
else
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  CLUSTER_IDS+=("default")
  CLUSTER_KUBECONFIGS+=("${KUBECONFIG:-$HOME/.kube/config}")
fi

# ── Process each cluster ────────────────────────────────────────────
TOTAL_SUCCESS=0
TOTAL_FAIL=0
_ORIG_KUBECONFIG="${KUBECONFIG:-}"

for ci in "${!CLUSTER_IDS[@]}"; do
  CID="${CLUSTER_IDS[$ci]}"
  CKUBE="${CLUSTER_KUBECONFIGS[$ci]}"
  export KUBECONFIG="$CKUBE"

  DOMAIN=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*//api\.\(.*\):.*|\1|' | sed 's/^ocp\./apps.ocp./')

  if [[ ${#CLUSTER_IDS[@]} -gt 1 ]]; then
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║  Cluster: ${CID} (${DOMAIN})${RESET}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
  fi

  # Build namespace list for this cluster
  NAMESPACES=()
  if [[ -z "$NS_START" ]]; then
    while IFS= read -r ns; do
      NAMESPACES+=("$ns")
    done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
      echo -e "  ${YELLOW}No ${NAMESPACE_PREFIX}* namespaces found on ${CID} — skipping${RESET}"
      echo ""
      continue
    fi
  else
    for i in $(seq "$NS_START" "$NS_END"); do
      NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
    done
  fi

  echo -e "${BOLD}Heartbeat: ${ACTION} on ${#NAMESPACES[@]} namespace(s)${RESET}"
  echo ""

  SUCCESS=0
  FAIL=0

  for NS in "${NAMESPACES[@]}"; do
    # Check pod exists
    POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
      | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)
    if [[ -z "$POD" ]]; then
      echo -e "  ${YELLOW}$NS: no running gateway pod — skipping${RESET}"
      FAIL=$((FAIL + 1))
      continue
    fi

    if [[ "$ACTION" == "status" ]]; then
      STATE=$(oc exec deployment/instance -n "$NS" -c gateway -- node -e "
        const c = JSON.parse(require('fs').readFileSync('/home/node/.openclaw/openclaw.json'));
        const hb = c.agents?.defaults?.heartbeat;
        if (!hb || Object.keys(hb).length === 0) { console.log('disabled'); }
        else { console.log('enabled'); }
      " 2>/dev/null || echo "unknown")
      if [[ "$STATE" == "enabled" ]]; then
        echo -e "  ${GREEN}●${RESET} $NS: enabled"
      elif [[ "$STATE" == "disabled" ]]; then
        echo -e "  ${RED}○${RESET} $NS: disabled"
      else
        echo -e "  ${YELLOW}?${RESET} $NS: unknown"
      fi
      SUCCESS=$((SUCCESS + 1))
    else
      RESULT=$(oc exec deployment/instance -n "$NS" -c gateway -- \
        node /app/dist/index.js system heartbeat "$ACTION" 2>/dev/null || echo '{"ok": false}')
      OK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok',False))" 2>/dev/null || echo "False")
      if [[ "$OK" == "True" ]]; then
        if [[ "$ACTION" == "disable" ]]; then
          echo -e "  ${RED}○${RESET} $NS: disabled"
        else
          echo -e "  ${GREEN}●${RESET} $NS: enabled"
        fi
        SUCCESS=$((SUCCESS + 1))
      else
        echo -e "  ${YELLOW}⚠${RESET} $NS: failed ($RESULT)"
        FAIL=$((FAIL + 1))
      fi
    fi
  done

  echo ""
  echo -e "${BOLD}${CID}:${RESET} ${SUCCESS} succeeded, ${FAIL} failed"
  echo ""

  TOTAL_SUCCESS=$((TOTAL_SUCCESS + SUCCESS))
  TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
done

# Restore original KUBECONFIG so we don't leak the last cluster's context
if [[ -n "$_ORIG_KUBECONFIG" ]]; then
  export KUBECONFIG="$_ORIG_KUBECONFIG"
else
  unset KUBECONFIG
fi

if [[ ${#CLUSTER_IDS[@]} -gt 1 ]]; then
  echo -e "${BOLD}Total:${RESET} ${TOTAL_SUCCESS} succeeded, ${TOTAL_FAIL} failed across ${#CLUSTER_IDS[@]} cluster(s)"
fi
