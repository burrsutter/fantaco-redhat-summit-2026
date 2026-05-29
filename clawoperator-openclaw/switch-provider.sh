#!/usr/bin/env bash
# switch-provider.sh — Hot-swap the LLM provider in ~30 seconds
#
# Ensures the Claw CR has the right credential, patches openclaw.json
# inside running pods, and restarts the gateway process (kill 1 preserves
# PVC config, avoiding operator re-seed).
#
# Usage:
#   ./switch-provider.sh openrouter           # switch all namespaces to OpenRouter
#   ./switch-provider.sh openrouter 2         # just user2
#   ./switch-provider.sh openrouter 1 5       # user1 through user5
#   ./switch-provider.sh gcp                  # switch back to GCP Gemini
#   ./switch-provider.sh gcp 2               # just user2
#
# Environment variables (from .env):
#   GEMINI_MODEL        — Gemini model name (e.g. gemini-2.5-pro)
#   OPENROUTER_MODEL    — OpenRouter model ID (e.g. moonshotai/kimi-k2.6)
#   OPENROUTER_API_KEY  — OpenRouter API key
#   NAMESPACE_PREFIX    — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Source .env ──────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# ── Parse arguments ─────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <provider> [user# | start end]"
  echo ""
  echo "Providers:"
  echo "  gcp         — Switch to Google Gemini (${GEMINI_MODEL:-gemini-2.5-pro})"
  echo "  openrouter  — Switch to OpenRouter (${OPENROUTER_MODEL:-not configured})"
  echo ""
  echo "Examples:"
  echo "  $0 openrouter        # all namespaces"
  echo "  $0 openrouter 2      # just user2"
  echo "  $0 gcp 1 5           # user1-5 back to Gemini"
  exit 1
fi

TARGET_PROVIDER="$1"
shift

# ── Build namespace list ────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No ${NAMESPACE_PREFIX}* namespaces found.${RESET}"
    exit 1
  fi
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
fi

# ── Determine model config ─────────────────────────────────────
case "$TARGET_PROVIDER" in
  gcp)
    MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
    MODEL_KEY="google/${MODEL}"
    MODEL_ALIAS="${MODEL}"
    PROVIDER_PATCH=""
    echo -e "${BOLD}Switching to GCP Gemini: ${CYAN}${MODEL}${RESET}"
    ;;
  openrouter)
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
      echo -e "${RED}Error: OPENROUTER_API_KEY not set in .env${RESET}"
      exit 1
    fi
    if [[ -z "${OPENROUTER_MODEL:-}" ]]; then
      echo -e "${RED}Error: OPENROUTER_MODEL not set in .env${RESET}"
      exit 1
    fi
    MODEL="${OPENROUTER_MODEL}"
    MODEL_KEY="openai/${MODEL}"
    MODEL_ALIAS="${MODEL}"
    PROVIDER_PATCH="
      c.models = c.models || {};
      c.models.providers = c.models.providers || {};
      c.models.providers.openai = c.models.providers.openai || {};
      var p = c.models.providers.openai;
      p.baseUrl = 'https://openrouter.ai/api/v1';
      p.apiKey = 'proxy-managed-credential';  // placeholder — real key injected by proxy via K8s Secret
      p.contextWindow = 131072;
      p.contextTokens = 131072;
      p.maxTokens = 8192;
      p.models = [{
        id: '${MODEL}', name: '${MODEL}',
        api: 'openai-completions', reasoning: true, input: ['text'],
        contextWindow: 131072, contextTokens: 131072, maxTokens: 8192,
        compat: { maxTokensField: 'max_tokens', supportsStore: false,
          supportsPromptCacheKey: false, supportsReasoningEffort: false,
          supportsDeveloperRole: false }
      }];
    "
    echo -e "${BOLD}Switching to OpenRouter: ${CYAN}${MODEL}${RESET}"
    ;;
  *)
    echo -e "${RED}Error: Unknown provider '${TARGET_PROVIDER}'. Use: gcp, openrouter${RESET}"
    exit 1
    ;;
esac

echo -e "  Model key: ${DIM}${MODEL_KEY}${RESET}"
echo -e "  Namespaces: ${CYAN}${#NAMESPACES[@]}${RESET}"
echo ""

