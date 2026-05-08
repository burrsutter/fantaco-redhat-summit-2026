#!/usr/bin/env bash
# port-forward-openshell.sh
#
# Port forwards the OpenShell gateway, registers it with the CLI, creates
# the OpenAI provider, and verifies connectivity.
#
# Run in a separate terminal and leave it running — the other scripts need
# the gateway to be reachable.
#
# Optional:
#   OPENSHELL_HOME   path to OpenShell repo (default: ../../OpenShell)
#   GATEWAY_PORT     local port for port-forward (default: 8081)
#   GATEWAY_NAME     name for the gateway registration (default: local)
#   OPENAI_API_KEY   creates the OpenAI provider if set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="$(oc project -q 2>/dev/null)"
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: Not logged in to an oc project. Run: oc project <namespace>"
  exit 1
fi

GATEWAY_PORT="${GATEWAY_PORT:-8081}"
GATEWAY_NAME="${GATEWAY_NAME:-local}"

echo "============================================"
echo "  OpenShell Gateway Port-Forward"
echo "============================================"
echo ""
echo "Namespace:    $NAMESPACE"
echo "Gateway port: $GATEWAY_PORT"
echo "Gateway name: $GATEWAY_NAME"
echo ""

# --- Kill any existing port-forward on this port ---
lsof -ti :"$GATEWAY_PORT" 2>/dev/null | xargs kill 2>/dev/null || true

# --- Start port-forward in background ---
echo "--- Starting port-forward on localhost:${GATEWAY_PORT} ---"
kubectl -n "$NAMESPACE" port-forward svc/openshell "${GATEWAY_PORT}:8080" &
PF_PID=$!
sleep 3

if ! kill -0 "$PF_PID" 2>/dev/null; then
  echo "ERROR: Port forward failed to start."
  exit 1
fi
echo "Port forward PID: $PF_PID"
echo ""

# --- Register gateway ---
echo "--- Registering gateway ---"
openshell gateway remove "$GATEWAY_NAME" 2>/dev/null || true
openshell gateway add "http://127.0.0.1:${GATEWAY_PORT}" --local --name "$GATEWAY_NAME"
openshell gateway select "$GATEWAY_NAME"
echo ""

# --- Create OpenAI provider ---
if [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "--- Creating OpenAI provider ---"
  openshell provider create --name openai --type generic --credential OPENAI_API_KEY 2>/dev/null || echo "Provider 'openai' may already exist."
  echo ""
else
  echo "--- Skipping OpenAI provider (OPENAI_API_KEY not set) ---"
  echo "Run later: openshell provider create --name openai --type generic --credential OPENAI_API_KEY"
  echo ""
fi

# --- Verify ---
echo "--- Verifying gateway ---"
openshell status
echo ""

echo "============================================"
echo "  Gateway ready on localhost:${GATEWAY_PORT}"
echo "============================================"
echo ""
echo "Keep this terminal running. Press Ctrl+C to stop."
echo ""
echo "Next step — deploy OpenClaw:"
echo "  ./3-deploy-openclaw-sandbox.sh"
echo ""

# Wait on the port-forward so Ctrl+C stops it cleanly
wait "$PF_PID"
