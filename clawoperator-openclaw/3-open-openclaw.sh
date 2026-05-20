#!/usr/bin/env bash
# 3-open-openclaw.sh — Open OpenClaw UI in the browser (claw-operator)
#
# Gets the URL from the Claw CR status and opens it.
#
# Usage:
#   ./3-open-openclaw.sh              # open current namespace (student mode)
#   ./3-open-openclaw.sh 2 5          # open agentic-user2 through agentic-user5
#   ./3-open-openclaw.sh 3            # just agentic-user3
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
  echo "Usage: $0                # open current namespace"
  echo "       $0 <start> [end]  # open agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

for NS in "${NAMESPACES[@]}"; do
  URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
  if [[ -z "$URL" ]]; then
    echo "ERROR: No URL found for Claw instance in $NS"
    echo "  Run ./1-deploy-claw.sh first."
    continue
  fi

  echo "$NS: $URL"
  open "$URL"
done

echo ""
echo "Students enter the password when prompted."
