#!/usr/bin/env bash
# openshell-status.sh
#
# Quick health check: verifies the gateway port-forward is running,
# the CLI can reach the gateway, and the provider is configured.
#
# Optional:
#   GATEWAY_PORT   local port for port-forward (default: 8081)
#   GATEWAY_NAME   CLI gateway name (default: local)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSHELL="${SCRIPT_DIR}/openshell.sh"
GATEWAY_PORT="${GATEWAY_PORT:-8081}"
GATEWAY_NAME="${GATEWAY_NAME:-local}"
NAMESPACE="$(oc project -q 2>/dev/null || echo unknown)"
ERRORS=0

echo "============================================"
echo "  OpenShell Health Check"
echo "============================================"
echo ""
echo "Namespace: $NAMESPACE"
echo ""

# --- Check port-forward ---
echo "--- Port-forward (localhost:${GATEWAY_PORT}) ---"
PF_PID=$(lsof -ti :"$GATEWAY_PORT" 2>/dev/null || true)
if [ -n "$PF_PID" ]; then
  echo "OK: Port-forward running (PID: $PF_PID)"
else
  echo "FAIL: No process listening on port $GATEWAY_PORT"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Check gateway pod ---
echo "--- Gateway pod ---"
POD=$(oc get pods -l app.kubernetes.io/name=openshell -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 || true)
if [ -n "$POD" ]; then
  STATUS=$(echo "$POD" | awk '{print $3}')
  NAME=$(echo "$POD" | awk '{print $1}')
  if [ "$STATUS" = "Running" ]; then
    echo "OK: $NAME ($STATUS)"
  else
    echo "WARN: $NAME ($STATUS)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "FAIL: No gateway pod found in $NAMESPACE"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Check CLI gateway registration ---
echo "--- CLI gateway ---"
if "$OPENSHELL" gateway list 2>/dev/null | grep -q "$GATEWAY_NAME"; then
  echo "OK: Gateway '$GATEWAY_NAME' registered"
else
  echo "FAIL: Gateway '$GATEWAY_NAME' not registered"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Check gateway connectivity ---
echo "--- Gateway status ---"
if "$OPENSHELL" status 2>/dev/null; then
  echo ""
  echo "OK: Gateway reachable"
else
  echo "FAIL: Cannot reach gateway"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# --- Check providers ---
echo "--- Providers ---"
PROVIDERS=$("$OPENSHELL" provider list 2>/dev/null || true)
if [ -n "$PROVIDERS" ]; then
  echo "$PROVIDERS"
else
  echo "WARN: No providers configured (or CLI cannot reach gateway)"
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
