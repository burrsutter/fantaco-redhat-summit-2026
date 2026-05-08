#!/usr/bin/env bash
# configure-openclaw.sh
#
# Configures OpenClaw inside an OpenShell sandbox pod.
#
# Usage:
#   ./4-configure-openclaw.sh --bot-token <token>         # Auto mode with CLI token
#   TELEGRAM_BOT_TOKEN=<token> ./4-configure-openclaw.sh  # Auto mode with env var
#   ./4-configure-openclaw.sh --interactive                # Interactive: run openclaw onboard
#
# Required:
#   TELEGRAM_BOT_TOKEN — via --bot-token flag or env var
#
# Optional:
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"
CONFIG_FILE="${SCRIPT_DIR}/openclaw.json"

# --- Parse arguments ---
INTERACTIVE=false
for arg in "$@"; do
  case "$arg" in
    --interactive) INTERACTIVE=true ;;
    --bot-token)   shift_next=true ;;
    *)
      if [ "${shift_next:-false}" = true ]; then
        TELEGRAM_BOT_TOKEN="$arg"
        shift_next=false
      fi
      ;;
  esac
done

# --- Resolve Telegram bot token ---
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "ERROR: Telegram bot token not provided."
  echo "Set it via env var or CLI flag:"
  echo "  export TELEGRAM_BOT_TOKEN=<token>"
  echo "  ./4-configure-openclaw.sh"
  echo ""
  echo "  ./4-configure-openclaw.sh --bot-token <token>"
  exit 1
fi

# --- Resolve pod name ---
if [ -z "${POD:-}" ]; then
  POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
  if [ -z "$POD" ]; then
    echo "ERROR: No pod found with label app=openclaw in namespace $NAMESPACE"
    exit 1
  fi
fi
echo "Pod: $POD"
echo "Namespace: $NAMESPACE"

# --- Interactive mode ---
if [ "$INTERACTIVE" = true ]; then
  echo ""
  echo "Starting interactive onboarding..."
  oc exec -it "$POD" -n "$NAMESPACE" -- openclaw onboard

  echo ""
  echo "============================================"
  echo "  Onboarding complete!"
  echo "============================================"
  echo ""
  echo "Next steps:"
  echo ""
  echo "  Start the gateway:"
  echo "    oc exec $POD -n $NAMESPACE -- sh -c 'nohup openclaw gateway --allow-unconfigured > /tmp/gateway.log 2>&1 &'"
  echo ""
  echo "  Get the auth token:"
  echo "    oc exec $POD -n $NAMESPACE -- sh -c \"grep -o '\\\"token\\\": *\\\"[^\\\"]*\\\"' /root/.openclaw/openclaw.json | tail -1\""
  echo ""
  echo "  Port forward (in a separate terminal):"
  echo "    oc port-forward $POD 18789:18789 -n $NAMESPACE"
  echo ""
  echo "  Open the UI: http://127.0.0.1:18789/"
  exit 0
fi

# --- Auto mode (default) ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Run with --interactive to configure manually."
  exit 1
fi

# --- Update OpenClaw to latest version ---
# The sandbox image ships an older version; update before starting the gateway.
echo ""
echo "Updating OpenClaw to latest version (this may take ~90s on first run)..."
oc exec "$POD" -n "$NAMESPACE" -- openclaw update 2>&1 | tail -5
echo "Update complete."

# --- Inject OpenAI API key ---
if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo ""
  echo "WARNING: OPENAI_API_KEY not set. Skipping API key injection."
  echo "Set it and re-run, or inject manually:"
  echo "  export OPENAI_API_KEY=sk-xxx"
  echo "  ./configure-openclaw.sh"
else
  echo ""
  echo "Injecting OpenAI API key..."
  oc exec "$POD" -n "$NAMESPACE" -- sh -c "
    mkdir -p /root/.openclaw/agents/main/agent
    cat > /root/.openclaw/agents/main/agent/auth-profiles.json << INNEREOF
{
  \"profiles\": {
    \"openai:default\": {
      \"type\": \"api_key\",
      \"provider\": \"openai\",
      \"key\": \"$OPENAI_API_KEY\"
    }
  }
}
INNEREOF
  "
  echo "API key injected."
fi

# Generate a random gateway auth token
GATEWAY_TOKEN=$(openssl rand -hex 24)

echo ""
echo "Copying openclaw.json into pod (injecting tokens)..."
oc exec "$POD" -n "$NAMESPACE" -- mkdir -p /root/.openclaw
sed -e "s|\"botToken\": \"REPLACE_ME\"|\"botToken\": \"${TELEGRAM_BOT_TOKEN}\"|" \
    -e "s|\"token\": \"REPLACE_ME\"|\"token\": \"${GATEWAY_TOKEN}\"|" "$CONFIG_FILE" \
  | oc exec -i "$POD" -n "$NAMESPACE" -- sh -c 'cat > /root/.openclaw/openclaw.json'
echo "Config copied."

echo ""
echo "Starting gateway..."
oc exec "$POD" -n "$NAMESPACE" -- sh -c 'nohup openclaw gateway --allow-unconfigured > /tmp/gateway.log 2>&1 &'

echo "Waiting for gateway to start..."
sleep 5

echo ""
echo "Gateway logs:"
oc exec "$POD" -n "$NAMESPACE" -- tail -20 /tmp/gateway.log || true

TOKEN="$GATEWAY_TOKEN"

echo ""
echo "============================================"
echo "  OpenClaw gateway is running!"
echo "============================================"
echo ""
echo "Auth token: $TOKEN"
echo ""
echo "Port forward (in a separate terminal):"
echo "  oc port-forward $POD 18789:18789 -n $NAMESPACE"
echo ""
echo "Open the UI: http://127.0.0.1:18789/"
echo ""
