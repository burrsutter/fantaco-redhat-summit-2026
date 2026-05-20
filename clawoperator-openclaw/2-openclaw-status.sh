#!/usr/bin/env bash
# 2-openclaw-status.sh — Health check for claw-operator deployed OpenClaw
#
# Checks claw-operator pods, Claw CR conditions, gateway logs, and Route.
#
# Usage:
#   ./2-openclaw-status.sh 2 5          # check agentic-user2 through agentic-user5
#   ./2-openclaw-status.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 2 5   → check agentic-user2 through agentic-user5"
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

TOTAL_ERRORS=0

for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  ERRORS=0

  echo "============================================"
  echo "  OpenClaw Health Check — $NS"
  echo "============================================"
  echo ""

  # --- Check claw-operator pods ---
  echo "--- Claw-operator pods (cluster-wide) ---"
  OPERATOR_RUNNING=$(oc get pods -n claw-operator -l control-plane=controller-manager --no-headers 2>/dev/null | grep -c Running || true)
  if [[ $OPERATOR_RUNNING -gt 0 ]]; then
    echo "OK: claw-operator running ($OPERATOR_RUNNING pod(s))"
  else
    echo "FAIL: claw-operator not running in namespace claw-operator"
    ERRORS=$((ERRORS + 1))
  fi
  echo ""

  # --- Check instance pods ---
  echo "--- Instance pods ($NS) ---"
  for DEPLOY in instance instance-proxy instance-device-pairing; do
    POD_LINE=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null | grep "^${DEPLOY}-" | head -1 || true)
    if [[ -n "$POD_LINE" ]]; then
      POD_STATUS=$(echo "$POD_LINE" | awk '{print $3}')
      POD_NAME=$(echo "$POD_LINE" | awk '{print $1}')
      if [[ "$POD_STATUS" == "Running" ]]; then
        echo "OK: $POD_NAME ($POD_STATUS)"
      else
        echo "FAIL: $POD_NAME ($POD_STATUS)"
        ERRORS=$((ERRORS + 1))
      fi
    else
      echo "FAIL: No pod found for deployment $DEPLOY"
      ERRORS=$((ERRORS + 1))
    fi
  done
  echo ""

  # --- Check Claw CR status conditions ---
  echo "--- Claw CR conditions ---"
  CONDITIONS=$(oc get claw instance -n "$NS" -o jsonpath='{range .status.conditions[*]}{.type}: {.status} ({.message}){"\n"}{end}' 2>/dev/null || true)
  if [[ -n "$CONDITIONS" ]]; then
    echo "$CONDITIONS"
  else
    echo "WARN: No status conditions found on Claw CR"
  fi
  echo ""

  # --- Check gateway logs ---
  echo "--- Gateway log (last 10 lines) ---"
  LOG=$(oc logs deployment/instance -n "$NS" -c gateway --tail=10 2>/dev/null || true)
  if [[ -n "$LOG" ]]; then
    echo "$LOG"
    if echo "$LOG" | grep -qi "error\|panic\|fatal"; then
      echo ""
      echo "WARN: Errors detected in gateway log"
    fi
  else
    echo "WARN: No gateway logs available"
  fi
  echo ""

  # --- Check Route / URL ---
  echo "--- OpenClaw URL ---"
  URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
  if [[ -n "$URL" ]]; then
    echo "OK: $URL"
    HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
      echo "OK: UI reachable (HTTP $HTTP_CODE)"
    else
      echo "WARN: UI returned HTTP $HTTP_CODE"
    fi
  else
    echo "FAIL: No URL found in Claw CR status"
    ERRORS=$((ERRORS + 1))
  fi
  echo ""

  # --- Summary for this namespace ---
  if [[ $ERRORS -eq 0 ]]; then
    echo "  ✓ $NS: All checks passed"
  else
    echo "  ✗ $NS: $ERRORS check(s) failed"
  fi
  echo ""

  TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))
done

# --- Overall summary ---
echo "============================================"
if [[ $TOTAL_ERRORS -eq 0 ]]; then
  echo "  All checks passed"
else
  echo "  $TOTAL_ERRORS total check(s) failed"
fi
echo "============================================"

[[ $TOTAL_ERRORS -eq 0 ]] || exit 1
