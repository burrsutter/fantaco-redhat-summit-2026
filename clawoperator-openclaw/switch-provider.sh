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
# Extract --site flag before positional args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="$2"; shift 2 ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Load site config (BROKER_DOMAIN, CLUSTERS_CSV, etc.)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 [--site NAME] <provider> [user# | start end]"
  echo ""
  echo "Providers:"
  echo "  gcp         — Switch to Google Gemini (${GEMINI_MODEL:-gemini-2.5-pro})"
  echo "  openrouter  — Switch to OpenRouter (${OPENROUTER_MODEL:-not configured})"
  echo ""
  echo "Examples:"
  echo "  $0 openrouter              # all namespaces (primary site)"
  echo "  $0 --site backup gcp       # all namespaces (backup site)"
  echo "  $0 gcp 1 5                 # user1-5"
  exit 1
fi

TARGET_PROVIDER="$1"
shift

# ── Namespace args (deferred to per-cluster loop) ─────────────
NS_MODE="auto"
NS_START=""
NS_END=""
if [[ $# -ge 1 ]]; then
  NS_MODE="range"
  NS_START=$1
  NS_END=${2:-$NS_START}
fi

# ── Build cluster list ────────────────────────────────────────
CLUSTER_ENTRIES=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}Error: Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}${RESET}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}Error: Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})${RESET}"
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_ENTRIES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
else
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  CLUSTER_ENTRIES+=("default ${KUBECONFIG:-$HOME/.kube/config}")
fi

MULTI_CLUSTER=false
[[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]] && MULTI_CLUSTER=true

# Helper: discover namespaces for a given kubeconfig
discover_namespaces() {
  local kc="$1"
  NAMESPACES=()
  if [[ "$NS_MODE" == "auto" ]]; then
    while IFS= read -r ns; do
      NAMESPACES+=("$ns")
    done < <(KUBECONFIG="$kc" oc get namespaces --no-headers 2>/dev/null \
      | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  else
    for i in $(seq "$NS_START" "$NS_END"); do
      NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
    done
  fi
}

# ── Determine model config ─────────────────────────────────────
case "$TARGET_PROVIDER" in
  gcp)
    if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
      echo -e "${RED}Error: GOOGLE_APPLICATION_CREDENTIALS not set in .env${RESET}"
      exit 1
    fi
    if [[ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
      echo -e "${RED}Error: SA key file not found at $GOOGLE_APPLICATION_CREDENTIALS${RESET}"
      exit 1
    fi
    if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
      echo -e "${RED}Error: GOOGLE_CLOUD_PROJECT not set in .env${RESET}"
      exit 1
    fi
    if [[ -z "${GOOGLE_CLOUD_LOCATION:-}" ]]; then
      echo -e "${RED}Error: GOOGLE_CLOUD_LOCATION not set in .env${RESET}"
      exit 1
    fi
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

# ── Update .env to reflect the new provider ──────────────────────
if [[ -f "$ENV_FILE" ]]; then
  if grep -q "^LLM_PROVIDER=" "$ENV_FILE"; then
    sed -i.bak "s/^LLM_PROVIDER=.*/LLM_PROVIDER=${TARGET_PROVIDER}/" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
    echo -e "  Updated .env: LLM_PROVIDER=${TARGET_PROVIDER}"
  fi
fi

echo -e "  Model key: ${DIM}${MODEL_KEY}${RESET}"
echo ""

# ── Process each cluster ──────────────────────────────────────────
TOTAL_PATCHED=0
TOTAL_FAILED=0

for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  discover_namespaces "$CLUSTER_KUBECONFIG"

  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}No ${NAMESPACE_PREFIX}* namespaces found on ${CLUSTER_ID} — skipping${RESET}"
    continue
  fi

  $MULTI_CLUSTER && echo -e "${BOLD}── Cluster: ${CLUSTER_ID} (${#NAMESPACES[@]} namespaces) ──${RESET}" && echo ""

  # ── Ensure provider credentials exist in Claw CR ────────────────
  CR_CHANGED=false

  if [[ "$TARGET_PROVIDER" == "gcp" ]]; then
    echo -e "${BOLD}--- Ensuring GCP credentials ---${RESET}"

    for NS in "${NAMESPACES[@]}"; do
      KUBECONFIG="$CLUSTER_KUBECONFIG" oc create secret generic gcp-service-account \
        --from-file=sa-key.json="${GOOGLE_APPLICATION_CREDENTIALS}" \
        -n "$NS" --dry-run=client -o yaml | KUBECONFIG="$CLUSTER_KUBECONFIG" oc apply -f - &>/dev/null

      HAS_GCP=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get claw instance -n "$NS" -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('yes' if any(c.get('name') == 'gcp-vertex' and c.get('type') == 'gcp' for c in d.get('spec',{}).get('credentials',[])) else 'no')
" 2>/dev/null || echo "no")

      if [[ "$HAS_GCP" == "no" ]]; then
        KUBECONFIG="$CLUSTER_KUBECONFIG" oc patch claw instance -n "$NS" --type=json -p "[
          {\"op\": \"add\", \"path\": \"/spec/credentials/-\", \"value\": {
            \"name\": \"gcp-vertex\",
            \"type\": \"gcp\",
            \"secretRef\": [{\"name\": \"gcp-service-account\", \"key\": \"sa-key.json\"}],
            \"domain\": \".googleapis.com\",
            \"provider\": \"google\",
            \"gcp\": {
              \"project\": \"${GOOGLE_CLOUD_PROJECT}\",
              \"location\": \"${GOOGLE_CLOUD_LOCATION}\"
            }
          }}
        ]" &>/dev/null
        echo -e "  ${GREEN}✓${RESET} ${NS}: GCP credential added to Claw CR"
        CR_CHANGED=true
      else
        echo -e "  ${GREEN}✓${RESET} ${NS}: GCP credential already exists"
      fi
    done
    echo ""
  fi

  if [[ "$TARGET_PROVIDER" == "openrouter" ]]; then
    echo -e "${BOLD}--- Ensuring OpenRouter credentials ---${RESET}"

    for NS in "${NAMESPACES[@]}"; do
      KUBECONFIG="$CLUSTER_KUBECONFIG" oc create secret generic openrouter-api-key \
        --from-literal=api-key="${OPENROUTER_API_KEY}" \
        -n "$NS" --dry-run=client -o yaml | KUBECONFIG="$CLUSTER_KUBECONFIG" oc apply -f - &>/dev/null

      HAS_OR=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get claw instance -n "$NS" -o json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('yes' if any(c.get('name') == 'openrouter' and c.get('type') == 'bearer' for c in d.get('spec',{}).get('credentials',[])) else 'no')
