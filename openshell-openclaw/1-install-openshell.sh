#!/usr/bin/env bash
# install-openshell.sh
#
# Installs OpenShell into the current oc project namespace, starts a
# background port-forward, registers the gateway with the CLI, and
# creates the LLM provider.
#
# The cluster-admin operations (SCC grant, CRD install) must be done
# first via 0-cluster-admin-setup.sh.
#
# Prerequisites:
#   - oc logged in and project set (oc project <name>)
#   - Cluster-admin has already run 0-cluster-admin-setup.sh <namespace>
#   - Local OpenShell repo checkout (for patched Helm chart)
#
# Optional:
#   OPENSHELL_HOME   path to OpenShell repo (default: ../../OpenShell)
#   GATEWAY_PORT     local port for port-forward (default: 8081)
#   GATEWAY_NAME     name for the gateway registration (default: local)
#   LLM_PROVIDER     provider to use: anthropic (default), openai, or vllm
#   ANTHROPIC_API_KEY creates the Anthropic provider (when LLM_PROVIDER=anthropic)
#   OPENAI_API_KEY   creates the OpenAI provider (when LLM_PROVIDER=openai)
#   VLLM_API_KEY     creates the vLLM provider (when LLM_PROVIDER=vllm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/provider-config.sh"
NAMESPACE="$(oc project -q 2>/dev/null)"
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: Not logged in to an oc project. Run: oc project <namespace>"
  exit 1
fi

OPENSHELL_HOME="${OPENSHELL_HOME:-${SCRIPT_DIR}/../../OpenShell}"
CHART_PATH="${OPENSHELL_HOME}/deploy/helm/openshell"

if [ ! -d "$CHART_PATH" ]; then
  echo "ERROR: Helm chart not found at $CHART_PATH"
  echo "Set OPENSHELL_HOME to your OpenShell repo checkout."
  exit 1
fi

# --- Pre-flight: verify cluster-admin setup has been done ---
echo "--- Pre-flight checks ---"

PREFLIGHT_OK=true

# Check CRD via API discovery (works for namespace-scoped users)
if ! kubectl api-resources --api-group=agents.x-k8s.io 2>/dev/null | grep -q "Sandbox"; then
  echo "ERROR: The Sandbox CRD (agents.x-k8s.io) is not installed on this cluster."
  PREFLIGHT_OK=false
fi

if [ "$PREFLIGHT_OK" = false ]; then
  echo ""
  echo "A cluster-admin must run the following first:"
  echo "  ./0-cluster-admin-setup.sh $NAMESPACE"
  exit 1
fi

# Note: SCC grant cannot be verified by namespace-scoped users.
# If the privileged SCC is missing, the pod will fail to start and
# the wait step below will timeout with a clear error.

echo "Pre-flight checks passed."
echo ""

echo "============================================"
echo "  Installing OpenShell"
echo "============================================"
echo ""
echo "Namespace: $NAMESPACE"
echo "Chart:     $CHART_PATH"
echo ""

# --- Helm install (clusterRole.create=false: ClusterRole/ClusterRoleBinding pre-created by admin) ---
echo "--- Installing Helm chart ---"
# ClusterRole/ClusterRoleBinding names include the namespace to avoid
# collisions when multiple OpenShell installs exist on the same cluster.
# The service name stays "openshell" in every namespace.
# clusterRole.create=false skips the cluster-scoped resources that the
# namespace user cannot create — these are pre-created by 0-cluster-admin-setup.sh.
if helm status openshell -n "$NAMESPACE" &>/dev/null; then
  echo "Helm release 'openshell' already exists in $NAMESPACE — upgrading."
  helm upgrade openshell "$CHART_PATH" \
    -n "$NAMESPACE" \
    --set clusterRole.create=false \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null \
    --set image.tag=dev \
    --set supervisor.image.tag=dev
else
  helm install openshell "$CHART_PATH" \
    -n "$NAMESPACE" \
    --set clusterRole.create=false \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null \
    --set image.tag=dev \
    --set supervisor.image.tag=dev
fi
echo ""

# --- Wait for pod ---
echo "--- Waiting for gateway pod to be ready ---"
kubectl wait pod -l app.kubernetes.io/name=openshell -n "$NAMESPACE" \
  --for=condition=Ready --timeout=120s
echo ""

echo "OpenShell installed in $NAMESPACE."
echo ""

# --- Port-forward the gateway ---
GATEWAY_PORT="${GATEWAY_PORT:-8081}"
GATEWAY_NAME="${GATEWAY_NAME:-local}"

echo "============================================"
echo "  Registering Gateway"
echo "============================================"
echo ""
echo "Gateway port: $GATEWAY_PORT"
echo "Gateway name: $GATEWAY_NAME"
echo ""

# Kill any existing port-forward on this port
lsof -ti :"$GATEWAY_PORT" 2>/dev/null | xargs kill 2>/dev/null || true

# Start port-forward in background
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
echo "Port forward running in background (PID: $PF_PID)."
echo ""
echo "Next step — deploy OpenClaw:"
echo "  ./3-deploy-openclaw-sandbox.sh"
echo ""
