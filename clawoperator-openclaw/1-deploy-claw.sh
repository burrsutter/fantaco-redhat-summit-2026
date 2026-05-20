#!/usr/bin/env bash
# 1-deploy-claw.sh — Deploy Claw CRs (secrets + Claw instance) per namespace
#
# Creates API key secret, password secret, and Claw CR in each target namespace.
# Sources ../.env for credentials.
#
# Usage:
#   ./1-deploy-claw.sh 2 5          # deploy to agentic-user2 through agentic-user5
#   ./1-deploy-claw.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX        — namespace prefix (default: agentic-user)
#   LLM_PROVIDER            — litellm | anthropic | openai (default: litellm)
#   LLM_API_KEY             — API key (sourced from ../.env)
#   LLM_API_BASE_URL        — LiteLLM base URL (sourced from ../.env)
#   LLM_MODEL_NAME          — custom model name for litellm (sourced from ../.env)
#   STUDENT_OPENCLAW_PASSWORD — password for OpenClaw login (sourced from ../.env)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
LLM_PROVIDER="${LLM_PROVIDER:-litellm}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 2 5   → deploy to agentic-user2 through agentic-user5"
  echo "  $0 3     → just agentic-user3"
  exit 1
fi

START=$1
END=${2:-$START}

if [[ $START -gt $END ]]; then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi

# ── Source .env ──────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE"
  echo "Copy .env.example to .env and fill in values."
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ── Validate required env vars ──────────────────────────────────────
case "$LLM_PROVIDER" in
  litellm)
    : "${LLM_API_KEY:?LLM_API_KEY must be set in .env}"
    : "${LLM_API_BASE_URL:?LLM_API_BASE_URL must be set in .env}"
    SECRET_NAME="litellm-api-key"
    API_KEY_VALUE="$LLM_API_KEY"
    ;;
  anthropic)
    : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY must be set in .env}"
    SECRET_NAME="anthropic-api-key"
    API_KEY_VALUE="$ANTHROPIC_API_KEY"
    ;;
  openai)
    : "${OPENAI_API_KEY:?OPENAI_API_KEY must be set in .env}"
    SECRET_NAME="openai-api-key"
    API_KEY_VALUE="$OPENAI_API_KEY"
    ;;
  *)
    echo "Error: Unknown LLM_PROVIDER '$LLM_PROVIDER'. Use: litellm, anthropic, openai"
    exit 1
    ;;
esac

: "${STUDENT_OPENCLAW_PASSWORD:?STUDENT_OPENCLAW_PASSWORD must be set in .env}"

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "=== Deploy Claw Instances ==="
echo "Provider: $LLM_PROVIDER"
echo "Namespaces: ${NAMESPACE_PREFIX}${START} through ${NAMESPACE_PREFIX}${END}"
echo ""

# ── Build credentials YAML block based on provider ──────────────────
build_credentials_yaml() {
  case "$LLM_PROVIDER" in
    litellm)
      # Extract domain from URL (strip protocol and trailing path)
      local domain
      domain=$(echo "$LLM_API_BASE_URL" | sed 's|^https\?://||' | sed 's|/.*||')
      cat <<CRED
    - name: litellm
      type: bearer
      secretRef:
        - name: litellm-api-key
          key: api-key
      domain: ${domain}
      provider: openai
CRED
      ;;
    anthropic)
      cat <<CRED
    - name: anthropic
      type: apiKey
      secretRef:
        - name: anthropic-api-key
          key: api-key
      provider: anthropic
CRED
      ;;
    openai)
      cat <<CRED
    - name: openai
      type: apiKey
      secretRef:
        - name: openai-api-key
          key: api-key
      provider: openai
CRED
      ;;
  esac
}

CREDENTIALS_YAML=$(build_credentials_yaml)

# ── Deploy to each namespace ────────────────────────────────────────
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  echo "--- Deploying to $NS ---"

  # 1. Create API key secret
  echo "  Creating secret: $SECRET_NAME"
  oc create secret generic "$SECRET_NAME" \
    --from-literal=api-key="$API_KEY_VALUE" \
    -n "$NS" \
    --dry-run=client -o yaml | oc apply -f -

  # 2. Create password secret
  echo "  Creating secret: claw-password"
  oc create secret generic claw-password \
    --from-literal=password="$STUDENT_OPENCLAW_PASSWORD" \
    -n "$NS" \
    --dry-run=client -o yaml | oc apply -f -

  # 3. Apply Claw CR
  echo "  Applying Claw CR"
  oc apply -n "$NS" -f - <<EOF
apiVersion: claw.sandbox.redhat.com/v1alpha1
kind: Claw
metadata:
  name: instance
spec:
  auth:
    mode: password
    passwordSecretRef:
      name: claw-password
      key: password
  credentials:
${CREDENTIALS_YAML}
EOF

  echo ""
done

# ── Wait for pods ───────────────────────────────────────────────────
echo "--- Waiting for pods to be ready (up to 120s) ---"
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  echo "  Waiting for pods in $NS ..."

  SECONDS=0
  while [[ $SECONDS -lt 120 ]]; do
    READY=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance \
      --no-headers 2>/dev/null | grep -c "Running" || true)
    if [[ $READY -ge 3 ]]; then
      break
    fi
    sleep 5
  done

  if [[ $READY -ge 3 ]]; then
    echo "  ✓ $NS: all $READY pods running"
  else
    echo "  ⚠ $NS: only $READY/3 pods running after 120s"
    echo "    Check: oc get pods -n $NS -l claw.sandbox.redhat.com/instance=instance"
  fi
done
echo ""

# ── Patch model config (litellm custom model) ─────────────────────
if [[ "$LLM_PROVIDER" == "litellm" && -n "${LLM_MODEL_NAME:-}" ]]; then
  echo "--- Patching model config (${LLM_MODEL_NAME}) ---"
  MODEL_KEY="openai/${LLM_MODEL_NAME}"
  for i in $(seq "$START" "$END"); do
    NS="${NAMESPACE_PREFIX}${i}"
    echo "  Patching $NS ..."
    oc exec deployment/instance -n "$NS" -c gateway -- node -e "
      const fs = require('fs');
      const f = '/home/node/.openclaw/openclaw.json';
      const c = JSON.parse(fs.readFileSync(f));
      if (!c.agents) c.agents = {};
      if (!c.agents.defaults) c.agents.defaults = {};
      if (!c.agents.defaults.models) c.agents.defaults.models = {};
      if (!c.agents.defaults.model) c.agents.defaults.model = {};
      c.agents.defaults.models['${MODEL_KEY}'] = {alias: '${LLM_MODEL_NAME}'};
      c.agents.defaults.model.primary = '${MODEL_KEY}';
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    "
    echo "    Set primary model to ${MODEL_KEY}"
  done

  echo "  Restarting gateway to pick up config change ..."
  for i in $(seq "$START" "$END"); do
    NS="${NAMESPACE_PREFIX}${i}"
    oc rollout restart deployment/instance -n "$NS"
  done
  for i in $(seq "$START" "$END"); do
    NS="${NAMESPACE_PREFIX}${i}"
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  echo ""
fi

# ── Print URLs ──────────────────────────────────────────────────────
echo "=== Claw Instance URLs ==="
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || echo "(not yet available)")
  echo "  $NS: $URL"
done
echo ""
echo "=== Deployment complete ==="
