#!/usr/bin/env bash
# demo-preflight.sh — Pre-demo verification of OpenClaw + FantaCo setup
#
# Checks everything that can break between setup and showtime:
# infrastructure pods, Claw CR conditions, gateway config (model, MCP,
# allowedOrigins), audience Routes, NetworkPolicy, proxy allowlist,
# and URL reachability.
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
fi

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <start> [end]"
  echo "  $0 1 5   → check agentic-user1 through agentic-user5"
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

# ── Check claw-operator (once, not per namespace) ───────────────────
OPERATOR_OK=false
if oc auth can-i list pods -n claw-operator &>/dev/null; then
  OPERATOR_RUNNING=$(oc get pods -n claw-operator -l control-plane=controller-manager \
    --no-headers 2>/dev/null | grep -c Running || true)
  if [[ $OPERATOR_RUNNING -gt 0 ]]; then
    OPERATOR_OK=true
  fi
fi

# ── Per-namespace checks ────────────────────────────────────────────
for NS in "${NAMESPACES[@]}"; do
  PASS=0
  FAIL=0

  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Demo Preflight Check — $NS${RESET}"
  echo -e "${BOLD}============================================${RESET}"

  # ── Infrastructure ──
  echo ""
  echo -e "  ${BOLD}Infrastructure:${RESET}"

  # 1. Claw-operator running
  if [[ "$OPERATOR_OK" == "true" ]]; then
    check_pass "Claw-operator running"
  else
    check_fail "Claw-operator not running"
  fi

  # 2. Gateway pod running
  GW_POD=$(oc get pods -n "$NS" -l app=claw --no-headers 2>/dev/null | grep Running | head -1 || true)
  if [[ -n "$GW_POD" ]]; then
    check_pass "Gateway pod running"
  else
    check_fail "Gateway pod not running"
  fi

  # 3. Proxy pod running
  PROXY_POD=$(oc get pods -n "$NS" -l app=claw-proxy --no-headers 2>/dev/null | grep Running | head -1 || true)
  if [[ -n "$PROXY_POD" ]]; then
    check_pass "Proxy pod running"
  else
    check_fail "Proxy pod not running"
  fi

  # 4. Device-pairing pod running
  DP_POD=$(oc get pods -n "$NS" -l app.kubernetes.io/name=claw-device-pairing --no-headers 2>/dev/null | grep Running | head -1 || true)
  if [[ -n "$DP_POD" ]]; then
    check_pass "Device-pairing pod running"
  else
    check_fail "Device-pairing pod not running"
  fi

  # 5. FantaCo customer pods (postgresql-customer, fantaco-customer-main, mcp-customer)
  FANTACO_RUNNING=0
  FANTACO_EXPECTED=3
  for APP in postgresql-customer fantaco-customer-main mcp-customer; do
    POD_LINE=$(oc get pods -n "$NS" -l app="$APP" --no-headers 2>/dev/null | grep Running | head -1 || true)
    if [[ -n "$POD_LINE" ]]; then
      FANTACO_RUNNING=$((FANTACO_RUNNING + 1))
    fi
  done
  if [[ $FANTACO_RUNNING -eq $FANTACO_EXPECTED ]]; then
    check_pass "FantaCo customer pods (${FANTACO_RUNNING}/${FANTACO_EXPECTED})"
  else
    check_fail "FantaCo customer pods (${FANTACO_RUNNING}/${FANTACO_EXPECTED})"
  fi

  # 5b. FantaCo product pods (postgresql-product, fantaco-product-main, mcp-product)
  PRODUCT_RUNNING=0
  PRODUCT_EXPECTED=3
  for APP in postgresql-product fantaco-product-main mcp-product; do
    POD_LINE=$(oc get pods -n "$NS" -l app="$APP" --no-headers 2>/dev/null | grep Running | head -1 || true)
    if [[ -n "$POD_LINE" ]]; then
      PRODUCT_RUNNING=$((PRODUCT_RUNNING + 1))
    fi
  done
  if [[ $PRODUCT_RUNNING -eq $PRODUCT_EXPECTED ]]; then
    check_pass "FantaCo product pods (${PRODUCT_RUNNING}/${PRODUCT_EXPECTED})"
  else
    check_fail "FantaCo product pods (${PRODUCT_RUNNING}/${PRODUCT_EXPECTED})"
  fi

  # ── Claw CR Status ──
  echo ""
  echo -e "  ${BOLD}Claw CR Status:${RESET}"

  # 6. Claw CR Ready
  READY=$(oc get claw instance -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "$READY" == "True" ]]; then
    check_pass "Ready: True"
  else
    check_fail "Ready: ${READY:-not set}"
  fi

  # 7. McpServersConfigured
  MCP_COND=$(oc get claw instance -n "$NS" \
    -o jsonpath='{.status.conditions[?(@.type=="McpServersConfigured")].status}' 2>/dev/null || true)
  if [[ "$MCP_COND" == "True" ]]; then
    check_pass "McpServersConfigured: True"
  else
    check_fail "McpServersConfigured: ${MCP_COND:-not set}"
  fi

  # ── Gateway Config (single oc exec, parse locally) ──
  echo ""
  echo -e "  ${BOLD}Gateway Config:${RESET}"

  CONFIG_JSON=""
  if [[ -n "$GW_POD" ]]; then
    CONFIG_JSON=$(oc exec deployment/instance -n "$NS" -c gateway -- \
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
        check_pass "Primary model: ${PRIMARY_MODEL}"
      else
        check_fail "Primary model: ${PRIMARY_MODEL:-not set} (expected ${EXPECTED_MODEL})"
      fi
    elif [[ -n "$PRIMARY_MODEL" ]]; then
      check_pass "Primary model: ${PRIMARY_MODEL}"
    else
      check_fail "Primary model: not set"
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
      check_pass "MCP customer: ${MCP_URL}"
    else
      check_fail "MCP customer: ${MCP_URL:-not configured}"
    fi

    # 10 & 11 — Audience Route + allowedOrigins (need route host first)
    # Get audience route host
    AUDIENCE_HOST=$(oc get route audience -n "$NS" \
      -o jsonpath='{.spec.host}' 2>/dev/null || true)

    echo ""
    echo -e "  ${BOLD}Routes & Network:${RESET}"

    # 10. Audience Route exists
    if [[ -n "$AUDIENCE_HOST" ]]; then
      check_pass "Audience Route: ${AUDIENCE_HOST}"
    else
      check_fail "Audience Route: not found"
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
        check_pass "allowedOrigins includes audience host"
      else
        check_fail "allowedOrigins missing audience host (https://${AUDIENCE_HOST})"
      fi
    else
      check_fail "allowedOrigins: skipped (no audience Route)"
    fi
  else
    check_fail "Primary model: could not read openclaw.json"
    check_fail "MCP customer: could not read openclaw.json"

    echo ""
    echo -e "  ${BOLD}Routes & Network:${RESET}"

    AUDIENCE_HOST=$(oc get route audience -n "$NS" \
      -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$AUDIENCE_HOST" ]]; then
      check_pass "Audience Route: ${AUDIENCE_HOST}"
    else
      check_fail "Audience Route: not found"
    fi
    check_fail "allowedOrigins: could not read openclaw.json"
  fi

  # 12. NetworkPolicy
  NP=$(oc get networkpolicy allow-proxy-to-mcp -n "$NS" --no-headers 2>/dev/null || true)
  if [[ -n "$NP" ]]; then
    check_pass "NetworkPolicy allow-proxy-to-mcp exists"
  else
    check_fail "NetworkPolicy allow-proxy-to-mcp not found"
  fi

  # 13. Proxy allowlist includes mcp-customer-service
  PROXY_CONFIG=$(oc get configmap instance-proxy-config -n "$NS" \
    -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)
  if echo "$PROXY_CONFIG" | grep -q "mcp-customer-service"; then
    check_pass "Proxy allowlist includes mcp-customer-service"
  else
    check_fail "Proxy allowlist missing mcp-customer-service"
  fi

  # ── Reachability ──
  echo ""
  echo -e "  ${BOLD}Reachability:${RESET}"

  # 14. Admin URL reachable
  ADMIN_URL=$(oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
  if [[ -n "$ADMIN_URL" ]]; then
    ADMIN_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$ADMIN_URL" 2>/dev/null || echo "000")
    if [[ "$ADMIN_HTTP" == "200" || "$ADMIN_HTTP" == "302" ]]; then
      check_pass "Admin URL: HTTP ${ADMIN_HTTP}"
    else
      check_fail "Admin URL: HTTP ${ADMIN_HTTP} (${ADMIN_URL})"
    fi
  else
    check_fail "Admin URL: not found in Claw CR status"
  fi

  # 15. Audience URL reachable
  if [[ -n "$AUDIENCE_HOST" ]]; then
    AUDIENCE_URL="https://${AUDIENCE_HOST}"
    AUDIENCE_HTTP=$(curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 5 "$AUDIENCE_URL" 2>/dev/null || echo "000")
    if [[ "$AUDIENCE_HTTP" == "200" || "$AUDIENCE_HTTP" == "302" ]]; then
      check_pass "Audience URL: HTTP ${AUDIENCE_HTTP}"
    else
      check_fail "Audience URL: HTTP ${AUDIENCE_HTTP} (${AUDIENCE_URL})"
    fi
  else
    check_fail "Audience URL: no audience Route to test"
  fi

  # ── Per-namespace summary ──
  NS_TOTAL=$((PASS + FAIL))
  echo ""
  if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}Result: ${PASS}/${NS_TOTAL} PASSED ✓${RESET}"
  else
    echo -e "  ${RED}Result: ${PASS}/${NS_TOTAL} passed, ${FAIL} FAILED ✗${RESET}"
  fi
done

# ── Overall summary ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}============================================${RESET}"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}All ${TOTAL_PASS}/${TOTAL_CHECKS} checks passed across ${#NAMESPACES[@]} namespace(s) ✓${RESET}"
else
  echo -e "  ${RED}${TOTAL_FAIL}/${TOTAL_CHECKS} checks FAILED across ${#NAMESPACES[@]} namespace(s) ✗${RESET}"
fi
echo -e "${BOLD}============================================${RESET}"
echo ""

[[ $TOTAL_FAIL -eq 0 ]] || exit 1
