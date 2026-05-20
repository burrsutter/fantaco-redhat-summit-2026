#!/usr/bin/env bash
# 1-deploy-claw.sh — Deploy Claw CRs (secrets + Claw instance) per namespace
#
# Creates API key secret, password secret, and Claw CR in each target namespace.
# Sources ../.env for credentials.
#
# Usage:
#   ./1-deploy-claw.sh              # deploy to current namespace (student mode)
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
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  # No args — use current namespace (student mode)
  CURRENT_NS=$(oc project -q 2>/dev/null) || { echo "Error: cannot detect current namespace. Run 'oc project <ns>' first."; exit 1; }
  NAMESPACES+=("$CURRENT_NS")
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo "Error: start ($START) must be <= end ($END)"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # deploy to current namespace"
  echo "       $0 <start> [end]  # deploy to agentic-user<start> through agentic-user<end>"
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
echo "Logged in as: $(oc whoami)"
echo "Provider: $LLM_PROVIDER"
echo "Namespaces: ${NAMESPACES[*]}"
echo ""

# ── Build credentials YAML block based on provider ──────────────────
build_credentials_yaml() {
  case "$LLM_PROVIDER" in
    litellm)
      # Extract domain from URL (strip protocol and trailing path)
      local domain
      domain=$(echo "$LLM_API_BASE_URL" | sed -E 's|^https?://||' | sed 's|/.*||')
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
for NS in "${NAMESPACES[@]}"; do
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
for NS in "${NAMESPACES[@]}"; do
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
  # Derive token limits based on model name
  if [[ "$LLM_MODEL_NAME" == claude-* ]]; then
    MODEL_CONTEXT_WINDOW=200000
    MODEL_CONTEXT_TOKENS=180000
    MODEL_MAX_TOKENS=8192
  elif [[ "$LLM_MODEL_NAME" == "qwen3-14b" ]]; then
    MODEL_CONTEXT_WINDOW=40960
    MODEL_CONTEXT_TOKENS=32768
    MODEL_MAX_TOKENS=4096
  else
    MODEL_CONTEXT_WINDOW=128000
    MODEL_CONTEXT_TOKENS=128000
    MODEL_MAX_TOKENS=16384
  fi

  echo "--- Patching model config (${LLM_MODEL_NAME}, maxTokens=${MODEL_MAX_TOKENS}) ---"
  MODEL_KEY="openai/${LLM_MODEL_NAME}"
  for NS in "${NAMESPACES[@]}"; do
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
      // Set provider-level token limits
      if (!c.models) c.models = {};
      if (!c.models.providers) c.models.providers = {};
      if (!c.models.providers.openai) c.models.providers.openai = {};
      const p = c.models.providers.openai;
      p.contextWindow = ${MODEL_CONTEXT_WINDOW};
      p.contextTokens = ${MODEL_CONTEXT_TOKENS};
      p.maxTokens = ${MODEL_MAX_TOKENS};
      p.models = [{
        id: '${LLM_MODEL_NAME}',
        name: '${LLM_MODEL_NAME}',
        api: 'openai-completions',
        reasoning: false,
        input: ['text'],
        contextWindow: ${MODEL_CONTEXT_WINDOW},
        contextTokens: ${MODEL_CONTEXT_TOKENS},
        maxTokens: ${MODEL_MAX_TOKENS},
        compat: {
          maxTokensField: 'max_tokens',
          supportsStore: false,
          supportsPromptCacheKey: false,
          supportsReasoningEffort: false,
          supportsDeveloperRole: false
        }
      }];
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    "
    echo "    Set primary model to ${MODEL_KEY} (maxTokens=${MODEL_MAX_TOKENS})"
  done

  echo "  Restarting gateway to pick up config change ..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout restart deployment/instance -n "$NS"
  done
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  echo ""
fi

# ── Print URLs ──────────────────────────────────────────────────────
echo "=== Claw Instance URLs ==="
for NS in "${NAMESPACES[@]}"; do
  URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || echo "(not yet available)")
  echo "  $NS: $URL"
done
echo ""
echo "=== Deployment complete ==="
