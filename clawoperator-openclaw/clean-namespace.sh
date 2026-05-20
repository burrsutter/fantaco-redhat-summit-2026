#!/usr/bin/env bash
# clean-namespace.sh — Remove claw-operator resources from student namespaces
#
# Deletes Claw CR, secrets, and waits for pods to terminate.
# Does NOT remove cluster-admin resources (operator, ClusterRole).
#
# Usage:
#   ./clean-namespace.sh 2 5          # clean agentic-user2 through agentic-user5
#   ./clean-namespace.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 2 5   → clean agentic-user2 through agentic-user5"
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

echo "============================================"
echo "  Claw-Operator Namespace Cleanup"
echo "============================================"
echo ""
echo "Namespaces to clean:"
for i in $(seq "$START" "$END"); do
  echo "  - ${NAMESPACE_PREFIX}${i}"
done
echo ""
echo "This removes student-user resources (Claw CR + secrets)."
echo "Cluster-admin resources (operator, ClusterRole) are preserved."
echo ""

# ── Per-namespace cleanup ──────────────────────────────────────────
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
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
for i in $(seq "$START" "$END"); do
  echo "  ./1-deploy-claw.sh $i"
done
