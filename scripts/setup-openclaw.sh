#!/usr/bin/env bash
# setup-openclaw.sh
#
# Configures a running OpenClaw gateway on OpenShift by patching the
# openclaw-config ConfigMap with model, MCP, cron, and Telegram settings,
# then restarts the pod so the init container picks up the new config.
#
# Usage:
#   ./scripts/setup-openclaw.sh \
#     --model-name "qwen3-14b" \
#     --model-url "https://litellm-prod.apps.maas.redhatworkshops.io/v1" \
#     --model-api-key "sk-abc123" \
#     --cron \
#     --telegram-token "bot123:ABC..." \
#     --mcp customer=https://mcp-customer-route.apps.example.com/mcp \
#     --mcp finance=https://mcp-finance-route.apps.example.com/mcp \
#     --mcp sales-order=https://mcp-sales-order-route.apps.example.com/mcp
#
# Required:
#   --model-name    Model identifier (e.g. qwen3-14b)
#   --model-url     OpenAI-compatible base URL
#   --model-api-key API key for the model server
#
# Optional:
#   --cron              Enable cron/scheduled tasks
#   --telegram-token    Telegram bot token
#   --mcp NAME=URL      MCP server entry (repeatable)
#   --namespace         Override namespace (default: current oc project)

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODEL_NAME=""
MODEL_URL=""
MODEL_API_KEY=""
ENABLE_CRON=false
TELEGRAM_TOKEN=""
NAMESPACE=""
declare -a MCP_ENTRIES=()

usage() {
  cat >&2 <<EOF
Usage: $0 [OPTIONS]

Required:
  --model-name NAME       Model identifier (e.g. qwen3-14b)
  --model-url URL         OpenAI-compatible base URL
  --model-api-key KEY     API key for the model server

Optional:
  --cron                  Enable cron/scheduled tasks
  --telegram-token TOKEN  Telegram bot token
  --mcp NAME=URL          MCP server entry (repeatable)
  --namespace NS          Override namespace (default: current oc project)
  -h, --help              Show this help message
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-name)
      MODEL_NAME="$2"; shift 2 ;;
    --model-url)
      MODEL_URL="$2"; shift 2 ;;
    --model-api-key)
      MODEL_API_KEY="$2"; shift 2 ;;
    --cron)
      ENABLE_CRON=true; shift ;;
    --telegram-token)
      TELEGRAM_TOKEN="$2"; shift 2 ;;
    --mcp)
      MCP_ENTRIES+=("$2"); shift 2 ;;
    --namespace)
      NAMESPACE="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown option: $1" >&2; usage ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required flags
# ---------------------------------------------------------------------------
missing=()
[[ -z "$MODEL_NAME" ]]    && missing+=("--model-name")
[[ -z "$MODEL_URL" ]]     && missing+=("--model-url")
[[ -z "$MODEL_API_KEY" ]] && missing+=("--model-api-key")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: missing required flags: ${missing[*]}" >&2
  echo "" >&2
  usage
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
for cmd in oc python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

if ! oc whoami >/dev/null 2>&1; then
  echo "Error: not logged in to OpenShift (oc whoami failed)" >&2
  exit 1
fi

NAMESPACE="${NAMESPACE:-$(oc project -q)}"
CONFIGMAP="openclaw-config"

echo "Namespace:  $NAMESPACE"
echo "ConfigMap:  $CONFIGMAP"
echo "Model:      custom/$MODEL_NAME"
echo "Model URL:  $MODEL_URL"
echo "Cron:       $ENABLE_CRON"
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  echo "Telegram:   enabled"
fi
echo "MCP servers: ${#MCP_ENTRIES[@]}"
for entry in "${MCP_ENTRIES[@]}"; do
  echo "  - $entry"
done
echo ""

# ---------------------------------------------------------------------------
# Fetch current config and build patched version
# ---------------------------------------------------------------------------
CURRENT_JSON=$(oc get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath='{.data.openclaw\.json}')

if [[ -z "$CURRENT_JSON" ]]; then
  echo "Error: could not read openclaw.json from ConfigMap $CONFIGMAP" >&2
  exit 1
fi

