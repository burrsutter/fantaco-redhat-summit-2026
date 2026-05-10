#!/usr/bin/env bash
# hackernews-policy-remove.sh
#
# Removes Hacker News endpoints from the sandbox policy, then applies it.
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
if ! grep -q 'news.ycombinator.com' "$POLICY_FILE"; then
  echo "Hacker News endpoints are not in the policy."
  exit 0
fi

echo "Removing Hacker News endpoints from policy..."

# Remove the HN endpoint lines
sed -i.bak '/- host: news\.ycombinator\.com/,/port: 443/d; /- host: hacker-news\.firebaseio\.com/,/port: 443/d' "$POLICY_FILE"
rm -f "${POLICY_FILE}.bak"

echo "Applying updated policy to sandbox $SANDBOX_NAME..."
"$OPENSHELL" policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

echo ""
echo "Hacker News endpoints removed and policy applied."
echo "Hacker News requests will now be blocked."
