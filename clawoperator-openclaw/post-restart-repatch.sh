#!/usr/bin/env bash
# post-restart-repatch.sh — Re-patch openclaw.json after a gateway restart
#
# Every `oc rollout restart` causes the claw-operator to re-seed openclaw.json
# from its ConfigMap, wiping custom config (allowedOrigins, model, plugins,
# diagnostics). This script re-applies all config so it survives restarts.
#
# Usage:
#   ./post-restart-repatch.sh <namespace>    # single namespace
#   ./post-restart-repatch.sh 1 5            # agentic-user1 through agentic-user5
#   ./post-restart-repatch.sh 3              # just agentic-user3
#
# What it patches:
#   1. allowedOrigins — audience route host + broker domain
#   2. Model — google/{GEMINI_MODEL} or openai/{LLM_MODEL_NAME} from .env
#   3. diagnostics.otel — full OTEL config block (if diagnostics-otel plugin installed)
#   4. diagnostics-prometheus plugin — only if ServiceMonitor exists
#   5. diagnostics-otel plugin — plugins.allow + plugins.entries
#   6. langfuse-tracer plugin — only if Langfuse keys in .env + plugin files on disk
#
# Requires: .env sourced for LLM_PROVIDER, GEMINI_MODEL, LLM_MODEL_NAME, BROKER_DOMAIN
# Does NOT restart the gateway — caller is responsible for restart timing.

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

# ── Source .env ────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"

# ── Argument parsing ──────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <namespace>       # single namespace by name"
  echo "       $0 <start> [end]     # agentic-user<start> through agentic-user<end>"
  exit 1
