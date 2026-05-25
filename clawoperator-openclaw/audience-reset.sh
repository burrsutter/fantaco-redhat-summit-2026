#!/usr/bin/env bash
# audience-reset.sh — One-stop demo environment reset for OpenClaw
#
# Resets all OpenClaw instances with new unique URLs, deploys FantaCo backends,
# injects MCP endpoints and enterprise skills, and updates the Route-LB broker.
#
# This script consolidates:
#   - audience-reset (URL rotation, state wipe)
#   - 4-deploy-fantaco-backends.sh (Helm deploy)
#   - 5-inject-mcp-endpoints.sh (MCP CR patch + NetworkPolicy)
#   - 6-inject-enterprise-skills.sh (skill injection)
#
# Usage:
#   ./audience-reset.sh              # reset all agentic-user namespaces on cluster
#   ./audience-reset.sh 1 5          # reset user1 through user5
#   ./audience-reset.sh 3            # just user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
HELM_DIR="${SCRIPT_DIR}/../helm"
SKILLS_DIR="${SCRIPT_DIR}/../claw_skills"
SKILLS_DEST="/home/node/.openclaw/workspace/skills"

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

# ── Route-LB broker config ─────────────────────────────────────────
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
BROKER_S3_BUCKET="${BROKER_S3_BUCKET:-yougetaclaw-route-lb-config}"
BROKER_S3_KEY="${BROKER_S3_KEY:-route-lb/routes.csv}"
BROKER_AWS_REGION="${BROKER_AWS_REGION:-us-east-1}"

# ── Helm template lists (from 4-deploy-fantaco-backends.sh) ────────
CUSTOMER_APP_TEMPLATES=(
  templates/postgres-customer-deployment.yaml
  templates/postgres-customer-service.yaml
  templates/customer-configmap.yaml
  templates/customer-secret.yaml
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
)

CUSTOMER_MCP_TEMPLATES=(
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
)

SALESORDER_APP_TEMPLATES=(
  templates/postgres-salesorder-deployment.yaml
  templates/postgres-salesorder-service.yaml
  templates/salesorder-configmap.yaml
  templates/salesorder-secret.yaml
  templates/salesorder-deployment.yaml
  templates/salesorder-service.yaml
  templates/salesorder-route.yaml
)

SALESORDER_MCP_TEMPLATES=(
  templates/salesorder-deployment.yaml
  templates/salesorder-service.yaml
  templates/salesorder-route.yaml
)

PRODUCT_APP_TEMPLATES=(
  templates/postgres-product-deployment.yaml
  templates/postgres-product-service.yaml
  templates/product-configmap.yaml
  templates/product-secret.yaml
  templates/product-deployment.yaml
  templates/product-service.yaml
  templates/product-route.yaml
)

PRODUCT_MCP_TEMPLATES=(
  templates/product-deployment.yaml
  templates/product-service.yaml
  templates/product-route.yaml
)

# ── Skills to inject ──────────────────────────────────────────────
SKILLS=(
  quote-builder
)

# ── Helper: render and apply Helm templates ───────────────────────
apply_templates() {
  local chart_name=$1
  local chart_dir=$2
  local ns=$3
  shift 3
  local templates=("$@")

  local show_args=()
  for t in "${templates[@]}"; do
    show_args+=(-s "$t")
  done

  helm template "$chart_name" "$chart_dir" -n "$ns" "${show_args[@]}" \
    | oc apply -n "$ns" -f - 2>&1 | sed 's/^/    /'
}

# ── Helper: wait for pods matching a grep pattern ─────────────────
wait_for_pods() {
  local ns=$1
  local pattern=$2
  local expected=$3
  local label=$4

  SECONDS=0
  local ready=0
  while [[ $SECONDS -lt 120 ]]; do
    ready=$(oc get pods -n "$ns" --no-headers 2>/dev/null \
      | grep -E "$pattern" \
      | grep -c "Running" || true)
    if [[ $ready -ge $expected ]]; then
      break
    fi
    sleep 5
  done

  if [[ $ready -ge $expected ]]; then
    echo -e "  ${GREEN}✓${RESET} $label: $ready/$expected pods running"
  else
    echo -e "  ${YELLOW}⚠${RESET} $label: only $ready/$expected pods running after 120s"
  fi
  return 0
}

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  # No args — discover all agentic-user namespaces on cluster
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo "Error: No ${NAMESPACE_PREFIX}* namespaces found on cluster."
    exit 1
  fi
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
  echo "Usage: $0                # reset all agentic-user namespaces"
  echo "       $0 <start> [end]  # reset agentic-user<start> through agentic-user<end>"
  exit 1
