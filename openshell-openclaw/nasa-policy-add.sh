#!/usr/bin/env bash
# add-nasa-policy.sh
#
# Adds api.nasa.gov and apod.nasa.gov to the sandbox policy, then applies it.
# Use this to demonstrate dynamically granting access to a new API.

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
"$OPENSHELL" policy set "$SANDBOX_NAME" --policy "$POLICY_FILE" --wait

# --- Pin DNS inside the sandbox for hosts that need local resolution ---
# The gateway runs inside the sandbox network namespace, so DNS pins must
# go into the sandbox's /etc/hosts (not the pod's).
HOSTS_TO_PIN="api.nasa.gov apod.nasa.gov"
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
echo "NASA endpoints added and policy applied."
echo "Try: \"Show me NASA's Astronomy Picture of the Day\""
