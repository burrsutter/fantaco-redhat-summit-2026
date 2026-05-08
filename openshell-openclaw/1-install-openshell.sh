#!/usr/bin/env bash
# install-openshell.sh
#
# Installs OpenShell into the current oc project namespace.
# Handles SCC, Helm install (from local patched chart), and CRD.
#
# Prerequisites:
#   - oc logged in and project set (oc project <name>)
#   - Local OpenShell repo checkout (for patched Helm chart)
#
# Optional:
#   OPENSHELL_HOME   path to OpenShell repo (default: ../../OpenShell)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="$(oc project -q 2>/dev/null)"
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: Not logged in to an oc project. Run: oc project <namespace>"
  exit 1
fi

OPENSHELL_HOME="${OPENSHELL_HOME:-${SCRIPT_DIR}/../../OpenShell}"
CHART_PATH="${OPENSHELL_HOME}/deploy/helm/openshell"
CRD_PATH="${OPENSHELL_HOME}/deploy/kube/manifests/agent-sandbox.yaml"

if [ ! -d "$CHART_PATH" ]; then
  echo "ERROR: Helm chart not found at $CHART_PATH"
  echo "Set OPENSHELL_HOME to your OpenShell repo checkout."
  exit 1
fi

echo "============================================"
echo "  Installing OpenShell"
echo "============================================"
echo ""
echo "Namespace: $NAMESPACE"
echo "Chart:     $CHART_PATH"
echo ""

# --- Step 1: SCC ---
echo "--- Adding privileged SCC to default service account ---"
oc adm policy add-scc-to-user privileged -z default -n "$NAMESPACE"
echo ""

# --- Step 2: Helm install ---
echo "--- Installing Helm chart ---"
# ClusterRole/ClusterRoleBinding names include the namespace to avoid
# collisions when multiple OpenShell installs exist on the same cluster.
# The service name stays "openshell" in every namespace.
if helm status openshell -n "$NAMESPACE" &>/dev/null; then
  echo "Helm release 'openshell' already exists in $NAMESPACE — upgrading."
  helm upgrade openshell "$CHART_PATH" \
    -n "$NAMESPACE" \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null \
    --set image.tag=dev \
    --set supervisor.image.tag=dev
else
  helm install openshell "$CHART_PATH" \
    -n "$NAMESPACE" \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null \
    --set image.tag=dev \
    --set supervisor.image.tag=dev
fi
echo ""

# --- Step 3: CRD ---
echo "--- Applying Agent Sandbox CRD ---"
kubectl apply -f "$CRD_PATH"
echo ""

# --- Step 4: Wait for pod ---
echo "--- Waiting for gateway pod to be ready ---"
kubectl wait pod -l app.kubernetes.io/name=openshell -n "$NAMESPACE" \
  --for=condition=Ready --timeout=120s
echo ""

echo "============================================"
echo "  OpenShell installed in $NAMESPACE"
echo "============================================"
echo ""
echo "Next step — start the gateway port-forward:"
echo "  ./2-port-forward-openshell.sh"
echo ""
