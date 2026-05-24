#!/usr/bin/env bash
# reset-openclaw.sh — Reset OpenClaw gateway to fresh state
#
# Wipes all user state (chat sessions, agent memory, cron jobs, custom skills,
# config) from the gateway PVC and restarts the deployment so it re-initializes
# cleanly from the operator ConfigMap.
#
# Usage:
#   ./reset-openclaw.sh              # reset current namespace (student mode)
#   ./reset-openclaw.sh 2 5          # reset agentic-user2 through agentic-user5
#   ./reset-openclaw.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)
#   BROKER_DOMAIN    — public broker domain (default: yougetaclaw.com)
#   LLM_PROVIDER     — litellm | anthropic | openai | gcp (default: from .env)
#   GEMINI_MODEL     — Gemini model name for GCP provider (from .env)
#   LLM_MODEL_NAME   — Custom model name for LiteLLM provider (from .env)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# ── Source .env (optional — needed for model re-patching) ─────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
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
  echo "Usage: $0                # reset current namespace"
  echo "       $0 <start> [end]  # reset agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  OpenClaw Gateway Reset"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo ""
echo "Namespaces to reset:"
for NS in "${NAMESPACES[@]}"; do
  echo "  - ${NS}"
done
echo ""
echo "This wipes all user state (chats, memory, cron, custom skills, config)"
echo "and restarts the gateway so it re-initializes from the operator ConfigMap."
echo ""

# ── Per-namespace reset ─────────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Resetting namespace: $NS ==="

  # Verify gateway pod is running
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo "  WARN: No gateway pod found in $NS — skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  Gateway pod: $POD"

  # Wipe user state via oc exec
  echo "  Wiping user state..."
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const { execSync } = require('child_process');
    const fs = require('fs');
    const path = require('path');
    const HOME = '/home/node/.openclaw';

    const dirsToRemove = [
      // Chat sessions
      HOME + '/agents/default/sessions',
      // Agent temp files
      HOME + '/agents/main/agent/codex-home/tmp',
      // Cron job runs
      HOME + '/cron/runs',
      // Caches
      HOME + '/.cache',
      HOME + '/.local',
    ];

    const filesToRemove = [
      // Agent state DBs (glob patterns handled below)
      // Agent identity
      HOME + '/agents/main/agent/codex-home/installation_id',
      HOME + '/agents/main/agent/codex-home/.personality_migration',
      // Cron config
      HOME + '/cron/jobs.json',
      HOME + '/cron/jobs.json.bak',
      HOME + '/cron/jobs-state.json',
      // Memory
      HOME + '/memory/default.sqlite',
      HOME + '/memory/default.sqlite-wal',
      HOME + '/memory/default.sqlite-shm',
      // Task history
      HOME + '/tasks/runs.sqlite',
      HOME + '/tasks/runs.sqlite-wal',
      HOME + '/tasks/runs.sqlite-shm',
      // Workspace state
      HOME + '/workspace/.openclaw/workspace-state.json',
      // Workspace docs
      HOME + '/workspace/USER.md',
      HOME + '/workspace/HEARTBEAT.md',
      HOME + '/workspace/IDENTITY.md',
      HOME + '/workspace/SOUL.md',
      // Device identity
      HOME + '/identity/device.json',
      // Config (will be re-seeded from operator ConfigMap on restart)
      HOME + '/openclaw.json',
      HOME + '/openclaw.json.last-good',
      // Update check
      HOME + '/update-check.json',
      // Config health
      HOME + '/logs/config-health.json',
    ];

    let removed = 0;

    // Remove directories
    for (const d of dirsToRemove) {
      try {
        execSync('rm -rf ' + JSON.stringify(d), { stdio: 'pipe' });
        removed++;
      } catch (e) { /* dir may not exist */ }
    }

    // Remove individual files
    for (const f of filesToRemove) {
      try {
        fs.unlinkSync(f);
        removed++;
      } catch (e) { /* file may not exist */ }
    }

    // Remove agent state/log SQLite files (glob: state_*.sqlite*, logs_*.sqlite*)
    const codexHome = HOME + '/agents/main/agent/codex-home';
    try {
      const entries = fs.readdirSync(codexHome);
      for (const e of entries) {
        if (/^(state_|logs_).*\\.sqlite/.test(e)) {
          fs.unlinkSync(path.join(codexHome, e));
          removed++;
        }
      }
    } catch (e) { /* dir may not exist */ }

    // Remove user-created skills (preserve platform/)
    const skillsDir = HOME + '/workspace/skills';
    try {
      const entries = fs.readdirSync(skillsDir);
      for (const e of entries) {
        if (e !== 'platform') {
          execSync('rm -rf ' + JSON.stringify(path.join(skillsDir, e)), { stdio: 'pipe' });
          removed++;
        }
      }
    } catch (e) { /* dir may not exist */ }

    // Remove temp logs
    try {
      execSync('rm -rf /tmp/openclaw', { stdio: 'pipe' });
      removed++;
    } catch (e) { /* may not exist */ }

    console.log('Removed ' + removed + ' items');
  "

  # Restart the deployment
  echo "  Restarting gateway deployment..."
  oc rollout restart deployment/instance -n "$NS"

  # Wait for rollout
  echo "  Waiting for rollout to complete..."
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    echo "  Gateway restarted successfully."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  WARN: Rollout did not complete within 120s."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
done

