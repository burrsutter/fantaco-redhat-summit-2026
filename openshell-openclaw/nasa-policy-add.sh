#!/usr/bin/env bash
# add-nasa-policy.sh
#
# Adds api.nasa.gov and apod.nasa.gov to the sandbox policy, then applies it.
# Use this to demonstrate dynamically granting access to a new API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/openclaw-policy.yaml"

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
if [ -z "$SANDBOX_NAME" ]; then
  echo "ERROR: No sandbox found."
  exit 1
fi

# Check if already added
if grep -q 'api.nasa.gov' "$POLICY_FILE"; then
  echo "NASA endpoints are already in the policy."
  exit 0
fi

echo "Adding api.nasa.gov and apod.nasa.gov to policy..."

# Insert NASA endpoints before the binaries line in the claude_code section
sed -i.bak '/    - host: api.telegram.org/{
N;N;N;N
a\
    - host: api.nasa.gov\
      port: 443\
    - host: apod.nasa.gov\
      port: 443
}' "$POLICY_FILE"
rm -f "${POLICY_FILE}.bak"

echo "Applying updated policy to sandbox $SANDBOX_NAME..."
openshell policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

echo ""
echo "NASA endpoints added and policy applied."
echo "Try: \"Show me NASA's Astronomy Picture of the Day\""
