#!/usr/bin/env bash
# reddit-policy-remove.sh
#
# Removes www.reddit.com from the sandbox policy, then applies it.
# Use this to demonstrate dynamically revoking access to a site.

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
if ! grep -q 'www.reddit.com' "$POLICY_FILE"; then
  echo "Reddit is not in the policy."
  exit 0
fi

echo "Removing www.reddit.com from policy..."

sed -i.bak '/- host: www\.reddit\.com/,/port: 443/d' "$POLICY_FILE"
rm -f "${POLICY_FILE}.bak"

echo "Applying updated policy to sandbox $SANDBOX_NAME..."
"$OPENSHELL" policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

echo ""
echo "Reddit removed and policy applied."
echo "Reddit requests will now be blocked."