fi

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

# ══════════════════════════════════════════════════════════════════════
# Phase 1: Per-namespace reset (wipe, deploy backends, new route, restart)
# ══════════════════════════════════════════════════════════════════════
SUCCESS_COUNT=0
FAIL_COUNT=0
declare -a AUDIENCE_URLS=()
declare -a AUDIENCE_HOSTS=()
declare -a AUDIENCE_LABELS=()

for idx in "${!NAMESPACES[@]}"; do
  NS="${NAMESPACES[$idx]}"
  USER_NUM="${NS#${NAMESPACE_PREFIX}}"

  echo -e "${BOLD}=== Resetting namespace: $NS ===${RESET}"

  # Generate unique 6-char random code for this user
  USER_CODE=$(head -c 6 /dev/urandom | xxd -p | head -c 6)
  AUDIENCE_HOST="claw-${AUDIENCE_CODE}-${USER_CODE}.${APPS_DOMAIN}"
  AUDIENCE_URL="https://${AUDIENCE_HOST}"

  echo -e "  New URL: ${GREEN}${AUDIENCE_URL}${RESET}"

  # 1a. Delete existing audience Route (old URL dies immediately)
  if oc get route audience -n "$NS" &>/dev/null; then
    echo "  Deleting previous audience Route..."
    oc delete route audience -n "$NS" --wait=false 2>/dev/null || true
  fi

  # 1b. Verify gateway pod is running
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo -e "  ${RED}WARN: No gateway pod found — skipping.${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # 1c. Wipe user state
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
      HOME + '/workspace/IDENTITY.md',
      HOME + '/workspace/SOUL.md',
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

  # 1d. Deploy FantaCo backends (Helm)
  echo "  Deploying FantaCo backends..."
  echo "    Customer app..."
  apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${CUSTOMER_APP_TEMPLATES[@]}" || true
  echo "    Customer MCP..."
  apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${CUSTOMER_MCP_TEMPLATES[@]}" || true
  echo "    Sales-order app..."
  apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${SALESORDER_APP_TEMPLATES[@]}" || true
  echo "    Sales-order MCP..."
  apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${SALESORDER_MCP_TEMPLATES[@]}" || true
  echo "    Product app..."
  apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${PRODUCT_APP_TEMPLATES[@]}" || true
  echo "    Product MCP..."
  apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${PRODUCT_MCP_TEMPLATES[@]}" || true

  # 1e. Create new audience Route with unique hostname
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

  # 1f. Restart gateway
  echo "  Restarting gateway..."
  oc rollout restart deployment/instance -n "$NS"

  # 1g. Wait for rollout
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    AUDIENCE_URLS+=("$AUDIENCE_URL")
    AUDIENCE_HOSTS+=("$AUDIENCE_HOST")
    AUDIENCE_LABELS+=("$USER_NUM")
  else
    echo -e "  ${RED}WARN: Rollout did not complete within 120s.${RESET}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # 1h. Wait for FantaCo backend pods
  echo "  Waiting for FantaCo backend pods..."
  wait_for_pods "$NS" \
    "(fantaco-customer-main|postgresql-customer|mcp-customer|fantaco-product-main|postgresql-product|mcp-product|fantaco-sales-order-main|postgresql-salesorder|mcp-sales-order)" \
    9 "FantaCo backends"

  echo ""
done

