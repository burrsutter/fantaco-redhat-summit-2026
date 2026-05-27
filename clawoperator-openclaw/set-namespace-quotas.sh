#!/usr/bin/env bash
# set-namespace-quotas.sh — Apply ResourceQuotas to agentic-user namespaces
#
# Prevents any single namespace from consuming excessive cluster resources.
# Based on measured per-namespace footprint (12 pods, ~2.15c requests, ~3Gi mem).
#
# Usage:
#   ./set-namespace-quotas.sh 1 22        # agentic-user1 through agentic-user22
#   ./set-namespace-quotas.sh 3           # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Quota values ---
# Current workload: 12 pods, 2150m req CPU, 3Gi req mem, 7500m lim CPU, 8.25Gi lim mem
# Quotas include ~40% headroom over current pod sums.
QUOTA_REQUESTS_CPU="3"
QUOTA_REQUESTS_MEMORY="4Gi"
QUOTA_LIMITS_CPU="8"
QUOTA_LIMITS_MEMORY="10Gi"
QUOTA_PODS="16"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 1 22  → agentic-user1 through agentic-user22"
  echo "  $0 3     → just agentic-user3"
  exit 1
fi

START=$1
END=${2:-$START}

if [[ $START -gt $END ]]; then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo -e "${BOLD}Applying ResourceQuotas${RESET}"
echo -e "  ${DIM}requests.cpu:    ${QUOTA_REQUESTS_CPU}${RESET}"
echo -e "  ${DIM}requests.memory: ${QUOTA_REQUESTS_MEMORY}${RESET}"
echo -e "  ${DIM}limits.cpu:      ${QUOTA_LIMITS_CPU}${RESET}"
echo -e "  ${DIM}limits.memory:   ${QUOTA_LIMITS_MEMORY}${RESET}"
echo -e "  ${DIM}pods:            ${QUOTA_PODS}${RESET}"
echo ""

APPLIED=0
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"

  if ! oc get namespace "$NS" &>/dev/null; then
    echo -e "  ${YELLOW}⚠${RESET} ${NS}: namespace not found, skipping"
    continue
  fi

  cat <<EOF | oc apply -n "$NS" -f - >/dev/null
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
spec:
  hard:
    requests.cpu: "${QUOTA_REQUESTS_CPU}"
    requests.memory: "${QUOTA_REQUESTS_MEMORY}"
    limits.cpu: "${QUOTA_LIMITS_CPU}"
    limits.memory: "${QUOTA_LIMITS_MEMORY}"
    pods: "${QUOTA_PODS}"
EOF

  # Show current usage vs quota
  USED=$(oc get resourcequota namespace-quota -n "$NS" -o jsonpath='{.status.used}' 2>/dev/null || true)
  if [[ -n "$USED" ]]; then
    USED_CPU=$(echo "$USED" | python3 -c "import sys,json; print(json.load(sys.stdin).get('requests.cpu','?'))" 2>/dev/null || echo "?")
    USED_MEM=$(echo "$USED" | python3 -c "import sys,json; print(json.load(sys.stdin).get('requests.memory','?'))" 2>/dev/null || echo "?")
    USED_PODS=$(echo "$USED" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pods','?'))" 2>/dev/null || echo "?")
    echo -e "  ${GREEN}✓${RESET} ${NS}: quota applied (using ${USED_CPU} cpu, ${USED_MEM} mem, ${USED_PODS} pods)"
  else
    echo -e "  ${GREEN}✓${RESET} ${NS}: quota applied"
  fi

  APPLIED=$((APPLIED + 1))
done

echo ""
echo -e "${GREEN}Applied ResourceQuota to ${APPLIED} namespace(s)${RESET}"
