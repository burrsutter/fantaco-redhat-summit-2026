#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/provider-config.sh"

# Auto-detect namespace from current oc project, fallback to openshell
NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"

# Strip ANSI escape codes from openshell output
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# Clean up any existing openclaw sandbox
EXISTING=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' || true)
if [ -n "$EXISTING" ]; then
  for sb in $EXISTING; do
    openshell sandbox delete "$sb" 2>/dev/null && echo "Deleted sandbox $sb" || true
  done
  echo "Waiting for cleanup..."
  sleep 10
fi

# Create the sandbox with a stable label for Service targeting
echo "Creating sandbox with provider: $PROVIDER_NAME..."
openshell sandbox create --label app=openclaw --from openclaw --provider "$PROVIDER_NAME" -- true

# Get the sandbox name
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
echo "Sandbox name: $SANDBOX_NAME"

# Update sandbox policy to allow Telegram and Anthropic API access
echo ""
echo "Updating sandbox policy for Telegram and ${PROVIDER_NAME}..."
openshell policy set "$SANDBOX_NAME" --policy "${SCRIPT_DIR}/openclaw-policy.yaml" --wait

# Label the pod and get its name
POD=$(oc get pod -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | grep -v '^openshell-' | head -1)
oc label pod "$POD" app=openclaw -n "$NAMESPACE" --overwrite 2>/dev/null || true

echo ""
echo "============================================"
echo "  Sandbox ready!"
echo "============================================"
echo ""
echo "Pod: $POD"
echo ""
echo "Next step — configure OpenClaw:"
echo ""
echo "  Option A (automated — copies config + starts gateway):"
echo "    ./4-configure-openclaw.sh"
echo ""
echo "  Option B (interactive — runs openclaw onboard):"
echo "    ./4-configure-openclaw.sh --interactive"
echo ""
