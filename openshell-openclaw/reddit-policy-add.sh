#!/usr/bin/env bash
# reddit-policy-add.sh
#
# Adds www.reddit.com to the sandbox policy, then applies it.
# Use this to demonstrate dynamically granting access to a new site.

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
"$OPENSHELL" policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

# --- Pin DNS inside the sandbox for hosts that need local resolution ---
# The gateway runs inside the sandbox network namespace, so DNS pins must
# go into the sandbox's /etc/hosts (not the pod's).
HOSTS_TO_PIN="www.reddit.com"
for host in $HOSTS_TO_PIN; do
  ip=$(dig +short "$host" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
  if [ -n "$ip" ]; then
    "$OPENSHELL" sandbox exec -n "$SANDBOX_NAME" --no-tty -- \
      sh -c "grep -q '$host' /etc/hosts 2>/dev/null || echo '$ip $host' >> /etc/hosts" || true
    echo "Pinned $host -> $ip in sandbox /etc/hosts"
  else
    echo "WARNING: Could not resolve $host — skipping /etc/hosts entry"
  fi
done

echo ""
echo "Reddit endpoint added and policy applied."
echo "Try: \"What are the top 5 posts on r/programming right now?\""