# Build MCP JSON array for Python
MCP_JSON="["
first=true
for entry in "${MCP_ENTRIES[@]}"; do
  key="${entry%%=*}"
  url="${entry#*=}"
  if [[ "$key" == "$url" ]]; then
    echo "Error: invalid --mcp format '$entry' (expected NAME=URL)" >&2
    exit 1
  fi
  $first || MCP_JSON+=","
  first=false
  MCP_JSON+=$(python3 -c "import json; print(json.dumps({'key': '$key', 'url': '$url'}))")
done
MCP_JSON+="]"

PATCHED_JSON=$(python3 -c "
import json, sys

config = json.loads(sys.argv[1])
model_name = sys.argv[2]
model_url = sys.argv[3]
model_api_key = sys.argv[4]
enable_cron = sys.argv[5] == 'true'
telegram_token = sys.argv[6]
mcp_entries = json.loads(sys.argv[7])

# Preserve the gateway block (and any other top-level keys we don't touch)
gateway = config.get('gateway', {})

# Build new config, preserving gateway
new_config = {}
if gateway:
    new_config['gateway'] = gateway

# Model configuration
new_config['models'] = {
    'providers': {
        'custom': {
            'baseUrl': model_url,
            'apiKey': model_api_key,
            'api': 'openai-completions',
            'models': [{'id': model_name}]
        }
    }
}

# Agent defaults
new_config['agents'] = {
    'defaults': {
        'model': {'primary': f'custom/{model_name}'},
        'workspace': '~/.openclaw/workspace'
    },
    'list': [
        {'id': 'default', 'name': 'OpenClaw Assistant', 'default': True, 'workspace': '~/.openclaw/workspace'}
    ]
}

# Cron
new_config['cron'] = {'enabled': enable_cron}

# Telegram (only if token provided)
if telegram_token:
    new_config['channels'] = {
        'telegram': {
            'enabled': True,
            'dmPolicy': 'pairing',
            'botToken': telegram_token
        }
    }

# MCP servers
if mcp_entries:
    servers = {}
    for entry in mcp_entries:
        servers[entry['key']] = {'url': entry['url']}
    new_config['mcp'] = {'servers': servers}

# Preserve skills config if present
if 'skills' in config:
    new_config['skills'] = config['skills']

print(json.dumps(new_config, indent=2))
" "$CURRENT_JSON" "$MODEL_NAME" "$MODEL_URL" "$MODEL_API_KEY" "$ENABLE_CRON" "$TELEGRAM_TOKEN" "$MCP_JSON")

# ---------------------------------------------------------------------------
# Build exec-approvals.json (allow-all)
# ---------------------------------------------------------------------------
EXEC_APPROVALS='{"version":"1.0","defaultPolicy":"allow","rules":[]}'

# ---------------------------------------------------------------------------
# Patch the ConfigMap
# ---------------------------------------------------------------------------
echo "Patching ConfigMap $CONFIGMAP..."

PATCH_PAYLOAD=$(python3 -c "
import json, sys
openclaw_json = sys.argv[1]
exec_approvals = sys.argv[2]
payload = {
    'data': {
        'openclaw.json': openclaw_json,
        'exec-approvals.json': exec_approvals
    }
}
print(json.dumps(payload))
" "$PATCHED_JSON" "$EXEC_APPROVALS")

oc patch configmap "$CONFIGMAP" -n "$NAMESPACE" --type merge -p "$PATCH_PAYLOAD"
echo "ConfigMap patched."

# ---------------------------------------------------------------------------
# Restart the openclaw pod
# ---------------------------------------------------------------------------
echo "Restarting openclaw pod..."
oc rollout restart deployment/openclaw -n "$NAMESPACE"

echo "Waiting for pod to become ready..."
oc rollout status deployment/openclaw -n "$NAMESPACE" --timeout=120s

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "===== Setup Complete ====="
echo "  Model:     custom/$MODEL_NAME"
echo "  Model URL: $MODEL_URL"
echo "  Cron:      $ENABLE_CRON"
if [[ -n "$TELEGRAM_TOKEN" ]]; then
  echo "  Telegram:  enabled"
fi
if [[ ${#MCP_ENTRIES[@]} -gt 0 ]]; then
  echo "  MCP servers:"
  for entry in "${MCP_ENTRIES[@]}"; do
    echo "    - $entry"
  done
fi
echo ""
echo "Verify:"
echo "  oc get configmap $CONFIGMAP -n $NAMESPACE -o jsonpath='{.data.openclaw\\.json}' | python3 -m json.tool"
echo "  oc get pods -l app=openclaw -n $NAMESPACE"