# ── Ensure OpenRouter credential exists in Claw CR ──────────────
if [[ "$TARGET_PROVIDER" == "openrouter" ]]; then
  echo -e "${BOLD}--- Ensuring OpenRouter credentials ---${RESET}"
  CR_CHANGED=false

  for NS in "${NAMESPACES[@]}"; do
    # Create the secret
    oc create secret generic openrouter-api-key \
      --from-literal=api-key="${OPENROUTER_API_KEY}" \
      -n "$NS" --dry-run=client -o yaml | oc apply -f - &>/dev/null

    # Check if bearer credential already exists in Claw CR
    HAS_OR=$(oc get claw instance -n "$NS" -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('yes' if any(c.get('name') == 'openrouter' and c.get('type') == 'bearer' for c in d.get('spec',{}).get('credentials',[])) else 'no')
" 2>/dev/null || echo "no")

    if [[ "$HAS_OR" == "no" ]]; then
      oc patch claw instance -n "$NS" --type=json -p '[
        {"op": "add", "path": "/spec/credentials/-", "value": {
          "name": "openrouter",
          "type": "bearer",
          "secretRef": [{"name": "openrouter-api-key", "key": "api-key"}],
          "domain": "openrouter.ai",
          "provider": "openai"
        }}
      ]' &>/dev/null
      echo -e "  ${GREEN}✓${RESET} ${NS}: credential added to Claw CR"
      CR_CHANGED=true
    else
      echo -e "  ${GREEN}✓${RESET} ${NS}: credential already exists"
    fi
  done
  echo ""

  # If any CR was patched, wait for operator to reconcile and restart pods
  if [[ "$CR_CHANGED" == "true" ]]; then
    echo -e "  ${DIM}Waiting for operator to reconcile...${RESET}"
    for NS in "${NAMESPACES[@]}"; do
      oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
    done
    echo ""

    # Re-apply post-restart config (allowedOrigins, plugins, traces, etc.)
    echo -e "${BOLD}--- Re-applying post-restart config ---${RESET}"
    for NS in "${NAMESPACES[@]}"; do
      "${SCRIPT_DIR}/post-restart-repatch.sh" "$NS" 2>/dev/null \
        && echo -e "  ${GREEN}✓${RESET} ${NS}: repatch applied" \
        || echo -e "  ${YELLOW}⚠${RESET} ${NS}: repatch failed"
    done
    echo ""
  fi
fi

# ── Patch openclaw.json in each pod ─────────────────────────────
echo -e "${BOLD}--- Patching model config ---${RESET}"
PATCHED=0
FAILED=0

for NS in "${NAMESPACES[@]}"; do
  if oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const f = '/home/node/.openclaw/openclaw.json';
    const c = JSON.parse(fs.readFileSync(f));
    c.agents = c.agents || {};
    c.agents.defaults = c.agents.defaults || {};
    c.agents.defaults.models = c.agents.defaults.models || {};
    c.agents.defaults.model = c.agents.defaults.model || {};
    c.agents.defaults.models['${MODEL_KEY}'] = {alias: '${MODEL_ALIAS}'};
    c.agents.defaults.model.primary = '${MODEL_KEY}';
    ${PROVIDER_PATCH}
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
    console.log('ok');
  " 2>/dev/null | grep -q "ok"; then
    echo -e "  ${GREEN}✓${RESET} ${NS}: ${MODEL_KEY}"
    PATCHED=$((PATCHED + 1))
  else
    echo -e "  ${RED}✗${RESET} ${NS}: patch failed"
    FAILED=$((FAILED + 1))
  fi
done

echo ""

# ── Restart gateway process (kill 1 preserves PVC config, avoids operator re-seed) ──
echo -e "${BOLD}--- Restarting gateway process ---${RESET}"
for NS in "${NAMESPACES[@]}"; do
  oc exec deployment/instance -n "$NS" -c gateway -- kill 1 2>/dev/null
  echo -e "  ${GREEN}✓${RESET} ${NS}"
done

echo ""
echo -e "  ${DIM}Waiting for gateways to restart...${RESET}"
sleep 15
for NS in "${NAMESPACES[@]}"; do
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "console.log('ready')" 2>/dev/null | grep -q "ready" \
    && echo -e "  ${GREEN}✓${RESET} ${NS}: ready" \
    || echo -e "  ${YELLOW}⚠${RESET} ${NS}: still starting"
done

echo ""
echo -e "${GREEN}${BOLD}Done.${RESET} ${PATCHED} patched, ${FAILED} failed."