# ══════════════════════════════════════════════════════════════════════
# Phase 2: Inject MCP endpoints (patch Claw CR + NetworkPolicy)
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Injecting MCP endpoints ---${RESET}"
for NS in "${NAMESPACES[@]}"; do
  echo "  $NS: patching Claw CR (customer + product + sales-order)..."
  oc patch claw instance -n "$NS" --type=merge -p \
    '{"spec":{"mcpServers":{"customer":{"url":"http://mcp-customer-service:9001/mcp","transport":"streamable-http"},"product":{"url":"http://mcp-product-service:9003/mcp","transport":"streamable-http"},"sales-order":{"url":"http://mcp-sales-order-service:9004/mcp","transport":"streamable-http"}}}}' \
    2>&1 | sed 's/^/    /' || true

  echo "  $NS: applying NetworkPolicy (proxy -> MCP services)..."
  cat <<'NETPOL' | oc apply -n "$NS" -f - 2>&1 | sed 's/^/    /'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-proxy-to-mcp
  labels:
    app: fantaco-mcp
spec:
  podSelector:
    matchLabels:
      app: claw-proxy
      claw.sandbox.redhat.com/instance: instance
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: mcp-customer
      ports:
        - port: 9001
          protocol: TCP
    - to:
        - podSelector:
            matchLabels:
              app: mcp-product
      ports:
        - port: 9003
          protocol: TCP
    - to:
        - podSelector:
            matchLabels:
              app: mcp-sales-order
      ports:
        - port: 9004
          protocol: TCP
NETPOL
done
echo ""

# ══════════════════════════════════════════════════════════════════════
# Phase 3: Re-patch model config
# ══════════════════════════════════════════════════════════════════════
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

# ══════════════════════════════════════════════════════════════════════
# Phase 4: Re-patch diagnostics (Prometheus + MLflow/OTEL)
# ══════════════════════════════════════════════════════════════════════

# ── Reset Prometheus data (wipe old audience metrics) ──────────────
# Prometheus User Workload Monitoring uses emptyDir — deleting pods wipes all data.
if oc get sts prometheus-user-workload -n openshift-user-workload-monitoring &>/dev/null; then
  echo -e "${BOLD}--- Resetting Prometheus data ---${RESET}"
  echo "  Deleting Prometheus pods (emptyDir — data wiped on recreate)..."
  oc delete pods -n openshift-user-workload-monitoring -l app.kubernetes.io/name=prometheus --wait=false 2>/dev/null || true
  echo "  Waiting for Prometheus pods to come back..."
  oc rollout status sts/prometheus-user-workload -n openshift-user-workload-monitoring --timeout=120s 2>/dev/null || true
  echo ""
fi

# ── Reset Grafana dashboard ────────────────────────────────────────
if oc get grafanadashboard openclaw-admin-overview -n grafana &>/dev/null; then
  echo -e "${BOLD}--- Resetting Grafana dashboard ---${RESET}"
  echo "  Deleting and re-applying openclaw-admin-overview..."
  DASHBOARD_JSON=$(oc get grafanadashboard openclaw-admin-overview -n grafana -o json 2>/dev/null)
  oc delete grafanadashboard openclaw-admin-overview -n grafana --wait=true 2>/dev/null || true
  # Re-create from the saved spec (strip runtime metadata)
  echo "$DASHBOARD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
# Keep only spec + essential metadata
out = {
    'apiVersion': d['apiVersion'],
    'kind': d['kind'],
    'metadata': {
        'name': d['metadata']['name'],
        'namespace': d['metadata']['namespace']
    },
    'spec': d['spec']
}
json.dump(out, sys.stdout)
" | oc apply -f - 2>&1 | sed 's/^/    /'
  echo ""
fi

# ── Prometheus ─────────────────────────────────────────────────────
DIAG_PATCHED=false
for NS in "${NAMESPACES[@]}"; do
  if ! oc get servicemonitor openclaw-gateway -n "$NS" &>/dev/null; then
    continue
  fi
  if [[ "$DIAG_PATCHED" == "false" ]]; then
    echo -e "${BOLD}--- Re-patching diagnostics (Prometheus) ---${RESET}"
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

