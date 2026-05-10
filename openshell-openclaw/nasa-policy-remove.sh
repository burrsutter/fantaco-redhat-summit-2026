#!/usr/bin/env bash
# remove-nasa-policy.sh
#
# Removes api.nasa.gov and apod.nasa.gov from the sandbox policy, then applies it.
# Use this to demonstrate dynamically revoking access to an API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/openclaw-policy.yaml"
OPENSHELL="${SCRIPT_DIR}/openshell.sh"

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$("$OPENSHELL" sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
if [ -z "$SANDBOX_NAME" ]; then
  echo "ERROR: No sandbox found."
  exit 1
fi

# Check if present
if ! grep -q 'api.nasa.gov' "$POLICY_FILE"; then
  echo "NASA endpoints are not in the policy."
  exit 0
fi

echo "Removing api.nasa.gov and apod.nasa.gov from policy..."

# Remove the NASA endpoint lines
sed -i.bak '/- host: api\.nasa\.gov/,/port: 443/d; /- host: apod\.nasa\.gov/,/port: 443/d' "$POLICY_FILE"
rm -f "${POLICY_FILE}.bak"

echo "Applying updated policy to sandbox $SANDBOX_NAME..."
"$OPENSHELL" policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

echo ""
echo "NASA endpoints removed and policy applied."
echo "NASA requests will now be blocked."
