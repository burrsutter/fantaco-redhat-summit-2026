#!/usr/bin/env bash
# 3-open-openclaw.sh — Open OpenClaw UI in the browser (claw-operator)
#
# Gets the URL from the Claw CR status and opens it.
#
# Usage:
#   ./3-open-openclaw.sh 2 5          # open agentic-user2 through agentic-user5
#   ./3-open-openclaw.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 2 5   → open agentic-user2 through agentic-user5"
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

for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"

  URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
  if [[ -z "$URL" ]]; then
    echo "ERROR: No URL found for Claw instance in $NS"
    echo "  Run ./1-deploy-claw.sh $i first."
    continue
  fi

  echo "$NS: $URL"
  open "$URL"
done

echo ""
echo "Students enter the password when prompted."
