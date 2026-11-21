#!/usr/bin/env bash
# demo-preflight.sh — Pre-demo health-check verification
#
# Runs pass/fail checks for infrastructure pods, Claw CR conditions,
# gateway config (model, MCP, allowedOrigins), audience Routes,
# NetworkPolicy, proxy allowlist, and URL reachability.
#
# For stage-ready URLs, QR code, and provider info, see demo-urls.sh.
#
# Multi-cluster mode:
#   If clusters.csv exists (see clusters.csv.example), checks are run
#   across all listed clusters. Otherwise, uses the current oc context.
#
# Usage:
#   ./demo-preflight.sh 1 5          # check user1 through user5
#   ./demo-preflight.sh 3            # just user3
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

# ── Source .env (needed for expected model name) ──────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"

# Determine expected model key from .env
EXPECTED_MODEL=""
if [[ "$LLM_PROVIDER" == "gcp" && -n "${GEMINI_MODEL:-}" ]]; then
  EXPECTED_MODEL="google/${GEMINI_MODEL}"
elif [[ "$LLM_PROVIDER" == "litellm" && -n "${LLM_MODEL_NAME:-}" ]]; then
  EXPECTED_MODEL="openai/${LLM_MODEL_NAME}"
elif [[ "$LLM_PROVIDER" == "openrouter" && -n "${OPENROUTER_MODEL:-}" ]]; then
  EXPECTED_MODEL="openai/${OPENROUTER_MODEL}"
fi

# ── Argument parsing ────────────────────────────────────────────────
DISCOVER_ALL=false
NAMESPACES=()

# Extract --site flag before positional args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="$2"; shift 2 ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Load site config (BROKER_DOMAIN, etc.)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