# ── MLflow / OTEL ──────────────────────────────────────────────────
# The diagnostics-otel plugin requires three things to export traces:
#   1. The plugin npm package must be installed (@openclaw/diagnostics-otel)
#   2. The diagnostics.otel config block must be set (enabled, protocol, traces, sampleRate)
#   3. OTEL env vars must be set as real container env vars (not just in openclaw.json env section)
# The gateway pod egresses through instance-proxy; the proxy allowlist does NOT include MLflow.
# Instead we use the internal cluster service URL (http://mlflow-mlflow.mlflow.svc.cluster.local:5000)
# which bypasses the proxy (matched by NO_PROXY=.svc.cluster.local) and a NetworkPolicy for egress.
OTEL_PATCHED=false
MLFLOW_URL=""
MLFLOW_INTERNAL_URL=""
EXPERIMENT_ID=""
MLFLOW_ROUTE=$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MLFLOW_ROUTE" ]]; then
  MLFLOW_URL="https://${MLFLOW_ROUTE}"
  MLFLOW_INTERNAL_URL="http://mlflow-mlflow.mlflow.svc.cluster.local:5000"
  # Look up experiment ID (default to 1 if lookup fails)
  EXPERIMENT_ID=$(curl -sk "${MLFLOW_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=openclaw-traces" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment']['experiment_id'])" 2>/dev/null || echo "1")

  echo -e "${BOLD}--- Re-patching diagnostics (MLflow/OTEL → ${MLFLOW_INTERNAL_URL}) ---${RESET}"
  echo "  Experiment ID: ${EXPERIMENT_ID}"
  echo "  External URL:  ${MLFLOW_URL} (for browser access)"
  echo "  Internal URL:  ${MLFLOW_INTERNAL_URL} (for gateway OTEL export)"

  # Create NetworkPolicy allowing instance pods to reach MLflow directly (bypassing proxy)
  for NS in "${NAMESPACES[@]}"; do
    oc apply -n "$NS" -f - <<'NETPOL_EOF' 2>/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-instance-to-mlflow
spec:
  podSelector:
    matchLabels:
      app: claw
      claw.sandbox.redhat.com/instance: instance
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: mlflow
    ports:
    - port: 5000
      protocol: TCP
NETPOL_EOF
  done
  echo "  NetworkPolicy: applied to all namespaces"

  for NS in "${NAMESPACES[@]}"; do
    echo "  $NS: installing + enabling diagnostics-otel plugin..."
    # Install the plugin npm package (required — config alone is not enough)
    oc exec deployment/instance -n "$NS" -c gateway -- \
      node /app/dist/index.js plugins install @openclaw/diagnostics-otel 2>&1 \
      | grep -E "^(Installed|Already|Error)" || true
    # Patch openclaw.json with full diagnostics.otel config block
    oc exec deployment/instance -n "$NS" -c gateway -- node -e "
      const fs = require('fs');
      const f = '/home/node/.openclaw/openclaw.json';
      const c = JSON.parse(fs.readFileSync(f));
      c.diagnostics = c.diagnostics || {};
      c.diagnostics.enabled = true;
      c.diagnostics.otel = {
        enabled: true,
        protocol: 'http/protobuf',
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
      if (!c.plugins) c.plugins = {};
      if (!c.plugins.allow) c.plugins.allow = [];
      if (!c.plugins.allow.includes('diagnostics-otel')) {
        c.plugins.allow.push('diagnostics-otel');
      }
      if (!c.plugins.entries) c.plugins.entries = {};
      c.plugins.entries['diagnostics-otel'] = {
        enabled: true,
        hooks: { allowConversationAccess: true }
      };
      if (!c.env) c.env = {};
      c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = '${MLFLOW_INTERNAL_URL}/v1/traces';
      c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = 'x-mlflow-experiment-id=${EXPERIMENT_ID}';
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    " 2>/dev/null && echo "    Patched" || echo "    WARN: could not patch"
    # Set OTEL env vars as real container env vars (OTEL SDK reads process.env, not openclaw.json)
    # OTEL_SERVICE_NAME tags traces per user so they're easy to find in MLflow UI
    # OTEL_SEMCONV_STABILITY_OPT_IN enables gen_ai semantic conventions for MLflow Summary tab
    oc set env deployment/instance -n "$NS" -c gateway \
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="${MLFLOW_INTERNAL_URL}/v1/traces" \
      OTEL_EXPORTER_OTLP_TRACES_HEADERS="x-mlflow-experiment-id=${EXPERIMENT_ID}" \
      OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
      OTEL_EXPORTER_OTLP_TRACES_PROTOCOL="http/protobuf" \
      OTEL_SERVICE_NAME="openclaw-${NS}" \
      OTEL_RESOURCE_ATTRIBUTES="openclaw.namespace=${NS}" \
      OTEL_SEMCONV_STABILITY_OPT_IN="gen_ai_latest_experimental" \
      2>/dev/null || true
  done
  OTEL_PATCHED=true
  # Wait for rollouts triggered by oc set env
  echo "  Waiting for OTEL rollouts..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  echo ""
fi

# TODO: Loki integration — not yet implemented

# ══════════════════════════════════════════════════════════════════════
# Phase 5: Patch allowedOrigins + final restart + re-patch everything
# ══════════════════════════════════════════════════════════════════════
# Each restart re-seeds openclaw.json from the operator ConfigMap, which
# only knows about the operator Route. We patch before the final restart,
# then re-patch everything after it so all config survives.
if [[ ${#AUDIENCE_HOSTS[@]} -gt 0 ]]; then
  echo -e "${BOLD}--- Patching allowedOrigins ---${RESET}"
  for idx in "${!NAMESPACES[@]}"; do
    NS="${NAMESPACES[$idx]}"
    if [[ $idx -ge ${#AUDIENCE_HOSTS[@]} ]]; then continue; fi
    HOST="${AUDIENCE_HOSTS[$idx]}"
    PUB_HOST="${HOST%%.*}.${BROKER_DOMAIN}"
    echo "  $NS: adding https://${HOST} + https://${PUB_HOST}"
    oc exec deployment/instance -n "$NS" -c gateway -- node -e '
      const fs = require("fs");
      const f = "/home/node/.openclaw/openclaw.json";
      const c = JSON.parse(fs.readFileSync(f));
      c.gateway = c.gateway || {};
      c.gateway.controlUi = c.gateway.controlUi || {};
      const origins = c.gateway.controlUi.allowedOrigins || [];
      for (const o of ["https://'"${HOST}"'", "https://'"${PUB_HOST}"'"]) {
        if (origins.indexOf(o) === -1) origins.push(o);
      }
      c.gateway.controlUi.allowedOrigins = origins;
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    '
  done
  # Final restart to pick up all config changes
  echo "  Restarting gateways (final restart)..."
  for NS in "${NAMESPACES[@]}"; do
    oc rollout restart deployment/instance -n "$NS"
  done
  for NS in "${NAMESPACES[@]}"; do
    oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null || true
  done
  # Re-apply allowedOrigins after final restart (restart re-seeds config)
  for idx in "${!NAMESPACES[@]}"; do
    NS="${NAMESPACES[$idx]}"
    if [[ $idx -ge ${#AUDIENCE_HOSTS[@]} ]]; then continue; fi
    HOST="${AUDIENCE_HOSTS[$idx]}"
    PUB_HOST="${HOST%%.*}.${BROKER_DOMAIN}"
    oc exec deployment/instance -n "$NS" -c gateway -- node -e '
      const fs = require("fs");
      const f = "/home/node/.openclaw/openclaw.json";
      const c = JSON.parse(fs.readFileSync(f));
      c.gateway = c.gateway || {};
      c.gateway.controlUi = c.gateway.controlUi || {};
      const origins = c.gateway.controlUi.allowedOrigins || [];
      for (const o of ["https://'"${HOST}"'", "https://'"${PUB_HOST}"'"]) {
        if (origins.indexOf(o) === -1) origins.push(o);
      }
      c.gateway.controlUi.allowedOrigins = origins;
      fs.writeFileSync(f, JSON.stringify(c, null, 2));
    '
  done
  # Re-apply Prometheus diagnostics after final restart
  if [[ "$DIAG_PATCHED" == "true" ]]; then
    echo "  Re-patching Prometheus after final restart..."
    for NS in "${NAMESPACES[@]}"; do
      if ! oc get servicemonitor openclaw-gateway -n "$NS" &>/dev/null; then
        continue
      fi
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
  fi
  # Re-apply MLflow/OTEL diagnostics after final restart
  if [[ "$OTEL_PATCHED" == "true" ]]; then
    echo "  Re-patching MLflow/OTEL after final restart..."
    for NS in "${NAMESPACES[@]}"; do
      # Re-install plugin (restart may clear npm state)
      oc exec deployment/instance -n "$NS" -c gateway -- \
        node /app/dist/index.js plugins install @openclaw/diagnostics-otel 2>&1 \
        | grep -E "^(Installed|Already|Error)" || true
      oc exec deployment/instance -n "$NS" -c gateway -- node -e "
        const fs = require('fs');
        const f = '/home/node/.openclaw/openclaw.json';
        const c = JSON.parse(fs.readFileSync(f));
        c.diagnostics = c.diagnostics || {};
        c.diagnostics.enabled = true;
        c.diagnostics.otel = {
          enabled: true,
          protocol: 'http/protobuf',
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
        if (!c.plugins) c.plugins = {};
        if (!c.plugins.allow) c.plugins.allow = [];
        if (!c.plugins.allow.includes('diagnostics-otel')) {
          c.plugins.allow.push('diagnostics-otel');
        }
        if (!c.plugins.entries) c.plugins.entries = {};
        c.plugins.entries['diagnostics-otel'] = {
          enabled: true,
          hooks: { allowConversationAccess: true }
        };
        if (!c.env) c.env = {};
        c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = '${MLFLOW_INTERNAL_URL}/v1/traces';
        c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = 'x-mlflow-experiment-id=${EXPERIMENT_ID}';
        fs.writeFileSync(f, JSON.stringify(c, null, 2));
      " 2>/dev/null || true
    done
  fi
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# Phase 6: Inject enterprise persona, skills, and agent instructions
#           (must be LAST — after final restart, since restarts wipe PVC state)
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Injecting enterprise persona + skills ---${RESET}"
SKILLS_INJECTED=0
for NS in "${NAMESPACES[@]}"; do
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
    | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)

  if [[ -z "$POD" ]]; then
    echo -e "  ${YELLOW}$NS: no running gateway pod — skipping${RESET}"
    continue
  fi

  # 6a. Pre-fill IDENTITY.md (prevents bootstrap questionnaire)
  oc exec "$POD" -n "$NS" -c gateway -- bash -c 'cat > /home/node/.openclaw/workspace/IDENTITY.md << "IDEOF"
# IDENTITY.md - Who Am I?

- **Name:**
- **Creature:** An octopus juggling eight priorities at once
- **Vibe:** Calm under pressure
- **Emoji:** 🐙
- **Avatar:**
IDEOF' 2>/dev/null && echo -e "  ${GREEN}✓${RESET} $NS: IDENTITY.md pre-filled" \
    || echo -e "  ${YELLOW}⚠${RESET} $NS: IDENTITY.md write failed"

  # 6b. Append enterprise assistant instructions to AGENTS.md
  oc exec "$POD" -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const f = '/home/node/.openclaw/workspace/AGENTS.md';
    let content = fs.readFileSync(f, 'utf8');
    const additions = \`

## Enterprise assistant

You are a resourceful enterprise assistant for FantaCo, a company that sells
tacos and related products. Help users explore customer data, sales orders,
and business workflows using the MCP tools available to you.

When a user mentions customers, orders, accounts, or quotes, proactively use
the customer and sales-order MCP tools to look up relevant data. Don't wait
to be asked — if the context suggests a lookup would be helpful, do it.

Key MCP tools at your disposal:
- **customer** tools: search customers, get customer details, look up projects
- **product** tools: search products by name/category/theme, list pod themes, get product details
- **sales-order** tools: search orders, get order details, look up line items

When presenting data, use clear tables or bullet points. Summarize key facts
first, then offer to dig deeper.

## Output formatting

Never wrap your responses in XML tags like <final>, <answer>, or similar.
Just respond directly.

## Identity

When a user gives you a name, accept it without asking follow-up questions
about your creature type, vibe, emoji, or avatar. Those are already set.
Do not run the bootstrap identity questionnaire.
\`;
    content += additions;
    fs.writeFileSync(f, content);
  " 2>/dev/null && echo -e "  ${GREEN}✓${RESET} $NS: AGENTS.md patched" \
    || echo -e "  ${YELLOW}⚠${RESET} $NS: AGENTS.md patch failed"

  # 6c. Inject enterprise skills
  for SKILL in "${SKILLS[@]}"; do
    if [[ ! -f "$SKILLS_DIR/$SKILL/SKILL.md" ]]; then
      echo -e "  ${YELLOW}$NS: skill not found locally: $SKILL${RESET}"
      continue
    fi
    oc exec "$POD" -n "$NS" -c gateway -- mkdir -p "${SKILLS_DEST}/${SKILL}" 2>/dev/null
    if oc cp "$SKILLS_DIR/$SKILL/SKILL.md" "$POD:${SKILLS_DEST}/${SKILL}/SKILL.md" -n "$NS" -c gateway 2>/dev/null; then
      echo -e "  ${GREEN}✓${RESET} $NS: $SKILL injected"
      SKILLS_INJECTED=$((SKILLS_INJECTED + 1))
    else
      echo -e "  ${YELLOW}⚠${RESET} $NS: $SKILL injection failed"
    fi
  done
done
echo "  Injected $SKILLS_INJECTED skill(s) across ${#NAMESPACES[@]} namespace(s)"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Phase 7: Update Route-LB broker (S3 + SSM)
# ══════════════════════════════════════════════════════════════════════
if [[ ${#AUDIENCE_HOSTS[@]} -gt 0 ]]; then
  echo -e "${BOLD}--- Updating Route-LB broker ---${RESET}"

  # Generate routes.csv
  ROUTES_CSV=$(mktemp)
  echo "# public_host,openshift_route_host,enabled,namespace" > "$ROUTES_CSV"
  for idx in "${!AUDIENCE_HOSTS[@]}"; do
    HOST="${AUDIENCE_HOSTS[$idx]}"
    PREFIX="${HOST%%.*}"
    NS_LABEL="${NAMESPACE_PREFIX}${AUDIENCE_LABELS[$idx]}"
    echo "${PREFIX}.${BROKER_DOMAIN},${HOST},true,${NS_LABEL}" >> "$ROUTES_CSV"
  done

  echo "  Generated routes.csv (${#AUDIENCE_HOSTS[@]} routes):"
  while IFS= read -r line; do echo "    $line"; done < "$ROUTES_CSV"

  # Upload to S3
  echo ""
  echo "  Uploading to s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}..."
  if aws s3 cp "$ROUTES_CSV" "s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}" --region "$BROKER_AWS_REGION" 2>/dev/null; then
    echo -e "  ${GREEN}S3 upload OK${RESET}"
  else
    echo -e "  ${RED}S3 upload failed — upload routes.csv manually${RESET}"
  fi
  rm -f "$ROUTES_CSV"

  # Find EC2 instance and trigger reset via SSM
  EC2_INSTANCE_ID=$(aws ec2 describe-instances \
    --region "$BROKER_AWS_REGION" \
    --filters Name=tag:Name,Values=route-lb-haproxy Name=instance-state-name,Values=running \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)

  if [[ -n "$EC2_INSTANCE_ID" && "$EC2_INSTANCE_ID" != "None" ]]; then
    echo "  Triggering broker reset on ${EC2_INSTANCE_ID} via SSM..."
    COMMAND_ID=$(aws ssm send-command \
      --region "$BROKER_AWS_REGION" \
      --instance-ids "$EC2_INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --parameters '{"commands":["source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && /usr/local/bin/route-lb-sync && curl -s -X POST http://localhost:3000/admin/reset"]}' \
      --query 'Command.CommandId' --output text 2>/dev/null || true)

    if [[ -n "$COMMAND_ID" && "$COMMAND_ID" != "None" ]]; then
      echo "  SSM command: $COMMAND_ID"
      echo "  Waiting for broker reset..."
      sleep 8
      SSM_STATUS=$(aws ssm get-command-invocation \
        --region "$BROKER_AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --query 'Status' --output text 2>/dev/null || echo "Unknown")
      SSM_OUTPUT=$(aws ssm get-command-invocation \
        --region "$BROKER_AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$EC2_INSTANCE_ID" \
        --query 'StandardOutputContent' --output text 2>/dev/null || echo "")
      if [[ "$SSM_STATUS" == "Success" ]]; then
        echo -e "  ${GREEN}Broker reset OK${RESET}"
        [[ -n "$SSM_OUTPUT" ]] && echo "  $SSM_OUTPUT" | tail -2 | sed 's/^/    /'
      else
        echo -e "  ${YELLOW}SSM status: ${SSM_STATUS}. Check manually:${RESET}"
        echo "    aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $EC2_INSTANCE_ID"
      fi
    else
      echo -e "  ${YELLOW}WARN: SSM send-command failed. Trigger reset manually:${RESET}"
      echo "    aws ssm start-session --target $EC2_INSTANCE_ID"
      echo "    curl -s -X POST http://localhost:3000/admin/reset"
    fi
  else
    echo -e "  ${YELLOW}WARN: No route-lb-haproxy EC2 instance found. Trigger reset manually.${RESET}"
  fi
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# Final cleanup: Reset MLflow traces
# ══════════════════════════════════════════════════════════════════════
# Runs AFTER all restarts/OTEL re-patching so startup traces are also wiped.
MLFLOW_ROUTE_CHECK=$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MLFLOW_ROUTE_CHECK" ]]; then
  echo -e "${BOLD}--- Resetting MLflow traces ---${RESET}"
  MLFLOW_RESET_URL="https://${MLFLOW_ROUTE_CHECK}"

  # Get experiment ID
  RESET_EXP_ID=$(curl -sk "${MLFLOW_RESET_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=openclaw-traces" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment']['experiment_id'])" 2>/dev/null || echo "")

  if [[ -n "$RESET_EXP_ID" ]]; then
    # Brief pause to let in-flight OTEL exports from gateway restarts land
    sleep 3
    CURRENT_TIME_MS=$(($(date +%s) * 1000 + 5000))
    DELETE_RESULT=$(curl -sk -X POST "${MLFLOW_RESET_URL}/api/2.0/mlflow/traces/delete-traces" \
      -H "Content-Type: application/json" \
      -d "{\"experiment_id\":\"${RESET_EXP_ID}\",\"max_timestamp_millis\":${CURRENT_TIME_MS},\"max_traces\":999999}" \
      2>/dev/null)
    TRACES_DELETED=$(echo "$DELETE_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('traces_deleted',0))" 2>/dev/null || echo "0")
    echo -e "  ${GREEN}Deleted ${TRACES_DELETED} traces from experiment ${RESET_EXP_ID}${RESET}"
  else
    echo -e "  ${YELLOW}Could not find openclaw-traces experiment — skipping${RESET}"
  fi
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
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
if [[ "$DIAG_PATCHED" == "true" ]]; then
  echo "  Prometheus: re-patched"
fi
if [[ "${OTEL_PATCHED:-false}" == "true" ]]; then
  echo "  MLflow/OTEL: re-patched"
fi
echo "  Skills:    ${SKILLS_INJECTED} injected"
echo ""

if [[ ${#AUDIENCE_URLS[@]} -gt 0 ]]; then
  if [[ -n "$STUDENT_OPENCLAW_PASSWORD" ]]; then
    echo -e "  ${BOLD}Share this URL (password: ${CYAN}${STUDENT_OPENCLAW_PASSWORD}${RESET}${BOLD}):${RESET}"
  else
    echo -e "  ${BOLD}Share this URL:${RESET}"
  fi
  echo ""
  echo -e "    ${GREEN}https://${BROKER_DOMAIN}${RESET}"
  echo ""
  echo -e "  ${DIM}Each visitor is auto-assigned an exclusive OpenClaw instance.${RESET}"
  echo -e "  ${DIM}Status board: https://${BROKER_DOMAIN}/status${RESET}"
  echo ""
  echo -e "  ${DIM}Direct URLs (admin/debug):${RESET}"
  for idx in "${!AUDIENCE_URLS[@]}"; do
    HOST="${AUDIENCE_HOSTS[$idx]}"
    PREFIX="${HOST%%.*}"
    echo -e "    ${AUDIENCE_LABELS[$idx]}: ${DIM}https://${PREFIX}.${BROKER_DOMAIN}${RESET}"
  done
  echo ""
fi
echo -e "  ${DIM}Admin URLs (stable): oc get route instance -n <namespace>${RESET}"
echo ""