elif [[ $# -eq 1 && ! "$1" =~ ^[0-9]+$ ]]; then
  # Single namespace name (e.g. "agentic-user3" or current NS)
  NAMESPACES+=("$1")
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
  echo "Usage: $0 <namespace>       # single namespace by name"
  echo "       $0 <start> [end]     # agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Determine model config ────────────────────────────────────────
MODEL_KEY=""
MODEL_ALIAS=""
MODEL_PROVIDER_PATCH=""

if [[ "$LLM_PROVIDER" == "gcp" && -n "${GEMINI_MODEL:-}" ]]; then
  MODEL_KEY="google/${GEMINI_MODEL}"
  MODEL_ALIAS="${GEMINI_MODEL}"
elif [[ "$LLM_PROVIDER" == "litellm" && -n "${LLM_MODEL_NAME:-}" ]]; then
  MODEL_KEY="openai/${LLM_MODEL_NAME}"
  MODEL_ALIAS="${LLM_MODEL_NAME}"
  # Derive token limits based on model name
  if [[ "$LLM_MODEL_NAME" == claude-* ]]; then
    MODEL_CONTEXT_WINDOW=200000; MODEL_CONTEXT_TOKENS=180000; MODEL_MAX_TOKENS=8192
  elif [[ "$LLM_MODEL_NAME" == "qwen3-14b" ]]; then
    MODEL_CONTEXT_WINDOW=40960; MODEL_CONTEXT_TOKENS=32768; MODEL_MAX_TOKENS=4096
  else
    MODEL_CONTEXT_WINDOW=128000; MODEL_CONTEXT_TOKENS=128000; MODEL_MAX_TOKENS=16384
  fi
  MODEL_PROVIDER_PATCH="
    c.models = c.models || {};
    c.models.providers = c.models.providers || {};
    c.models.providers.openai = c.models.providers.openai || {};
    var p = c.models.providers.openai;
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
  "
fi

# ── Detect trace backends ─────────────────────────────────────────
# diagnostics-otel always targets MLflow (if deployed).
# langfuse-tracer handles Langfuse traces via REST API (not OTEL).
OTEL_ENDPOINT=""
OTEL_HEADERS=""

# Detect MLflow (diagnostics-otel target)
MLFLOW_ROUTE=$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MLFLOW_ROUTE" ]]; then
  MLFLOW_INTERNAL_URL="http://mlflow-mlflow.mlflow.svc.cluster.local:5000"
  MLFLOW_URL="https://${MLFLOW_ROUTE}"
  EXPERIMENT_ID=$(curl -sk "${MLFLOW_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=openclaw-traces" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment']['experiment_id'])" 2>/dev/null || echo "1")
  OTEL_ENDPOINT="${MLFLOW_INTERNAL_URL}/v1/traces"
  OTEL_HEADERS="x-mlflow-experiment-id=${EXPERIMENT_ID}"
fi

# Detect Langfuse (langfuse-tracer plugin — does NOT use OTEL_ENDPOINT)
LANGFUSE_ROUTE=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)

# ── Per-namespace re-patch ────────────────────────────────────────
for NS in "${NAMESPACES[@]}"; do
  # Verify gateway pod exists
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo "  WARN: No gateway pod in $NS — skipping re-patch"
    continue
  fi

  # Read audience route host for allowedOrigins
  AUDIENCE_HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  PUB_HOST=""
  if [[ -n "$AUDIENCE_HOST" ]]; then
    PUB_HOST="${AUDIENCE_HOST%%.*}.${BROKER_DOMAIN}"
  fi

  # Check if ServiceMonitor exists (prometheus was enabled)
  HAS_PROMETHEUS="false"
  if oc get servicemonitor openclaw-gateway -n "$NS" &>/dev/null; then
    HAS_PROMETHEUS="true"
  fi

  echo "  $NS: re-patching config..."

  # Single piped node script that patches everything at once
  # Uses piped stdin to avoid `!` escaping issues with `oc exec -- node -e`
  cat <<REPATCH_EOF | oc exec -i deployment/instance -n "$NS" -c gateway -- node 2>/dev/null
var fs = require("fs");
var f = "/home/node/.openclaw/openclaw.json";
var c = JSON.parse(fs.readFileSync(f));

// 1. allowedOrigins
if ("${AUDIENCE_HOST}") {
  c.gateway = c.gateway || {};
  c.gateway.controlUi = c.gateway.controlUi || {};
  var origins = c.gateway.controlUi.allowedOrigins || [];
  ["https://${AUDIENCE_HOST}", "https://${PUB_HOST}"].forEach(function(o) {
    if (o && o !== "https://" && origins.indexOf(o) === -1) origins.push(o);
  });
  c.gateway.controlUi.allowedOrigins = origins;
}

// 2. Model
if ("${MODEL_KEY}") {
  c.agents = c.agents || {};
  c.agents.defaults = c.agents.defaults || {};
  c.agents.defaults.models = c.agents.defaults.models || {};
  c.agents.defaults.model = c.agents.defaults.model || {};
  c.agents.defaults.models["${MODEL_KEY}"] = {alias: "${MODEL_ALIAS}"};
  c.agents.defaults.model.primary = "${MODEL_KEY}";
  ${MODEL_PROVIDER_PATCH}
}

// 3. diagnostics.otel
c.diagnostics = c.diagnostics || {};
c.diagnostics.enabled = true;
if ("${OTEL_ENDPOINT}") {
  c.diagnostics.otel = {
    enabled: true,
    protocol: "http/protobuf",
    traces: true,
    metrics: false,
    logs: false,
    sampleRate: 1,
    captureContent: {
      inputMessages: true,
      outputMessages: true,
      toolInputs: true,
      toolOutputs: true,
      systemPrompt: false
    }
  };
  c.env = c.env || {};
  c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = "${OTEL_ENDPOINT}";
  c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = "${OTEL_HEADERS}";
}

// 4. diagnostics-prometheus plugin (only if ServiceMonitor exists)
c.plugins = c.plugins || {};
c.plugins.allow = c.plugins.allow || [];
c.plugins.entries = c.plugins.entries || {};
if ("${HAS_PROMETHEUS}" === "true") {
  if (c.plugins.allow.indexOf("diagnostics-prometheus") === -1) c.plugins.allow.push("diagnostics-prometheus");
  c.plugins.entries["diagnostics-prometheus"] = { enabled: true };
}

// 5. diagnostics-otel plugin (if OTEL backend detected)
if ("${OTEL_ENDPOINT}") {
  if (c.plugins.allow.indexOf("diagnostics-otel") === -1) c.plugins.allow.push("diagnostics-otel");
  c.plugins.entries["diagnostics-otel"] = {
    enabled: true,
    hooks: { allowConversationAccess: true }
  };
}

// 6. langfuse-tracer plugin (if Langfuse keys available and plugin files exist on disk)
if ("${LANGFUSE_PUBLIC_KEY:-}" && "${LANGFUSE_SECRET_KEY:-}") {
  try {
    fs.statSync("/home/node/.openclaw/extensions/langfuse-tracer/index.js");
    if (c.plugins.allow.indexOf("langfuse-tracer") === -1) c.plugins.allow.push("langfuse-tracer");
    c.plugins.entries["langfuse-tracer"] = {
      enabled: true,
      hooks: { allowConversationAccess: true }
    };
  } catch(e) { /* plugin files not present — skip */ }
}

fs.writeFileSync(f, JSON.stringify(c, null, 2));
console.log("ok");
REPATCH_EOF
  echo "    done"
done