if [[ $# -eq 0 ]]; then
  DISCOVER_ALL=true
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
  echo "Usage: $0 [--site NAME] [start] [end]"
  echo "  $0          → check all ${NAMESPACE_PREFIX}* namespaces (auto-discover)"
  echo "  $0 1 5      → check ${NAMESPACE_PREFIX}1 through ${NAMESPACE_PREFIX}5"
  echo "  $0 3        → just ${NAMESPACE_PREFIX}3"
  exit 1
fi

# ── Helper functions ────────────────────────────────────────────────
pass() {
  echo -e "    ${GREEN}✓${RESET} $1"
}

fail() {
  echo -e "    ${RED}✗${RESET} $1"
}

warn() {
  echo -e "    ${YELLOW}⚠${RESET} $1"
}

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_CHECKS=0

check_pass() {
  pass "$1"
  PASS=$((PASS + 1))
  TOTAL_PASS=$((TOTAL_PASS + 1))
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

check_fail() {
  fail "$1"
  FAIL=$((FAIL + 1))
  TOTAL_FAIL=$((TOTAL_FAIL + 1))
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

# ── Build cluster list ──────────────────────────────────────────────
CLUSTER_IDS=()
CLUSTER_KUBECONFIGS=()
CLUSTER_GUIDS_LIST=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})"
      exit 1
    fi
    GUID=$(KUBECONFIG="$kubeconfig_path" oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
    CLUSTER_IDS+=("$cluster_id")
    CLUSTER_KUBECONFIGS+=("$kubeconfig_path")
    CLUSTER_GUIDS_LIST+=("$GUID")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_IDS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
  echo -e "${BOLD}Multi-cluster mode:${RESET} ${#CLUSTER_IDS[@]} cluster(s)"
  echo ""
else
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  GUID=$(oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
  if [[ -z "$GUID" ]]; then
    echo "Error: could not extract cluster GUID from 'oc whoami --show-server'" >&2
    exit 1
  fi
  CLUSTER_IDS+=("default")
  CLUSTER_KUBECONFIGS+=("${KUBECONFIG:-$HOME/.kube/config}")
  CLUSTER_GUIDS_LIST+=("$GUID")
fi

# ══════════════════════════════════════════════════════════════════════
# Per-cluster, per-namespace checks
# ══════════════════════════════════════════════════════════════════════
TOTAL_CLUSTER_COUNT=${#CLUSTER_IDS[@]}
TOTAL_NS_CHECKED=0
MULTI_CLUSTER=$([[ $TOTAL_CLUSTER_COUNT -gt 1 ]] && echo true || echo false)

for ci in "${!CLUSTER_IDS[@]}"; do
  CID="${CLUSTER_IDS[$ci]}"
  CKUBE="${CLUSTER_KUBECONFIGS[$ci]}"
  CGUID="${CLUSTER_GUIDS_LIST[$ci]}"
  export KUBECONFIG="$CKUBE"

  ROUTE_IP=""
  if [[ -n "${PREFLIGHT_ROUTE_IP_MAP:-}" ]]; then
    IFS=',' read -r -a ROUTE_ENTRIES <<< "$PREFLIGHT_ROUTE_IP_MAP"
    for ROUTE_ENTRY in "${ROUTE_ENTRIES[@]}"; do
      if [[ "${ROUTE_ENTRY%%:*}" == "$CID" || "${ROUTE_ENTRY%%:*}" == "$CGUID" ]]; then
        ROUTE_IP="${ROUTE_ENTRY#*:}"
        break
      fi
    done
  fi

  # The OCP audience origins use each cluster's own apps domain, not the
  # domain of whichever cluster was active when this script started.
  if [[ "$SITE_NAME" == "ocp" ]]; then
    BROKER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  fi

  # Auto-discover namespaces on this cluster if no range given
  if $DISCOVER_ALL; then
    NAMESPACES=()
    while IFS= read -r ns; do
      NAMESPACES+=("$ns")
    done < <(oc get ns --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
      echo -e "  ${YELLOW}⚠${RESET} No ${NAMESPACE_PREFIX}* namespaces found on ${CID} — skipping"
      continue
    fi
  fi

  if $MULTI_CLUSTER; then
    APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║  Cluster: ${CID} (${APPS_DOMAIN:-unknown}) — ${#NAMESPACES[@]} namespaces${RESET}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
  fi

  # Source Langfuse keys from cluster state
  LANGFUSE_STATE="${SCRIPT_DIR}/.state/${CGUID}/langfuse.env"
  LANGFUSE_PUBLIC_KEY=""
  LANGFUSE_SECRET_KEY=""
  if [[ -f "$LANGFUSE_STATE" ]]; then
    # shellcheck disable=SC1090
    source "$LANGFUSE_STATE"
    LANGFUSE_PUBLIC_KEY="${INIT_PUBLIC_KEY:-}"
    LANGFUSE_SECRET_KEY="${INIT_SECRET_KEY:-}"
  fi

  TOTAL_NS_CHECKED=$((TOTAL_NS_CHECKED + ${#NAMESPACES[@]}))

  # ── Check claw-operator (once per cluster) ───────────────────
  OPERATOR_OK=false
  if oc auth can-i list pods -n claw-operator &>/dev/null; then
    OPERATOR_RUNNING=$(oc get pods -n claw-operator -l control-plane=controller-manager \
      --no-headers 2>/dev/null | grep -c Running || true)
    if [[ $OPERATOR_RUNNING -gt 0 ]]; then
      OPERATOR_OK=true
    fi
  fi

  # ── Per-namespace checks (parallel) ──────────────────────────────────
  PREFLIGHT_TMPDIR=$(mktemp -d)
  MAX_PARALLEL="${PREFLIGHT_MAX_PARALLEL:-10}"
  JOB_COUNT=0

  for NS in "${NAMESPACES[@]}"; do
    (
      # Local pass/fail tracking (subshell-scoped)
      _PASS=0
      _FAIL=0
      _check_pass() { echo -e "    ${GREEN}✓${RESET} $1"; _PASS=$((_PASS + 1)); }
      _check_fail() { echo -e "    ${RED}✗${RESET} $1"; _FAIL=$((_FAIL + 1)); }

      echo ""
      echo -e "${BOLD}============================================${RESET}"
      if $MULTI_CLUSTER; then
        echo -e "${BOLD}  Demo Preflight — ${CID} / $NS${RESET}"
      else
        echo -e "${BOLD}  Demo Preflight Check — $NS${RESET}"
      fi
      echo -e "${BOLD}============================================${RESET}"

      # ── Infrastructure ──
      echo ""
      echo -e "  ${BOLD}Infrastructure:${RESET}"

      # 1. Claw-operator running
      if [[ "$OPERATOR_OK" == "true" ]]; then
        _check_pass "Claw-operator running"
      else
        _check_fail "Claw-operator not running"
      fi

      # 2. Gateway pod running
      GW_POD=$(KUBECONFIG="$CKUBE" oc get pods -n "$NS" -l app=claw --no-headers 2>/dev/null | grep Running | head -1 || true)
      if [[ -n "$GW_POD" ]]; then
        _check_pass "Gateway pod running"
      else
        _check_fail "Gateway pod not running"
      fi

      # 3. Proxy pod running
      PROXY_POD=$(KUBECONFIG="$CKUBE" oc get pods -n "$NS" -l app=claw-proxy --no-headers 2>/dev/null | grep Running | head -1 || true)
      if [[ -n "$PROXY_POD" ]]; then
        _check_pass "Proxy pod running"
      else
        _check_fail "Proxy pod not running"
      fi

      # 4. Device-pairing was removed by claw-operator 554d988 (OpenClaw 2026.6.35).
      # The operator now actively deletes instance-device-pairing, so there is
      # nothing to check here.

      # 5. FantaCo customer pods (postgresql-customer, fantaco-customer-main, mcp-customer)
      FANTACO_RUNNING=0
      FANTACO_EXPECTED=3
      for APP in postgresql-customer fantaco-customer-main mcp-customer; do
        POD_LINE=$(KUBECONFIG="$CKUBE" oc get pods -n "$NS" -l app="$APP" --no-headers 2>/dev/null | grep Running | head -1 || true)
        if [[ -n "$POD_LINE" ]]; then
          FANTACO_RUNNING=$((FANTACO_RUNNING + 1))
        fi
      done
      if [[ $FANTACO_RUNNING -eq $FANTACO_EXPECTED ]]; then
        _check_pass "FantaCo customer pods (${FANTACO_RUNNING}/${FANTACO_EXPECTED})"
      else
        _check_fail "FantaCo customer pods (${FANTACO_RUNNING}/${FANTACO_EXPECTED})"
      fi

      # 5b. FantaCo product pods (postgresql-product, fantaco-product-main, mcp-product)
      PRODUCT_RUNNING=0
      PRODUCT_EXPECTED=3
      for APP in postgresql-product fantaco-product-main mcp-product; do
        POD_LINE=$(KUBECONFIG="$CKUBE" oc get pods -n "$NS" -l app="$APP" --no-headers 2>/dev/null | grep Running | head -1 || true)
        if [[ -n "$POD_LINE" ]]; then
          PRODUCT_RUNNING=$((PRODUCT_RUNNING + 1))
        fi
      done
      if [[ $PRODUCT_RUNNING -eq $PRODUCT_EXPECTED ]]; then
        _check_pass "FantaCo product pods (${PRODUCT_RUNNING}/${PRODUCT_EXPECTED})"
      else
        _check_fail "FantaCo product pods (${PRODUCT_RUNNING}/${PRODUCT_EXPECTED})"
      fi

      # ── Claw CR Status ──
      echo ""
      echo -e "  ${BOLD}Claw CR Status:${RESET}"

      # 6. Claw CR Ready
      READY=$(KUBECONFIG="$CKUBE" oc get claw instance -n "$NS" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
      if [[ "$READY" == "True" ]]; then
        _check_pass "Ready: True"
      else
        _check_fail "Ready: ${READY:-not set}"
      fi

      # 7. McpServersConfigured
      MCP_COND=$(KUBECONFIG="$CKUBE" oc get claw instance -n "$NS" \
        -o jsonpath='{.status.conditions[?(@.type=="McpServersConfigured")].status}' 2>/dev/null || true)
      if [[ "$MCP_COND" == "True" ]]; then
        _check_pass "McpServersConfigured: True"
      else
        _check_fail "McpServersConfigured: ${MCP_COND:-not set}"
      fi

      # ── Gateway Config (single oc exec, parse locally) ──
      echo ""
      echo -e "  ${BOLD}Gateway Config:${RESET}"

      CONFIG_JSON=""
      if [[ -n "$GW_POD" ]]; then
        CONFIG_JSON=$(KUBECONFIG="$CKUBE" oc exec deployment/instance -n "$NS" -c gateway -- \
          node -e 'const fs=require("fs"); try { process.stdout.write(fs.readFileSync("/home/node/.openclaw/openclaw.json","utf8")); } catch(e) { process.stdout.write("{}"); }' \
          2>/dev/null || echo "{}")
      fi

      # 8. Primary model
      if [[ -n "$CONFIG_JSON" && "$CONFIG_JSON" != "{}" ]]; then
        PRIMARY_MODEL=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    c = json.load(sys.stdin)
    print(c.get('agents',{}).get('defaults',{}).get('model',{}).get('primary',''))
except: print('')
" 2>/dev/null || true)

        if [[ -n "$EXPECTED_MODEL" ]]; then
          if [[ "$PRIMARY_MODEL" == "$EXPECTED_MODEL" ]]; then
            _check_pass "Primary model: ${PRIMARY_MODEL}"
          else
            _check_fail "Primary model: ${PRIMARY_MODEL:-not set} (expected ${EXPECTED_MODEL})"
          fi
        elif [[ -n "$PRIMARY_MODEL" ]]; then
          _check_pass "Primary model: ${PRIMARY_MODEL}"
        else
          _check_fail "Primary model: not set"
        fi

        # 9. MCP customer in gateway config
        MCP_URL=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    c = json.load(sys.stdin)
    print(c.get('mcp',{}).get('servers',{}).get('customer',{}).get('url',''))
except: print('')
" 2>/dev/null || true)

        if echo "$MCP_URL" | grep -q "mcp-customer-service:9001"; then
          _check_pass "MCP customer: ${MCP_URL}"
        else
          _check_fail "MCP customer: ${MCP_URL:-not configured}"
        fi

        # 9b. API key not leaked in gateway pod
        # Check both openclaw.json and env vars for real API keys (sk-or-v1-*)
        API_KEY_IN_CONFIG=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    c = json.load(sys.stdin)
    key = c.get('models',{}).get('providers',{}).get('openai',{}).get('apiKey','')
    print('leaked' if key.startswith('sk-or-') else 'safe')
except: print('safe')
" 2>/dev/null || true)

        API_KEY_IN_ENV=$(KUBECONFIG="$CKUBE" oc exec deployment/instance -n "$NS" -c gateway -- \
          env 2>/dev/null | grep -c 'sk-or-v1-' || true)

        if [[ "$API_KEY_IN_CONFIG" == "safe" && "$API_KEY_IN_ENV" -eq 0 ]]; then
          _check_pass "API key not leaked in gateway pod"
        else
          _check_fail "API key LEAKED in gateway pod (config=${API_KEY_IN_CONFIG}, env_matches=${API_KEY_IN_ENV})"
        fi

        # 9c. Langfuse keys not leaked in gateway pod
        LANGFUSE_IN_ENV=$(KUBECONFIG="$CKUBE" oc exec deployment/instance -n "$NS" -c gateway -- \
          env 2>/dev/null | grep -cE '(LANGFUSE_PUBLIC_KEY|LANGFUSE_SECRET_KEY)=' || true)

        LANGFUSE_IN_CONFIG=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    c = json.load(sys.stdin)
    # Check plugin entries and diagnostics for key-like values
    plugins = c.get('plugins',{}).get('entries',{})
    lt = plugins.get('langfuse-tracer',{})
    otel_headers = c.get('diagnostics',{}).get('otel',{}).get('headers',{})
    combined = json.dumps(lt) + json.dumps(otel_headers)
    print('leaked' if ('pk-lf-' in combined or 'sk-lf-' in combined) else 'safe')
except: print('safe')
" 2>/dev/null || true)

        if [[ "$LANGFUSE_IN_ENV" -eq 0 && "$LANGFUSE_IN_CONFIG" == "safe" ]]; then
          _check_pass "Langfuse keys not leaked in gateway pod"
        else
          _check_fail "Langfuse keys LEAKED in gateway pod (env_matches=${LANGFUSE_IN_ENV}, config=${LANGFUSE_IN_CONFIG})"
        fi

        # 10 & 11 — Audience Route + allowedOrigins (need route host first)
        # Get audience route host
        AUDIENCE_HOST=$(KUBECONFIG="$CKUBE" oc get route audience -n "$NS" \
          -o jsonpath='{.spec.host}' 2>/dev/null || true)

        echo ""
        echo -e "  ${BOLD}Routes & Network:${RESET}"

        # 10. Audience Route exists
        if [[ -n "$AUDIENCE_HOST" ]]; then
          _check_pass "Audience Route: ${AUDIENCE_HOST}"
        else
          _check_fail "Audience Route: not found"
        fi

        # 11. allowedOrigins includes audience host
        if [[ -n "$AUDIENCE_HOST" ]]; then
          ORIGINS_HAS_HOST=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    c = json.load(sys.stdin)
    origins = c.get('gateway',{}).get('controlUi',{}).get('allowedOrigins',[])
    host = 'https://${AUDIENCE_HOST}'
    print('yes' if host in origins else 'no')
except: print('no')
" 2>/dev/null || true)

          if [[ "$ORIGINS_HAS_HOST" == "yes" ]]; then
            _check_pass "allowedOrigins includes audience host"
          else
            _check_fail "allowedOrigins missing audience host (https://${AUDIENCE_HOST})"
          fi
        else
          _check_fail "allowedOrigins: skipped (no audience Route)"
        fi

        # 12. allowedOrigins includes broker domain
        BROKER_ORIGIN=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json, re
try:
    c = json.load(sys.stdin)
    origins = c.get('gateway',{}).get('controlUi',{}).get('allowedOrigins',[])
    # Keep scanning past non-audience origins: in OCP broker mode BROKER_DOMAIN
    # is the cluster apps domain, so the admin Route origin matches it too.
    for o in origins:
        if '${BROKER_DOMAIN}' in o:
            m = re.search(r'claw-([a-z0-9]+)-', o)
            if m:
                print(m.group(1))
                break
except: pass
" 2>/dev/null || true)

        if [[ -n "$BROKER_ORIGIN" ]]; then
          _check_pass "allowedOrigins includes broker (audience: ${BROKER_ORIGIN})"
        else
          _check_fail "allowedOrigins missing ${BROKER_DOMAIN} broker URL"
        fi
      else
        _check_fail "Primary model: could not read openclaw.json"
        _check_fail "MCP customer: could not read openclaw.json"

        echo ""
        echo -e "  ${BOLD}Routes & Network:${RESET}"

        AUDIENCE_HOST=$(KUBECONFIG="$CKUBE" oc get route audience -n "$NS" \
          -o jsonpath='{.spec.host}' 2>/dev/null || true)
        if [[ -n "$AUDIENCE_HOST" ]]; then
          _check_pass "Audience Route: ${AUDIENCE_HOST}"
        else
          _check_fail "Audience Route: not found"
        fi
        _check_fail "allowedOrigins: could not read openclaw.json"
        _check_fail "Broker origin: could not read openclaw.json"
      fi

      # 13. NetworkPolicy
      NP=$(KUBECONFIG="$CKUBE" oc get networkpolicy allow-proxy-to-mcp -n "$NS" --no-headers 2>/dev/null || true)
      if [[ -n "$NP" ]]; then
        _check_pass "NetworkPolicy allow-proxy-to-mcp exists"
      else
        _check_fail "NetworkPolicy allow-proxy-to-mcp not found"
      fi

      # 14. Proxy allowlist includes mcp-customer-service
      PROXY_CONFIG=$(KUBECONFIG="$CKUBE" oc get configmap instance-proxy-config -n "$NS" \
        -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)
      if echo "$PROXY_CONFIG" | grep -q "mcp-customer-service"; then
        _check_pass "Proxy allowlist includes mcp-customer-service"
      else
        _check_fail "Proxy allowlist missing mcp-customer-service"
      fi

      # ── Reachability ──
      echo ""
      echo -e "  ${BOLD}Reachability:${RESET}"

      # 15. Admin URL reachable
      ADMIN_URL=$(KUBECONFIG="$CKUBE" oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
      if [[ -n "$ADMIN_URL" ]]; then
        ADMIN_SAFE_URL="${ADMIN_URL%%#*}"
        ADMIN_HOST="${ADMIN_SAFE_URL#https://}"
        ADMIN_HOST="${ADMIN_HOST%%/*}"
        ADMIN_RESOLVE=()
        if [[ -n "$ROUTE_IP" ]]; then
          ADMIN_RESOLVE=(--resolve "${ADMIN_HOST}:443:${ROUTE_IP}")
        fi
        # curl already prints "000" on a failed connection and then exits
        # non-zero, so `|| echo 000` inside $( ) yields "000000".
        ADMIN_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 \
          --max-time 20 --retry 2 --retry-delay 1 --retry-all-errors \
          ${ADMIN_RESOLVE[@]+"${ADMIN_RESOLVE[@]}"} \
          "$ADMIN_SAFE_URL" 2>/dev/null) || true
        ADMIN_HTTP="${ADMIN_HTTP:-000}"
        if [[ "$ADMIN_HTTP" == "200" || "$ADMIN_HTTP" == "302" ]]; then
          _check_pass "Admin URL: HTTP ${ADMIN_HTTP}"
        else
          _check_fail "Admin URL: HTTP ${ADMIN_HTTP} (${ADMIN_SAFE_URL})"
        fi
      else
        _check_fail "Admin URL: not found in Claw CR status"
      fi

      # 16. Audience URL reachable
      if [[ -n "$AUDIENCE_HOST" ]]; then
        AUDIENCE_URL="https://${AUDIENCE_HOST}"
        AUDIENCE_RESOLVE=()
        if [[ -n "$ROUTE_IP" ]]; then
          AUDIENCE_RESOLVE=(--resolve "${AUDIENCE_HOST}:443:${ROUTE_IP}")
        fi
        # curl already prints "000" on a failed connection and then exits
        # non-zero, so `|| echo 000` inside $( ) yields "000000".
        AUDIENCE_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 \
          --max-time 20 --retry 2 --retry-delay 1 --retry-all-errors \
          ${AUDIENCE_RESOLVE[@]+"${AUDIENCE_RESOLVE[@]}"} \
          "$AUDIENCE_URL" 2>/dev/null) || true
        AUDIENCE_HTTP="${AUDIENCE_HTTP:-000}"
        if [[ "$AUDIENCE_HTTP" == "200" || "$AUDIENCE_HTTP" == "302" ]]; then
          _check_pass "Audience URL: HTTP ${AUDIENCE_HTTP}"
        else
          _check_fail "Audience URL: HTTP ${AUDIENCE_HTTP} (${AUDIENCE_URL})"
        fi
      else
        _check_fail "Audience URL: no audience Route to test"
      fi

      # 17. Heartbeat is actually muzzled.
      #
      # Check the FILE, not the config and not the CLI. workspace/HEARTBEAT.md
      # present with comments-only content is what makes the heartbeat skip
      # ('empty-heartbeat-file'). If the file is ABSENT, OpenClaw falls back to
      # a built-in default prompt and polls every 30 min at ~40k tokens a time
      # — idle spend plus heartbeat traces that pollute the MLflow list.
      #
      # agents.defaults.heartbeat in openclaw.json is null on every seat either
      # way, so it proves nothing; `system heartbeat disable` only writes
      # state/openclaw.sqlite, which audience-reset wipes. The file is the one
      # durable signal. Verified on rosa-tztnl 2026-11-17 across 8/8 seats.
      HB_BYTES=$(oc exec deployment/instance -n "$NS" -c gateway -- \
        sh -c 'wc -c < /home/node/.openclaw/workspace/HEARTBEAT.md 2>/dev/null || echo MISSING' 2>/dev/null | tr -d ' \r')
      if [[ "$HB_BYTES" == "MISSING" || -z "$HB_BYTES" ]]; then
        _check_fail "Heartbeat muzzled: HEARTBEAT.md MISSING (heartbeat will fire ~every 30m)"
      elif oc exec deployment/instance -n "$NS" -c gateway -- \
             sh -c 'grep -qvE "^\s*(#|<!--|$)" /home/node/.openclaw/workspace/HEARTBEAT.md' 2>/dev/null; then
        _check_fail "Heartbeat muzzled: HEARTBEAT.md has non-comment content (heartbeat will fire)"
      else
        _check_pass "Heartbeat muzzled (HEARTBEAT.md comments-only, ${HB_BYTES}b)"
      fi

      # 18. Seeded skill is actually on the seat.
      #
      # This check exists because its absence was discovered ON STAGE. On
      # 2026-11-10 preflight passed 3240/3240 while the presenter's own seat
      # had no /quote, and on rosa-7s2hf 5 of 200 seats were missing it with
      # zero DNS errors — `6-inject-enterprise-skills.sh` copies the skill in
      # after pod creation and that lands unreliably at fleet scale (~2.5%).
      # Nothing else reports it: the seat is healthy, pods Running, metrics up.
      #
      # LIMITATION, stated honestly: this checks the FILE, not what the agent
      # can see. The stronger test is asking the agent to list its skills, but
      # that is a full LLM turn per seat and far too slow for a 100-seat
      # preflight. A present file has always correlated with a working /quote;
      # if a seat passes here and still has no /quote, ask the agent directly:
      #   oc exec deployment/instance -n <ns> -c gateway -- \
      #     node /app/dist/index.js --no-color agent --session-id check \
      #     --message "List the names of the skills you can use." --json
      SEEDED_SKILL="${PREFLIGHT_SEEDED_SKILL:-quote-builder}"
      SKILL_FOUND=$(oc exec deployment/instance -n "$NS" -c gateway -- \
        sh -c "ls /home/node/.openclaw/workspace/skills/${SEEDED_SKILL}/SKILL.md 2>/dev/null | wc -l" \
        2>/dev/null | tr -d ' \r')
      if [[ "$SKILL_FOUND" == "1" ]]; then
        _check_pass "Seeded skill present (${SEEDED_SKILL})"
      else
        _check_fail "Seeded skill MISSING (${SEEDED_SKILL}) — repair with ./6-inject-enterprise-skills.sh ${NS##*user} ${NS##*user}"
      fi

      # ── Per-namespace summary ──
      NS_TOTAL=$((_PASS + _FAIL))
      echo ""
      if [[ $_FAIL -eq 0 ]]; then
        echo -e "  ${GREEN}Result: ${_PASS}/${NS_TOTAL} PASSED ✓${RESET}"
      else
        echo -e "  ${RED}Result: ${_PASS}/${NS_TOTAL} passed, ${_FAIL} FAILED ✗${RESET}"
      fi

      # Write counts for aggregation
      echo "${_PASS} ${_FAIL}" > "${PREFLIGHT_TMPDIR}/${NS}.counts"
    ) > "${PREFLIGHT_TMPDIR}/${NS}.out" 2>&1 &

    JOB_COUNT=$((JOB_COUNT + 1))
    if (( JOB_COUNT >= MAX_PARALLEL )); then
      wait
      JOB_COUNT=0
    fi
  done
  wait  # wait for remaining jobs

  # Print results in namespace order and aggregate counts
  for NS in "${NAMESPACES[@]}"; do
    cat "${PREFLIGHT_TMPDIR}/${NS}.out"
    if [[ -f "${PREFLIGHT_TMPDIR}/${NS}.counts" ]]; then
      read -r P F < "${PREFLIGHT_TMPDIR}/${NS}.counts"
      TOTAL_PASS=$((TOTAL_PASS + P))
      TOTAL_FAIL=$((TOTAL_FAIL + F))
      TOTAL_CHECKS=$((TOTAL_CHECKS + P + F))
    fi
  done

  rm -rf "$PREFLIGHT_TMPDIR"

done  # end cluster loop

# ── Overall summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================${RESET}"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  if $MULTI_CLUSTER; then
    echo -e "  ${GREEN}All ${TOTAL_PASS}/${TOTAL_CHECKS} checks passed across ${TOTAL_NS_CHECKED} namespace(s) on ${TOTAL_CLUSTER_COUNT} cluster(s) ✓${RESET}"
  else
    echo -e "  ${GREEN}All ${TOTAL_PASS}/${TOTAL_CHECKS} checks passed across ${TOTAL_NS_CHECKED} namespace(s) ✓${RESET}"
  fi
else
  if $MULTI_CLUSTER; then
    echo -e "  ${RED}${TOTAL_FAIL}/${TOTAL_CHECKS} checks FAILED across ${TOTAL_NS_CHECKED} namespace(s) on ${TOTAL_CLUSTER_COUNT} cluster(s) ✗${RESET}"
  else
    echo -e "  ${RED}${TOTAL_FAIL}/${TOTAL_CHECKS} checks FAILED across ${TOTAL_NS_CHECKED} namespace(s) ✗${RESET}"
  fi
fi
echo -e "${BOLD}============================================${RESET}"
echo ""

[[ $TOTAL_FAIL -eq 0 ]] || exit 1
