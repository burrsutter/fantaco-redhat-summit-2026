#!/usr/bin/env bash
# port-forward-openshell.sh
#
# Port forwards the OpenShell gateway, registers it with the CLI, creates
# the LLM provider, and verifies connectivity.
#
# Run in a separate terminal and leave it running — the other scripts need
# the gateway to be reachable.
#
# Optional:
#   OPENSHELL_HOME    path to OpenShell repo (default: ../../OpenShell)
#   GATEWAY_PORT      local port for port-forward (default: 8081)
#   GATEWAY_NAME      name for the gateway registration (default: local)
#   LLM_PROVIDER      provider to use: anthropic (default), openai, or vllm
#   ANTHROPIC_API_KEY creates the Anthropic provider (when LLM_PROVIDER=anthropic)
#   OPENAI_API_KEY    creates the OpenAI provider (when LLM_PROVIDER=openai)
#   VLLM_API_KEY      creates the vLLM provider (when LLM_PROVIDER=vllm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/provider-config.sh"
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

# --- Create LLM provider ---
if [ -n "$PROVIDER_API_KEY" ]; then
  echo "--- Creating ${PROVIDER_NAME} provider ---"
  openshell provider create --name "$PROVIDER_NAME" --type generic \
    --credential "$PROVIDER_API_KEY_VAR" 2>/dev/null \
    || echo "Provider '${PROVIDER_NAME}' may already exist."
  echo ""
else
  echo "--- Skipping ${PROVIDER_NAME} provider (${PROVIDER_API_KEY_VAR} not set) ---"
  echo "Run later: openshell provider create --name ${PROVIDER_NAME} --type generic --credential ${PROVIDER_API_KEY_VAR}"
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
