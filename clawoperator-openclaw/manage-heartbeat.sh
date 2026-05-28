#!/usr/bin/env bash
# manage-heartbeat.sh — Enable or disable the OpenClaw heartbeat across namespaces
#
# The heartbeat runs every 30 minutes per instance and consumes LLM tokens.
# With 40 instances that's 80 LLM calls/hour even with no humans active.
# Use this script to disable heartbeat when the cluster is idle.
#
# Usage:
#   ./manage-heartbeat.sh disable          # disable on all agentic-user namespaces
#   ./manage-heartbeat.sh enable           # enable on all
#   ./manage-heartbeat.sh disable 1 5      # disable on user1 through user5
#   ./manage-heartbeat.sh enable 3         # enable on just user3
#   ./manage-heartbeat.sh status           # show heartbeat state on all
#   ./manage-heartbeat.sh status 1 5       # show state on user1 through user5

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
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

NAMESPACES=()
if [[ $# -eq 0 ]]; then
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo "Error: No ${NAMESPACE_PREFIX}* namespaces found."
    exit 1
  fi
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  for i in $(seq "$START" "$END"); do
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
    # No direct status command — check config file for heartbeat state
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
echo -e "${BOLD}Done:${RESET} ${SUCCESS} succeeded, ${FAIL} failed"