# ── Re-patch model config ───────────────────────────────────────────
# The reset wipes openclaw.json, and the operator re-seeds it from the
# ConfigMap with default models that may not exist on this project.
# Re-apply the model config from .env (same logic as 1-deploy-claw.sh).

MODEL_PATCHED=false

if [[ "$LLM_PROVIDER" == "gcp" && -n "${GEMINI_MODEL:-}" ]]; then
  echo "--- Re-patching model config (${GEMINI_MODEL}) ---"
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
  # Derive token limits based on model name
  if [[ "$LLM_MODEL_NAME" == claude-* ]]; then
    MODEL_CONTEXT_WINDOW=200000; MODEL_CONTEXT_TOKENS=180000; MODEL_MAX_TOKENS=8192
  elif [[ "$LLM_MODEL_NAME" == "qwen3-14b" ]]; then
    MODEL_CONTEXT_WINDOW=40960; MODEL_CONTEXT_TOKENS=32768; MODEL_MAX_TOKENS=4096
  else
    MODEL_CONTEXT_WINDOW=128000; MODEL_CONTEXT_TOKENS=128000; MODEL_MAX_TOKENS=16384
  fi

  echo "--- Re-patching model config (${LLM_MODEL_NAME}, maxTokens=${MODEL_MAX_TOKENS}) ---"
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

# Restart again if model was patched (so the gateway picks up the change)
if [[ "$MODEL_PATCHED" == "true" ]]; then
  echo "  Restarting gateway for model config ..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout restart deployment/instance -n "$NS"
  done
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  echo ""
fi

# ── Re-patch diagnostics + prometheus (after all restarts) ──────────
# The reset wipes openclaw.json (and the npm-installed plugin on the PVC).
# Re-install the plugin and re-enable diagnostics if a ServiceMonitor
# exists (meaning enable-prometheus.sh was run previously).
DIAG_PATCHED=false
for NS in "${NAMESPACES[@]}"; do
  # Only re-patch if ServiceMonitor exists
  if ! oc get servicemonitor openclaw-gateway -n "$NS" &>/dev/null; then
    continue
  fi
  if [[ "$DIAG_PATCHED" == "false" ]]; then
    echo "--- Re-patching diagnostics + prometheus ---"
    DIAG_PATCHED=true
  fi
  echo "  $NS: installing plugin + enabling diagnostics"
  oc exec deployment/instance -n "$NS" -c gateway -- \
    node /app/dist/index.js plugins install @openclaw/diagnostics-prometheus 2>&1 \
    | grep -E "^(Installed|Already|Error)" || true
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const f = '/home/node/.openclaw/openclaw.json';
    const c = JSON.parse(fs.readFileSync(f));
    c.diagnostics = { enabled: true };
    if (!c.plugins) c.plugins = {};
    if (!c.plugins.allow) c.plugins.allow = [];
    if (!c.plugins.allow.includes('diagnostics-prometheus')) {
      c.plugins.allow.push('diagnostics-prometheus');
    }
    if (!c.plugins.entries) c.plugins.entries = {};
    c.plugins.entries['diagnostics-prometheus'] = { enabled: true };
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
  "
done
if [[ "$DIAG_PATCHED" == "true" ]]; then
  echo ""
fi

# ── Patch allowedOrigins (must be LAST — after all restarts) ─────────
# Each restart re-seeds openclaw.json from the operator ConfigMap, which
# only knows about the operator Route. We patch after all restarts so
# the audience origin survives.
ORIGINS_PATCHED=false
for NS in "${NAMESPACES[@]}"; do
  AUDIENCE_HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
  if [[ -z "$AUDIENCE_HOST" ]]; then
    continue
  fi
  if [[ "$ORIGINS_PATCHED" == "false" ]]; then
    echo "--- Patching allowedOrigins ---"
    ORIGINS_PATCHED=true
  fi
  PUB_HOST="${AUDIENCE_HOST%%.*}.${BROKER_DOMAIN}"
  echo "  $NS: adding https://${AUDIENCE_HOST} + https://${PUB_HOST}"
  oc exec deployment/instance -n "$NS" -c gateway -- node -e '
    const fs = require("fs");
    const f = "/home/node/.openclaw/openclaw.json";
    const c = JSON.parse(fs.readFileSync(f));
    c.gateway = c.gateway || {};
    c.gateway.controlUi = c.gateway.controlUi || {};
    const origins = c.gateway.controlUi.allowedOrigins || [];
    for (const o of ["https://'"${AUDIENCE_HOST}"'", "https://'"${PUB_HOST}"'"]) {
      if (origins.indexOf(o) === -1) origins.push(o);
    }
    c.gateway.controlUi.allowedOrigins = origins;
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
  '
done
if [[ "$ORIGINS_PATCHED" == "true" ]]; then
  echo ""
fi

# ── Summary ─────────────────────────────────────────────────────────
echo "============================================"
echo "  Reset complete!"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
if [[ "$MODEL_PATCHED" == "true" ]]; then
  echo "  Model:     re-patched from .env"
fi
if [[ "$DIAG_PATCHED" == "true" ]]; then
  echo "  Metrics:   re-patched diagnostics-prometheus"
fi
if [[ "$ORIGINS_PATCHED" == "true" ]]; then
  echo "  Origins:   re-patched for ${BROKER_DOMAIN}"
fi
echo ""
echo "The gateway will re-initialize with a clean state."
echo "Connect to the UI to verify: empty chats, no custom skills, no cron jobs."
