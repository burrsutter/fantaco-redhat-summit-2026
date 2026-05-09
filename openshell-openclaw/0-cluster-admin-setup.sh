#!/usr/bin/env bash
# 0-cluster-admin-setup.sh
#
# Performs cluster-admin-only operations required before namespace users
# can install OpenShell with 1-install-openshell.sh.
#
# Usage:
#   ./0-cluster-admin-setup.sh <namespaces>
#
# Examples:
#   ./0-cluster-admin-setup.sh agentic-user1
#   ./0-cluster-admin-setup.sh agentic-user1,agentic-user2,agentic-user3
#   ./0-cluster-admin-setup.sh "agentic-user*"
#
# Supports comma-separated lists and wildcard patterns (matched against
# existing namespaces on the cluster).
#
# Prerequisites:
#   - oc logged in as cluster-admin
#   - Local OpenShell repo checkout (for agent-sandbox CRD manifest)
#
# Optional:
#   OPENSHELL_HOME   path to OpenShell repo (default: ../../OpenShell)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <namespaces>"
  echo ""
  echo "Performs cluster-admin-only setup for target namespaces."
  echo ""
  echo "Examples:"
  echo "  $0 agentic-user1"
  echo "  $0 agentic-user1,agentic-user2,agentic-user3"
  echo '  $0 "agentic-user*"'
  exit 1
fi

OPENSHELL_HOME="${OPENSHELL_HOME:-${SCRIPT_DIR}/../../OpenShell}"
CRD_PATH="${OPENSHELL_HOME}/deploy/kube/manifests/agent-sandbox.yaml"

if [ ! -f "$CRD_PATH" ]; then
  echo "ERROR: Agent Sandbox manifest not found at $CRD_PATH"
  echo "Set OPENSHELL_HOME to your OpenShell repo checkout."
  exit 1
fi

# --- Resolve namespace list ---
# Split on commas, expand wildcards against existing namespaces.
ALL_NAMESPACES=$(oc get namespaces -o jsonpath='{.items[*].metadata.name}')
RESOLVED_NAMESPACES=()

IFS=',' read -ra INPUT_PATTERNS <<< "$1"
for pattern in "${INPUT_PATTERNS[@]}"; do
  pattern=$(echo "$pattern" | xargs)  # trim whitespace
  matched=false
  for ns in $ALL_NAMESPACES; do
    # shellcheck disable=SC2254
    case "$ns" in
      $pattern) RESOLVED_NAMESPACES+=("$ns"); matched=true ;;
    esac
  done
  if [ "$matched" = false ]; then
    echo "WARNING: No namespaces matched pattern '$pattern'"
  fi
done

# Deduplicate
NAMESPACES=($(printf '%s\n' "${RESOLVED_NAMESPACES[@]}" | sort -u))

if [ ${#NAMESPACES[@]} -eq 0 ]; then
  echo "ERROR: No namespaces matched. Check your input."
  exit 1
fi

echo "============================================"
echo "  Cluster-Admin Setup for OpenShell"
echo "============================================"
echo ""
echo "Target namespaces (${#NAMESPACES[@]}):"
for ns in "${NAMESPACES[@]}"; do
  echo "  - $ns"
done
echo ""

# --- Cluster-wide: Agent Sandbox CRD + controller (once) ---
echo "--- Applying Agent Sandbox CRD and controller ---"
kubectl apply -f "$CRD_PATH"
echo ""

# --- Per-namespace setup ---
setup_namespace() {
  local NAMESPACE="$1"

  echo "=== Setting up namespace: $NAMESPACE ==="

  # SCC
  echo "  Adding privileged SCC to default service account..."
  oc adm policy add-scc-to-user privileged -z default -n "$NAMESPACE"

  # ClusterRole + ClusterRoleBinding for node-reader
  echo "  Creating ClusterRole and ClusterRoleBinding for node-reader..."
  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshell-${NAMESPACE}-node-reader
rules:
  - apiGroups: [""]
    resources: [nodes]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshell-${NAMESPACE}-node-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: openshell-${NAMESPACE}-node-reader
subjects:
  - kind: ServiceAccount
    name: openshell
    namespace: ${NAMESPACE}
EOF

  # Namespace-scoped Role + RoleBinding for sandbox management
  echo "  Creating Role and RoleBinding for sandbox management..."
  kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openshell-sandbox
  namespace: ${NAMESPACE}
rules:
  - apiGroups: [agents.x-k8s.io]
    resources: [sandboxes, sandboxes/status]
    verbs: [create, delete, get, list, patch, update, watch]
  - apiGroups: [""]
    resources: [events]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: openshell-sandbox
  namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: openshell-sandbox
subjects:
  - kind: ServiceAccount
    name: openshell
    namespace: ${NAMESPACE}
EOF

  echo "  Done: $NAMESPACE"
  echo ""
}

for ns in "${NAMESPACES[@]}"; do
  setup_namespace "$ns"
done

echo "============================================"
echo "  Cluster-admin setup complete"
echo "============================================"
echo ""
echo "Namespace users can now run:"
for ns in "${NAMESPACES[@]}"; do
  echo "  oc project $ns && ./1-install-openshell.sh"
done
echo ""