" 2>/dev/null || echo "no")

      if [[ "$HAS_OR" == "no" ]]; then
        KUBECONFIG="$CLUSTER_KUBECONFIG" oc patch claw instance -n "$NS" --type=json -p '[
          {"op": "add", "path": "/spec/credentials/-", "value": {
            "name": "openrouter",
            "type": "bearer",
            "secretRef": [{"name": "openrouter-api-key", "key": "api-key"}],
            "domain": "openrouter.ai",
            "provider": "openai"
          }}
        ]' &>/dev/null
        echo -e "  ${GREEN}✓${RESET} ${NS}: OpenRouter credential added to Claw CR"
        CR_CHANGED=true
      else
        echo -e "  ${GREEN}✓${RESET} ${NS}: OpenRouter credential already exists"
      fi
    done
    echo ""
  fi

  # If any CR was patched, wait for operator to reconcile and restart pods
  if [[ "$CR_CHANGED" == "true" ]]; then
    echo -e "  ${DIM}Waiting for operator to reconcile...${RESET}"
    for NS in "${NAMESPACES[@]}"; do
      KUBECONFIG="$CLUSTER_KUBECONFIG" oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
    done
    echo ""

    echo -e "${BOLD}--- Re-applying post-restart config ---${RESET}"
    for NS in "${NAMESPACES[@]}"; do
      echo -e "  ${NS}: re-patching config..."
      KUBECONFIG="$CLUSTER_KUBECONFIG" "${SCRIPT_DIR}/post-restart-repatch.sh" --site "${SITE_NAME}" "$NS" 2>/dev/null \
        && echo -e "  ${GREEN}✓${RESET} ${NS}: repatch applied" \
        || echo -e "  ${YELLOW}⚠${RESET} ${NS}: repatch failed"
    done
    echo ""
  fi

  # ── Patch openclaw.json in each pod ─────────────────────────────
  echo -e "${BOLD}--- Patching model config ---${RESET}"
  PATCHED=0
  FAILED=0

  for NS in "${NAMESPACES[@]}"; do
    if KUBECONFIG="$CLUSTER_KUBECONFIG" oc exec deployment/instance -n "$NS" -c gateway -- node -e "
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

  # ── Restart gateway process (kill 1 preserves PVC config) ──
  echo -e "${BOLD}--- Restarting gateway process ---${RESET}"
  for NS in "${NAMESPACES[@]}"; do
    KUBECONFIG="$CLUSTER_KUBECONFIG" oc exec deployment/instance -n "$NS" -c gateway -- kill 1 2>/dev/null
    echo -e "  ${GREEN}✓${RESET} ${NS}"
  done

  echo ""
  echo -e "  ${DIM}Waiting for gateways to restart...${RESET}"
  sleep 15
  for NS in "${NAMESPACES[@]}"; do
    KUBECONFIG="$CLUSTER_KUBECONFIG" oc exec deployment/instance -n "$NS" -c gateway -- node -e "console.log('ready')" 2>/dev/null | grep -q "ready" \
      && echo -e "  ${GREEN}✓${RESET} ${NS}: ready" \
      || echo -e "  ${YELLOW}⚠${RESET} ${NS}: still starting"
  done

  echo ""
  echo -e "${BOLD}${CLUSTER_ID}:${RESET} ${PATCHED} patched, ${FAILED} failed"
  echo ""

  TOTAL_PATCHED=$((TOTAL_PATCHED + PATCHED))
  TOTAL_FAILED=$((TOTAL_FAILED + FAILED))
done

if $MULTI_CLUSTER; then
  echo -e "${GREEN}${BOLD}Done.${RESET} ${TOTAL_PATCHED} patched, ${TOTAL_FAILED} failed across ${#CLUSTER_ENTRIES[@]} cluster(s)."
else
  echo -e "${GREEN}${BOLD}Done.${RESET} ${TOTAL_PATCHED} patched, ${TOTAL_FAILED} failed."
fi
