#!/usr/bin/env bash
# reddit-policy-add.sh
#
# Adds www.reddit.com to the sandbox policy, then applies it.
# Use this to demonstrate dynamically granting access to a new site.

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
if grep -q 'www.reddit.com' "$POLICY_FILE"; then
  echo "Reddit endpoints are already in the policy."
  exit 0
fi

echo "Adding www.reddit.com to policy..."

# Insert Reddit endpoint after the api.telegram.org block
sed -i.bak '/    - host: api.telegram.org/{
N;N;N;N
a\
    - host: www.reddit.com\
      port: 443
}' "$POLICY_FILE"
rm -f "${POLICY_FILE}.bak"

echo "Applying updated policy to sandbox $SANDBOX_NAME..."
openshell policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

echo ""
echo "Reddit endpoint added and policy applied."
echo "Try: \"What are the top 5 posts on r/programming right now?\""
