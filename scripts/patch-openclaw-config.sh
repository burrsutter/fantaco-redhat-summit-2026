#!/usr/bin/env bash
# patch-openclaw-config.sh
#
# Patches the openclaw-config ConfigMap with cron, Telegram, and MCP server
# settings, then restarts the gateway pod.
#
# Required:
#   - oc logged in to the target cluster
#   - TELEGRAM_BOT_TOKEN env var set
#
# Optional:
#   - NAMESPACE env var (default: current oc project)
#   - CONFIGMAP env var (default: openclaw-config)

set -euo pipefail

NAMESPACE="${NAMESPACE:-$(oc project -q)}"
CONFIGMAP="${CONFIGMAP:-openclaw-config}"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Error: TELEGRAM_BOT_TOKEN is not set" >&2
  exit 1
fi

echo "Namespace:  $NAMESPACE"
echo "ConfigMap:  $CONFIGMAP"

# Fetch current config and patch it
PATCHED_JSON=$(oc get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath='{.data.openclaw\.json}' | python3 -c "
import sys, json

config = json.load(sys.stdin)

# Enable cron / scheduled tasks
config['cron'] = {'enabled': True}

# Enable Telegram with bot token from env
import os
config['channels'] = {
    'telegram': {
        'groupPolicy': 'disabled',
        'botToken': os.environ['TELEGRAM_BOT_TOKEN']
    }
}

# Configure MCP servers
config['mcp'] = {
    'servers': {
        'customer': {
            'url': 'https://mcp-customer-route-agentic-user1.apps.ocp.v5987.sandbox340.opentlc.com'
        },
        'sales-order': {
            'url': 'https://mcp-sales-order-route-agentic-user1.apps.ocp.v5987.sandbox340.opentlc.com'
        },
        'sales-policy-search': {
            'url': 'https://mcp-sales-policy-search-route-agentic-user1.apps.ocp.v5987.sandbox340.opentlc.com/mcp'
        }
    }
}

print(json.dumps(config))
")

# Escape the JSON for the patch payload
PATCH_PAYLOAD=$(python3 -c "
import sys, json
print(json.dumps({'data': {'openclaw.json': sys.stdin.read()}}))
" <<< "$PATCHED_JSON")

# Apply the patch
oc patch configmap "$CONFIGMAP" -n "$NAMESPACE" --type merge -p "$PATCH_PAYLOAD"
echo "ConfigMap patched."

# Restart the gateway pod
echo "Restarting openclaw pod..."
oc delete pod -l app=openclaw -n "$NAMESPACE"

# Wait for the new pod to be ready
echo "Waiting for pod to become ready..."
oc rollout status deployment/openclaw -n "$NAMESPACE" --timeout=120s 2>/dev/null \
  || oc wait pod -l app=openclaw -n "$NAMESPACE" --for=condition=Ready --timeout=120s

echo "Done. OpenClaw gateway restarted with updated config."
