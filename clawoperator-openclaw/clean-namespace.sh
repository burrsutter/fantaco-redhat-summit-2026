#!/usr/bin/env bash
# clean-namespace.sh — Remove claw-operator resources from student namespaces
#
# Deletes Claw CR, secrets, and waits for pods to terminate.
# Does NOT remove cluster-admin resources (operator, ClusterRole).
#
# Usage:
#   ./clean-namespace.sh              # clean current namespace (student mode)
#   ./clean-namespace.sh 2 5          # clean agentic-user2 through agentic-user5
#   ./clean-namespace.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  CURRENT_NS=$(oc project -q 2>/dev/null) || { echo "Error: cannot detect current namespace. Run 'oc project <ns>' first."; exit 1; }
  NAMESPACES+=("$CURRENT_NS")
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo "Error: start ($START) must be <= end ($END)"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # clean current namespace"
  echo "       $0 <start> [end]  # clean agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  Claw-Operator Namespace Cleanup"
echo "============================================"
echo ""
echo "Namespaces to clean:"
for NS in "${NAMESPACES[@]}"; do
  echo "  - ${NS}"
done
echo ""
echo "This removes student-user resources (Claw CR + secrets)."
echo "Cluster-admin resources (operator, ClusterRole) are preserved."
echo ""

# ── Per-namespace cleanup ──────────────────────────────────────────
for NS in "${NAMESPACES[@]}"; do
  echo "=== Cleaning namespace: $NS ==="

  # Delete Claw CR (triggers operator cleanup of deployments/services/routes)
  echo "  Deleting Claw CR..."
  oc delete claw instance -n "$NS" 2>/dev/null && echo "    Deleted." || echo "    Not found (skipping)."

  # Wait for pods to terminate (operator handles teardown)
  echo "  Waiting for pods to terminate..."
  for attempt in $(seq 1 24); do
    COUNT=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$COUNT" == "0" ]]; then
      break
    fi
    sleep 5
  done
  REMAINING=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$REMAINING" == "0" ]]; then
    echo "    Pods cleared."
  else
    echo "    WARN: $REMAINING pod(s) still present after 120s."
  fi

  # Delete secrets
  echo "  Deleting secrets..."
  for SECRET in litellm-api-key anthropic-api-key openai-api-key claw-password; do
    oc delete secret "$SECRET" -n "$NS" 2>/dev/null && echo "    Deleted $SECRET" || true
  done

  echo "  Namespace $NS cleaned."
  echo ""
done

echo "============================================"
echo "  Cleanup complete!"
echo "============================================"
echo ""
echo "Re-run the deployment:"
echo "  ./1-deploy-claw.sh"
