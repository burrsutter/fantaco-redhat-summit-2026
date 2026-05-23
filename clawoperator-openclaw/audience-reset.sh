#!/usr/bin/env bash
# audience-reset.sh — Reset OpenClaw instances with new unique URLs for the next audience
#
# Generates a unique random Route per user so that:
#   - Old audience URLs stop working immediately
#   - New URLs are non-guessable (no user1/user2 pattern)
#   - User state is wiped (chats, memory, skills, config)
#
# The operator-managed Route ("instance") stays intact for admin use.
# Audience Routes are independent — the operator doesn't touch them.
#
# Usage:
#   ./audience-reset.sh 1 5          # reset user1 through user5
#   ./audience-reset.sh 3            # just user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

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

# ── Source .env (needed for model re-patching and password display) ──
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"
STUDENT_OPENCLAW_PASSWORD="${STUDENT_OPENCLAW_PASSWORD:-}"

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 1 5   → reset agentic-user1 through agentic-user5"
  echo "  $0 3     → just agentic-user3"
  exit 1
fi

START=$1
END=${2:-$START}

if [[ $START -gt $END ]]; then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi

NAMESPACES=()
for i in $(seq "$START" "$END"); do
  NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
done

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Audience Reset${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "Logged in as: ${CYAN}$(oc whoami)${RESET}"
echo ""
echo -e "Namespaces:"
for NS in "${NAMESPACES[@]}"; do
  echo -e "  - ${CYAN}${NS}${RESET}"
done
echo ""

# ── Derive apps domain from existing Route ──────────────────────────
FIRST_NS="${NAMESPACES[0]}"
APPS_DOMAIN=$(oc get route instance -n "$FIRST_NS" \
  -o jsonpath='{.status.ingress[0].routerCanonicalHostname}' 2>/dev/null \
  | sed 's/^router-default\.//')

if [[ -z "$APPS_DOMAIN" ]]; then
  echo "Error: Could not derive apps domain from Route in $FIRST_NS."
  echo "Make sure the Claw instance is deployed and the Route exists."
  exit 1
fi

echo -e "Apps domain: ${CYAN}${APPS_DOMAIN}${RESET}"

# Generate a shared audience code (visible in all URLs for this run)
AUDIENCE_CODE=$(head -c 4 /dev/urandom | xxd -p | head -c 5)
echo -e "Audience:   ${CYAN}${AUDIENCE_CODE}${RESET}"
echo ""

# ── Per-namespace reset ─────────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0
declare -a AUDIENCE_URLS=()
declare -a AUDIENCE_HOSTS=()
declare -a AUDIENCE_LABELS=()

for idx in "${!NAMESPACES[@]}"; do
  NS="${NAMESPACES[$idx]}"
  USER_NUM=$((START + idx))

  echo -e "${BOLD}=== Resetting namespace: $NS ===${RESET}"

  # Generate unique 6-char random code for this user
  USER_CODE=$(head -c 6 /dev/urandom | xxd -p | head -c 6)
  AUDIENCE_HOST="claw-${AUDIENCE_CODE}-${USER_CODE}.${APPS_DOMAIN}"
  AUDIENCE_URL="https://${AUDIENCE_HOST}"

  echo -e "  New URL: ${GREEN}${AUDIENCE_URL}${RESET}"

  # 1. Delete existing audience Route (old URL dies immediately)
  if oc get route audience -n "$NS" &>/dev/null; then
    echo "  Deleting previous audience Route..."
    oc delete route audience -n "$NS" --wait=false 2>/dev/null || true
  fi

  # 2. Verify gateway pod is running
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo -e "  ${RED}WARN: No gateway pod found — skipping.${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # 3. Wipe user state
  echo "  Wiping user state..."
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const { execSync } = require('child_process');
    const fs = require('fs');
    const path = require('path');
    const HOME = '/home/node/.openclaw';

    const dirsToRemove = [
      HOME + '/agents/default/sessions',
      HOME + '/agents/main/agent/codex-home/tmp',
      HOME + '/cron/runs',
      HOME + '/.cache',
      HOME + '/.local',
    ];

    const filesToRemove = [
      HOME + '/agents/main/agent/codex-home/installation_id',
      HOME + '/agents/main/agent/codex-home/.personality_migration',
      HOME + '/cron/jobs.json',
      HOME + '/cron/jobs.json.bak',
      HOME + '/cron/jobs-state.json',
      HOME + '/memory/default.sqlite',
      HOME + '/memory/default.sqlite-wal',
      HOME + '/memory/default.sqlite-shm',
      HOME + '/tasks/runs.sqlite',
      HOME + '/tasks/runs.sqlite-wal',
      HOME + '/tasks/runs.sqlite-shm',
      HOME + '/workspace/.openclaw/workspace-state.json',
      HOME + '/workspace/USER.md',
      HOME + '/workspace/HEARTBEAT.md',
      HOME + '/identity/device.json',
      HOME + '/openclaw.json',
      HOME + '/openclaw.json.last-good',
      HOME + '/update-check.json',
      HOME + '/logs/config-health.json',
    ];

    let removed = 0;

    for (const d of dirsToRemove) {
      try { execSync('rm -rf ' + JSON.stringify(d), { stdio: 'pipe' }); removed++; } catch (e) {}
    }
    for (const f of filesToRemove) {
      try { fs.unlinkSync(f); removed++; } catch (e) {}
    }

    const codexHome = HOME + '/agents/main/agent/codex-home';
    try {
      const entries = fs.readdirSync(codexHome);
      for (const e of entries) {
        if (/^(state_|logs_).*\\.sqlite/.test(e)) {
          fs.unlinkSync(path.join(codexHome, e));
          removed++;
        }
      }
    } catch (e) {}

    const skillsDir = HOME + '/workspace/skills';
    try {
      const entries = fs.readdirSync(skillsDir);
      for (const e of entries) {
        if (e !== 'platform') {
          execSync('rm -rf ' + JSON.stringify(path.join(skillsDir, e)), { stdio: 'pipe' });
          removed++;
        }
      }
    } catch (e) {}

    try { execSync('rm -rf /tmp/openclaw', { stdio: 'pipe' }); removed++; } catch (e) {}

    console.log('Removed ' + removed + ' items');
  "

  # 4. Create new audience Route with unique hostname
  echo "  Creating audience Route..."
  oc apply -n "$NS" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: audience
  labels:
    app: claw
    audience-route: "true"
  annotations:
    haproxy.router.openshift.io/timeout: "3600s"
spec:
  host: ${AUDIENCE_HOST}
  to:
    kind: Service
    name: instance
    weight: 100
  port:
    targetPort: 18789
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

  # 5. Restart gateway
  echo "  Restarting gateway..."
  oc rollout restart deployment/instance -n "$NS"

  # 6. Wait for rollout
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    AUDIENCE_URLS+=("$AUDIENCE_URL")
    AUDIENCE_HOSTS+=("$AUDIENCE_HOST")
    AUDIENCE_LABELS+=("$USER_NUM")
  else
    echo -e "  ${RED}WARN: Rollout did not complete within 120s.${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
done

# ── Re-patch model config ───────────────────────────────────────────
MODEL_PATCHED=false

if [[ "$LLM_PROVIDER" == "gcp" && -n "${GEMINI_MODEL:-}" ]]; then
  echo -e "${BOLD}--- Re-patching model config (${GEMINI_MODEL}) ---${RESET}"
  MODEL_KEY="google/${GEMINI_MODEL}"
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
      c.agents.defaults.models['${MODEL_KEY}'] = {alias: '${GEMINI_MODEL}'};
      c.agents.defaults.model.primary = '${MODEL_KEY}';
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    " && echo "    Set primary model to ${MODEL_KEY}"
  done
  MODEL_PATCHED=true
fi

if [[ "$LLM_PROVIDER" == "litellm" && -n "${LLM_MODEL_NAME:-}" ]]; then
  if [[ "$LLM_MODEL_NAME" == claude-* ]]; then
    MODEL_CONTEXT_WINDOW=200000; MODEL_CONTEXT_TOKENS=180000; MODEL_MAX_TOKENS=8192
  elif [[ "$LLM_MODEL_NAME" == "qwen3-14b" ]]; then
    MODEL_CONTEXT_WINDOW=40960; MODEL_CONTEXT_TOKENS=32768; MODEL_MAX_TOKENS=4096
  else
    MODEL_CONTEXT_WINDOW=128000; MODEL_CONTEXT_TOKENS=128000; MODEL_MAX_TOKENS=16384
  fi

  echo -e "${BOLD}--- Re-patching model config (${LLM_MODEL_NAME}, maxTokens=${MODEL_MAX_TOKENS}) ---${RESET}"
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
      if (!c.models) c.models = {};
      if (!c.models.providers) c.models.providers = {};
      if (!c.models.providers.openai) c.models.providers.openai = {};
      const p = c.models.providers.openai;
      p.contextWindow = ${MODEL_CONTEXT_WINDOW};
      p.contextTokens = ${MODEL_CONTEXT_TOKENS};
      p.maxTokens = ${MODEL_MAX_TOKENS};
      p.models = [{
        id: '${LLM_MODEL_NAME}', name: '${LLM_MODEL_NAME}',
        api: 'openai-completions', reasoning: false, input: ['text'],
        contextWindow: ${MODEL_CONTEXT_WINDOW}, contextTokens: ${MODEL_CONTEXT_TOKENS},
        maxTokens: ${MODEL_MAX_TOKENS},
        compat: { maxTokensField: 'max_tokens', supportsStore: false,
          supportsPromptCacheKey: false, supportsReasoningEffort: false,
          supportsDeveloperRole: false }
      }];
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    " && echo "    Set primary model to ${MODEL_KEY} (maxTokens=${MODEL_MAX_TOKENS})"
  done
  MODEL_PATCHED=true
fi

# Restart again if model was patched
if [[ "$MODEL_PATCHED" == "true" ]]; then
  echo "  Restarting gateways for model config ..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout restart deployment/instance -n "$NS"
  done
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  echo ""
fi

# ── Patch allowedOrigins (must be LAST — after all restarts) ─────────
# Each restart re-seeds openclaw.json from the operator ConfigMap, which
# only knows about the operator Route. We patch after all restarts so
# the audience origin survives.
if [[ ${#AUDIENCE_HOSTS[@]} -gt 0 ]]; then
  echo -e "${BOLD}--- Patching allowedOrigins ---${RESET}"
  for idx in "${!NAMESPACES[@]}"; do
    NS="${NAMESPACES[$idx]}"
    if [[ $idx -ge ${#AUDIENCE_HOSTS[@]} ]]; then continue; fi
    HOST="${AUDIENCE_HOSTS[$idx]}"
    echo "  $NS: adding https://${HOST}"
    oc exec deployment/instance -n "$NS" -c gateway -- node -e '
      const fs = require("fs");
      const f = "/home/node/.openclaw/openclaw.json";
      const c = JSON.parse(fs.readFileSync(f));
      c.gateway = c.gateway || {};
      c.gateway.controlUi = c.gateway.controlUi || {};
      const origins = c.gateway.controlUi.allowedOrigins || [];
      const newOrigin = "https://'"${HOST}"'";
      if (origins.indexOf(newOrigin) === -1) {
        origins.push(newOrigin);
        c.gateway.controlUi.allowedOrigins = origins;
      }
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    '
  done
  # Final restart to pick up the allowedOrigins change
  echo "  Restarting gateways for allowedOrigins..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout restart deployment/instance -n "$NS"
  done
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  # Re-apply allowedOrigins after this final restart (restart re-seeds config)
  for idx in "${!NAMESPACES[@]}"; do
    NS="${NAMESPACES[$idx]}"
    if [[ $idx -ge ${#AUDIENCE_HOSTS[@]} ]]; then continue; fi
    HOST="${AUDIENCE_HOSTS[$idx]}"
    oc exec deployment/instance -n "$NS" -c gateway -- node -e '
      const fs = require("fs");
      const f = "/home/node/.openclaw/openclaw.json";
      const c = JSON.parse(fs.readFileSync(f));
      c.gateway = c.gateway || {};
      c.gateway.controlUi = c.gateway.controlUi || {};
      const origins = c.gateway.controlUi.allowedOrigins || [];
      const newOrigin = "https://'"${HOST}"'";
      if (origins.indexOf(newOrigin) === -1) {
        origins.push(newOrigin);
        c.gateway.controlUi.allowedOrigins = origins;
      }
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    '
  done
  echo ""
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Audience Reset Complete${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  Succeeded: ${GREEN}${SUCCESS_COUNT}${RESET}"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo -e "  Failed:    ${RED}${FAIL_COUNT}${RESET}"
fi
if [[ "$MODEL_PATCHED" == "true" ]]; then
  echo "  Model:     re-patched from .env"
fi
echo ""

if [[ ${#AUDIENCE_URLS[@]} -gt 0 ]]; then
  if [[ -n "$STUDENT_OPENCLAW_PASSWORD" ]]; then
    echo -e "  ${BOLD}Share these URLs (password: ${CYAN}${STUDENT_OPENCLAW_PASSWORD}${RESET}${BOLD}):${RESET}"
  else
    echo -e "  ${BOLD}Share these URLs:${RESET}"
  fi
  echo ""
  for idx in "${!AUDIENCE_URLS[@]}"; do
    echo -e "  ${BOLD}${AUDIENCE_LABELS[$idx]}:${RESET} ${GREEN}${AUDIENCE_URLS[$idx]}${RESET}"
  done
  echo ""
fi
echo -e "  ${DIM}Admin URLs (stable): oc get route instance -n <namespace>${RESET}"
echo ""
