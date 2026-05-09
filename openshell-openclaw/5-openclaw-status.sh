#!/usr/bin/env bash
# openclaw-status.sh
#
# Quick health check for OpenClaw: verifies the sandbox pod is running,
# the gateway process is alive inside it, the UI port-forward is working,
# and the config looks sane.
#
# Optional:
#   NAMESPACE env var (default: current oc project)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSHELL="${SCRIPT_DIR}/openshell.sh"
NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"
ERRORS=0

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

echo "============================================"
echo "  OpenClaw Health Check"
echo "============================================"
echo ""
echo "Namespace: $NAMESPACE"
echo ""

# --- Check sandbox pod ---
echo "--- Sandbox pod ---"
POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 || true)
if [ -n "$POD" ]; then
  STATUS=$(echo "$POD" | awk '{print $3}')
  NAME=$(echo "$POD" | awk '{print $1}')
  if [ "$STATUS" = "Running" ]; then
    echo "OK: $NAME ($STATUS)"
  else
    echo "FAIL: $NAME ($STATUS)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "FAIL: No pod found with label app=openclaw in $NAMESPACE"
  ERRORS=$((ERRORS + 1))
fi
POD_NAME=$(echo "$POD" | awk '{print $1}')
echo ""

# --- Check gateway process inside pod ---
echo "--- OpenClaw gateway process ---"
if [ -n "$POD_NAME" ]; then
  if oc exec "$POD_NAME" -n "$NAMESPACE" -- sh -c 'cat /proc/*/cmdline 2>/dev/null | tr "\0" "\n" | grep -q "openclaw"' 2>/dev/null; then
    echo "OK: openclaw gateway is running"
  else
    echo "FAIL: openclaw gateway process not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "SKIP: No pod to check"
fi
echo ""

# --- Check gateway logs for errors ---
echo "--- Gateway log (last 10 lines) ---"
if [ -n "$POD_NAME" ]; then
  LOG=$(oc exec "$POD_NAME" -n "$NAMESPACE" -- cat /tmp/gateway.log 2>/dev/null | tail -10 || true)
  if [ -n "$LOG" ]; then
    echo "$LOG"
    if echo "$LOG" | grep -qi "error\|panic\|fatal"; then
      echo ""
      echo "WARN: Errors detected in gateway log"
    fi
  else
    echo "WARN: No gateway log found at /tmp/gateway.log"
  fi
else
  echo "SKIP: No pod to check"
fi
echo ""

# --- Check config ---
echo "--- OpenClaw config ---"
if [ -n "$POD_NAME" ]; then
  if oc exec "$POD_NAME" -n "$NAMESPACE" -- test -f /sandbox/.openclaw/openclaw.json 2>/dev/null; then
    echo "OK: openclaw.json exists"
    # Check bot token is not the placeholder
    if oc exec "$POD_NAME" -n "$NAMESPACE" -- grep -q '"botToken": "REPLACE_ME"' /sandbox/.openclaw/openclaw.json 2>/dev/null; then
      echo "FAIL: botToken is still REPLACE_ME"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK: botToken is set"
    fi
  else
    echo "FAIL: /sandbox/.openclaw/openclaw.json not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "SKIP: No pod to check"
fi
echo ""

# --- Check sandbox via OpenShell CLI ---
echo "--- OpenShell sandbox ---"
SANDBOX_NAME=$("$OPENSHELL" sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1 || true)
if [ -n "$SANDBOX_NAME" ]; then
  echo "OK: Sandbox '$SANDBOX_NAME' exists"
else
  echo "FAIL: No sandbox found via openshell CLI"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Check UI Route ---
echo "--- OpenClaw UI Route ---"
ROUTE_HOST=$(oc get route openclaw-ui -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [ -n "$ROUTE_HOST" ]; then
  echo "OK: Route exists (https://${ROUTE_HOST}/)"
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "https://${ROUTE_HOST}/" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "OK: UI reachable (HTTP $HTTP_CODE)"
  else
    echo "WARN: UI returned HTTP $HTTP_CODE"
  fi
else
  echo "FAIL: Route 'openclaw-ui' not found in $NAMESPACE"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Summary ---
if [ "$ERRORS" -eq 0 ]; then
  echo "============================================"
  echo "  All checks passed"
  echo "============================================"
else
  echo "============================================"
  echo "  $ERRORS check(s) failed"
  echo "============================================"
  exit 1
fi
