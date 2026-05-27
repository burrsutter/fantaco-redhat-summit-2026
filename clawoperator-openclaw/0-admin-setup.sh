#!/usr/bin/env bash
# 0-admin-setup.sh — Cluster-admin one-time setup for claw-operator
#
# Installs the claw-operator, patches memory limits, creates the claw-user
# ClusterRole, and grants RBAC to student users across namespaces.
#
# Usage:
#   ./0-admin-setup.sh 2 5          # agentic-user2 through agentic-user5
#   ./0-admin-setup.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX    — namespace/user prefix (default: agentic-user)
#   CLAW_OPERATOR_HOME  — path to claw-operator repo (default: ../../claw-operator)
#   REGISTRY            — container registry (default: quay.io/bsutter)
#   TAG                 — image tag (default: latest)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
CLAW_OPERATOR_HOME="${CLAW_OPERATOR_HOME:-../../claw-operator}"
REGISTRY="${REGISTRY:-quay.io/bsutter}"
TAG="${TAG:-v2026.5.26}"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 2 5   → agentic-user2 through agentic-user5"
  echo "  $0 3     → just agentic-user3"
  exit 1
fi

START=$1
END=${2:-$START}

if [[ $START -gt $END ]]; then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi

echo "=== Claw-Operator Admin Setup ==="
echo "Namespaces: ${NAMESPACE_PREFIX}${START} through ${NAMESPACE_PREFIX}${END}"
echo ""

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi
echo "Logged in as: $(oc whoami)"
echo ""

# ── Step 1: Install claw-operator (if not already running) ──────────
echo "--- Step 1: Install claw-operator ---"
OPERATOR_PODS=$(oc get pods -n claw-operator -l control-plane=controller-manager --no-headers 2>/dev/null | grep -c Running || true)

if [[ $OPERATOR_PODS -gt 0 ]]; then
  echo "Claw-operator is already running ($OPERATOR_PODS pod(s)). Skipping install."
else
  echo "Claw-operator not found. Installing from $CLAW_OPERATOR_HOME ..."

  if [[ ! -d "$CLAW_OPERATOR_HOME" ]]; then
    echo "Error: claw-operator repo not found at $CLAW_OPERATOR_HOME"
    echo "Set CLAW_OPERATOR_HOME to the correct path."
    exit 1
  fi

  (cd "$CLAW_OPERATOR_HOME" && make dev-deploy REGISTRY="$REGISTRY" TAG="$TAG")

  echo "Patching memory limits (512Mi limit, 128Mi request) ..."
  # Use JSON patch to set resources without clobbering env vars or other fields.
  # --type=merge on containers replaces the entire array, losing env vars like PROXY_IMAGE.
  oc patch deployment claw-operator-controller-manager -n claw-operator \
    --type=json -p '[
      {"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"limits":{"memory":"512Mi"},"requests":{"memory":"128Mi"}}}
    ]'

  echo "Waiting for operator pod to be ready ..."
  oc rollout status deployment/claw-operator-controller-manager -n claw-operator --timeout=120s
fi
echo ""

# ── Step 2: Enable User Workload Monitoring (for Prometheus/Grafana) ─
echo "--- Step 2: Enable User Workload Monitoring ---"
oc apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF
echo ""

# ── Step 3: Create claw-user ClusterRole ────────────────────────────
echo "--- Step 3: Create claw-user ClusterRole ---"
oc apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: claw-user
rules:
  - apiGroups: ["claw.sandbox.redhat.com"]
    resources: ["claws", "clawdevicepairingrequests"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF
echo ""

# ── Step 4: Grant RBAC per namespace ────────────────────────────────
echo "--- Step 4: Grant RBAC to students ---"
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  # Derive username: strip NAMESPACE_PREFIX, prepend "user"
  USER="user${i}"

  echo "  Granting claw-user to $USER in $NS ..."
  oc adm policy add-role-to-user claw-user "$USER" -n "$NS" --role-namespace=""
done
echo ""

echo "=== Admin setup complete ==="
echo "Next: run ./deploy-logs-loki.sh (see QUICKSTART.md for full steps)"
