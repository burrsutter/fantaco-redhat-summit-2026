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
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"
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
  echo "Usage: $0 [start] [end]"
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
    GUID=$(KUBECONFIG="$kubeconfig_path" oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
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
  GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
  if [[ -z "$GUID" ]]; then
    echo "Error: could not extract cluster GUID from 'oc cluster-info'" >&2
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
  MAX_PARALLEL=10
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

      # 4. Device-pairing pod running
      DP_POD=$(KUBECONFIG="$CKUBE" oc get pods -n "$NS" -l app.kubernetes.io/name=claw-device-pairing --no-headers 2>/dev/null | grep Running | head -1 || true)
      if [[ -n "$DP_POD" ]]; then
        _check_pass "Device-pairing pod running"
      else
        _check_fail "Device-pairing pod not running"
      fi

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

        # 12. allowedOrigins includes yougetaclaw.com broker URL
        BROKER_ORIGIN=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json, re
try:
    c = json.load(sys.stdin)
    origins = c.get('gateway',{}).get('controlUi',{}).get('allowedOrigins',[])
    for o in origins:
        if 'yougetaclaw.com' in o:
            m = re.search(r'claw-([a-z0-9]+)-', o)
            if m:
                print(m.group(1))
            break
except: pass
" 2>/dev/null || true)

        if [[ -n "$BROKER_ORIGIN" ]]; then
          _check_pass "allowedOrigins includes broker (audience: ${BROKER_ORIGIN})"
        else
          _check_fail "allowedOrigins missing yougetaclaw.com broker URL"
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
        ADMIN_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$ADMIN_URL" 2>/dev/null || echo "000")
        if [[ "$ADMIN_HTTP" == "200" || "$ADMIN_HTTP" == "302" ]]; then
          _check_pass "Admin URL: HTTP ${ADMIN_HTTP}"
        else
          _check_fail "Admin URL: HTTP ${ADMIN_HTTP} (${ADMIN_URL})"
        fi
      else
        _check_fail "Admin URL: not found in Claw CR status"
      fi

      # 16. Audience URL reachable
      if [[ -n "$AUDIENCE_HOST" ]]; then
        AUDIENCE_URL="https://${AUDIENCE_HOST}"
        AUDIENCE_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$AUDIENCE_URL" 2>/dev/null || echo "000")
        if [[ "$AUDIENCE_HTTP" == "200" || "$AUDIENCE_HTTP" == "302" ]]; then
          _check_pass "Audience URL: HTTP ${AUDIENCE_HTTP}"
        else
          _check_fail "Audience URL: HTTP ${AUDIENCE_HTTP} (${AUDIENCE_URL})"
        fi
      else
        _check_fail "Audience URL: no audience Route to test"
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
