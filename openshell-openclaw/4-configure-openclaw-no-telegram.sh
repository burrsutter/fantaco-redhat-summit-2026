#!/usr/bin/env bash
# configure-openclaw-no-telegram.sh
#
# Configures OpenClaw inside an OpenShell sandbox pod (web UI only, no Telegram).
#
# Usage:
#   ./4-configure-openclaw-no-telegram.sh
#
# Optional:
#   LLM_PROVIDER env var (default: anthropic) — see provider-config.sh
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Source .env from the repo root (one level up) for STUDENT_PASSWORD, API keys, etc.
ENV_FILE="${SCRIPT_DIR}/../.env"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE"; set +a
fi
source "${SCRIPT_DIR}/provider-config.sh"
OPENSHELL="${SCRIPT_DIR}/openshell.sh"

NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"
CONFIG_FILE="${SCRIPT_DIR}/openclaw-no-telegram.json.template"

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

# --- Auto mode ---
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config template not found: $CONFIG_FILE"
  exit 1
fi

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$("$OPENSHELL" sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
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
  echo "  ./4-configure-openclaw-no-telegram.sh"
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

# Use STUDENT_PASSWORD from .env as the gateway password
STUDENT_PASSWORD="${STUDENT_PASSWORD:-}"
if [ -z "$STUDENT_PASSWORD" ]; then
  echo "ERROR: STUDENT_PASSWORD not set. Add it to .env or export it."
  exit 1
fi

# Pre-compute the Route hostname for allowedOrigins injection
# Create the Service and Route early so we know the hostname before injecting config
oc expose pod "$POD" --port=18789 --name=openclaw-ui -n "$NAMESPACE" 2>/dev/null || true
oc create route edge openclaw-ui --service=openclaw-ui --port=18789 -n "$NAMESPACE" 2>/dev/null || true
ROUTE_HOST=$(oc get route openclaw-ui -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)

echo ""
echo "Copying openclaw.json into pod (injecting provider config)..."
oc exec "$POD" -n "$NAMESPACE" -- mkdir -p "$SANDBOX_HOME"
sed -e "s|\"password\": \"REPLACE_ME\"|\"password\": \"${STUDENT_PASSWORD}\"|" \
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

# --- Add /etc/hosts entries for domains that need local DNS resolution ---
# OpenClaw's web_fetch tool resolves DNS locally (getaddrinfo) instead of
# delegating to the proxy, so we resolve IPs at deploy time.
HOSTS_TO_PIN="api.nasa.gov apod.nasa.gov wttr.in"
for host in $HOSTS_TO_PIN; do
  ip=$(dig +short "$host" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
  if [ -n "$ip" ]; then
    oc exec "$POD" -n "$NAMESPACE" -- sh -c \
      "grep -q '$host' /etc/hosts 2>/dev/null || echo '$ip $host' >> /etc/hosts" || true
  else
    echo "WARNING: Could not resolve $host — skipping /etc/hosts entry"
  fi
done

# --- Stop any existing gateway ---
# Use `openclaw gateway stop` via sandbox exec (runs in sandbox namespace where
# the gateway process lives). Fall back to kill via PID file if that fails.
echo ""
echo "Stopping existing gateway (if any)..."
"$OPENSHELL" sandbox exec -n "$SANDBOX_NAME" --no-tty -- \
  openclaw gateway stop 2>/dev/null || true

# Fallback: force-kill any remaining gateway process and clean up lock files
# inside the sandbox namespace (where the gateway runs)
"$OPENSHELL" sandbox exec -n "$SANDBOX_NAME" --no-tty -- sh -c '
  pkill -9 -f "openclaw gateway" 2>/dev/null || true
  pkill -9 -f "openclaw$" 2>/dev/null || true
  sleep 1
  rm -f /tmp/openclaw-*/gateway.*.lock /tmp/gateway.log
' || true

# Also kill the port forwarder (holds 0.0.0.0:18789 in pod namespace)
oc exec "$POD" -n "$NAMESPACE" -- sh -c '
  pkill -9 -f "python3.*18789" 2>/dev/null || true
  rm -f /tmp/gateway.log
' || true
sleep 2

echo ""
echo "Starting gateway inside sandbox network namespace..."
"$OPENSHELL" sandbox exec -n "$SANDBOX_NAME" --no-tty -- \
  sh -c 'export HTTP_PROXY=http://10.200.0.1:3128 HTTPS_PROXY=http://10.200.0.1:3128 OPENCLAW_PROXY_ACTIVE=1; nohup openclaw gateway --allow-unconfigured > /tmp/gateway.log 2>&1 &'

echo "Waiting for gateway to start..."
sleep 8

echo ""
echo "Gateway logs:"
oc exec "$POD" -n "$NAMESPACE" -- cat /tmp/gateway.log 2>/dev/null | tail -15 || true

PASSWORD="$STUDENT_PASSWORD"

# --- Start port bridge for Route ---
echo ""
echo "--- Exposing OpenClaw UI via Route ---"

# Kill any existing port bridge
oc exec "$POD" -n "$NAMESPACE" -- sh -c 'pkill -f "python3.*portfwd" 2>/dev/null' || true

# Start a Python TCP proxy inside the pod to bridge 0.0.0.0:18789 -> sandbox 10.200.0.2:18789
oc exec "$POD" -n "$NAMESPACE" -- nohup python3 -c "
import socket, threading
def relay(s,d):
    try:
        while True:
            data = s.recv(4096)
            if not data: break
            d.sendall(data)
    except: pass
    finally: s.close(); d.close()
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('0.0.0.0', 18789))
srv.listen(32)
while True:
    cli, _ = srv.accept()
    up = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    up.connect(('10.200.0.2', 18789))
    threading.Thread(target=relay, args=(cli, up), daemon=True).start()
    threading.Thread(target=relay, args=(up, cli), daemon=True).start()
" > /tmp/portfwd.log 2>&1 &
sleep 2

echo "Route: https://${ROUTE_HOST}/"

echo ""
echo "============================================"
echo "  OpenClaw gateway is running (web UI only)"
echo "============================================"
echo ""
echo "Student password: $PASSWORD"
echo ""
echo "Next step — open the UI:"
echo "  ./6-open-openclaw.sh"
echo ""
echo "Route URL: https://${ROUTE_HOST}/"
echo "Students enter the password above when prompted."
echo ""
