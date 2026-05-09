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
#   LLM_PROVIDER env var (default: anthropic) — see provider-config.sh
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/provider-config.sh"

NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"
CONFIG_FILE="${SCRIPT_DIR}/openclaw.json.template"

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
echo "LLM Provider: $LLM_PROVIDER ($PROVIDER_NAME)"

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
  echo "  Port forward the UI:"
  echo "    openshell forward start 18789 \$SANDBOX_NAME --background"
  echo ""
  echo "  Open the UI: http://127.0.0.1:18789/"
  exit 0
fi

# --- Auto mode (default) ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config template not found: $CONFIG_FILE"
  echo "Run with --interactive to configure manually."
  exit 1
fi

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
if [ -z "$SANDBOX_NAME" ]; then
  echo "ERROR: No sandbox found. Run ./3-deploy-openclaw-sandbox.sh first."
  exit 1
fi
echo "Sandbox: $SANDBOX_NAME"

# Config is written to /sandbox/.openclaw/ so the sandbox user (not root)
# can read it. The sandbox network namespace enforces the security policy,
# which only works when OpenClaw runs as the sandbox user via
# openshell sandbox exec.
SANDBOX_HOME=/sandbox/.openclaw

# --- Update OpenClaw to latest version ---
# The sandbox image ships an older version; update before starting the gateway.
echo ""
echo "Updating OpenClaw to latest version (this may take ~90s on first run)..."
oc exec "$POD" -n "$NAMESPACE" -- openclaw update 2>&1 | tail -5
echo "Update complete."

# --- Inject API key ---
if [ -z "$PROVIDER_API_KEY" ]; then
  echo ""
  echo "WARNING: ${PROVIDER_API_KEY_VAR} not set. Skipping API key injection."
  echo "Set it and re-run, or inject manually:"
  echo "  export ${PROVIDER_API_KEY_VAR}=<key>"
  echo "  ./4-configure-openclaw.sh"
else
  echo ""
  echo "Injecting ${PROVIDER_NAME} API key..."

  if [ "$LLM_PROVIDER" = "vllm" ]; then
    # vLLM needs baseUrl for the custom endpoint
    AUTH_PROFILES_JSON="{
  \"profiles\": {
    \"${AUTH_PROFILE_NAME}\": {
      \"type\": \"api_key\",
      \"provider\": \"${AUTH_PROVIDER}\",
      \"key\": \"${PROVIDER_API_KEY}\",
      \"baseUrl\": \"${VLLM_BASE_URL}\"
    }
  }
}"
  else
    AUTH_PROFILES_JSON="{
  \"profiles\": {
    \"${AUTH_PROFILE_NAME}\": {
      \"type\": \"api_key\",
      \"provider\": \"${AUTH_PROVIDER}\",
      \"key\": \"${PROVIDER_API_KEY}\"
    }
  }
}"
  fi

  oc exec "$POD" -n "$NAMESPACE" -- sh -c "
    mkdir -p ${SANDBOX_HOME}/agents/main/agent
    chown -R sandbox:sandbox ${SANDBOX_HOME}/agents
    cat > ${SANDBOX_HOME}/agents/main/agent/auth-profiles.json << 'INNEREOF'
${AUTH_PROFILES_JSON}
INNEREOF
    chown sandbox:sandbox ${SANDBOX_HOME}/agents/main/agent/auth-profiles.json
  "
  echo "API key injected."
fi

# Generate a random gateway auth token
GATEWAY_TOKEN=$(openssl rand -hex 24)

echo ""
echo "Copying openclaw.json into pod (injecting tokens + provider config)..."
oc exec "$POD" -n "$NAMESPACE" -- mkdir -p "$SANDBOX_HOME"
sed -e "s|\"botToken\": \"REPLACE_ME\"|\"botToken\": \"${TELEGRAM_BOT_TOKEN}\"|" \
    -e "s|\"token\": \"REPLACE_ME\"|\"token\": \"${GATEWAY_TOKEN}\"|" \
    -e "s|__AUTH_PROFILE_NAME__|${AUTH_PROFILE_NAME}|g" \
    -e "s|__AUTH_PROVIDER__|${AUTH_PROVIDER}|g" \
    -e "s|__MODEL_PRIMARY__|${MODEL_PRIMARY}|g" \
    -e "s|__MODEL_ALIAS__|${MODEL_ALIAS}|g" \
    -e "s|__PLUGIN_NAME__|${PLUGIN_NAME}|g" \
    "$CONFIG_FILE" \
  | oc exec -i "$POD" -n "$NAMESPACE" -- sh -c "cat > ${SANDBOX_HOME}/openclaw.json"
oc exec "$POD" -n "$NAMESPACE" -- chown sandbox:sandbox "${SANDBOX_HOME}/openclaw.json"
echo "Config copied."

# --- Make /root/.openclaw accessible to sandbox user ---
# The OpenClaw image ships a default config at /root/.openclaw/ and the binary
# references /root/.openclaw/workspace for agent files. /root is drwx------ by
# default and Landlock restricts writes to /sandbox, /tmp, /dev/null only.
# Fix: make /root traversable, own .openclaw by sandbox, and symlink workspace
# to a Landlock-writable path.
oc exec "$POD" -n "$NAMESPACE" -- sh -c '
  chmod 755 /root
  chown -R sandbox:sandbox /root/.openclaw 2>/dev/null
  rm -rf /root/.openclaw/workspace
  mkdir -p /sandbox/.openclaw/workspace
  chown sandbox:sandbox /sandbox/.openclaw/workspace
  ln -s /sandbox/.openclaw/workspace /root/.openclaw/workspace
' || true

# --- Kill any existing gateway and clean up root-owned log ---
oc exec "$POD" -n "$NAMESPACE" -- sh -c 'pkill -f "openclaw gateway" 2>/dev/null; rm -f /tmp/gateway.log' || true
sleep 2

echo ""
echo "Starting gateway inside sandbox network namespace..."
openshell sandbox exec -n "$SANDBOX_NAME" --no-tty -- \
  sh -c 'nohup openclaw gateway --allow-unconfigured > /tmp/gateway.log 2>&1 &'

echo "Waiting for gateway to start..."
sleep 8

echo ""
echo "Gateway logs:"
oc exec "$POD" -n "$NAMESPACE" -- cat /tmp/gateway.log 2>/dev/null | tail -15 || true

TOKEN="$GATEWAY_TOKEN"

# --- Port-forward OpenClaw UI in background ---
echo ""
echo "--- Starting OpenClaw UI port-forward (background) ---"
openshell forward start 18789 "$SANDBOX_NAME" --background
echo "Forwarding localhost:18789 -> sandbox:18789"
echo ""

echo "============================================"
echo "  OpenClaw gateway is running!"
echo "============================================"
echo ""
echo "Auth token: $TOKEN"
echo ""
echo "Next step — open the UI:"
echo "  ./6-open-openclaw.sh"
echo ""
echo "Or open directly: http://127.0.0.1:18789/#token=${TOKEN}"
echo ""
