#!/usr/bin/env bash
#
# run-demo.sh — Send FantaCo demo prompts via the OpenClaw REST API
#               and evaluate responses against expected keywords.
#
# Usage:
#   ./scripts/run-demo.sh [--step N] [--dry-run] [--timeout 120]
#
# Options:
#   --step N      Run only step N (e.g. 1, 5a, 7)
#   --dry-run     Show prompts without sending
#   --timeout S   Max seconds to wait per response (default 120)

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=false
SINGLE_STEP=""
TIMEOUT=120

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)    SINGLE_STEP="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true;     shift   ;;
    --timeout) TIMEOUT="$2";     shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Resolve gateway URL and token ─────────────────────────────────────────────
resolve_gateway() {
  echo -e "${CYAN}Resolving OpenClaw gateway...${RESET}"

  ROUTE=$(oc get route openclaw-route -o jsonpath='{.spec.host}' 2>/dev/null) || {
    echo -e "${RED}ERROR: Could not get openclaw-route. Is oc logged in?${RESET}" >&2
    exit 1
  }
  BASE_URL="https://${ROUTE}"
  echo "  Route: ${BASE_URL}"

  TOKEN=$(oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])" 2>/dev/null) || {
    echo -e "${RED}ERROR: Could not extract gateway token from pod.${RESET}" >&2
    exit 1
  }
  echo "  Token: ${TOKEN:0:8}..."

  # Health check
  HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "${BASE_URL}/api/status")
  if [[ "$HTTP_CODE" != "200" ]]; then
    echo -e "${RED}ERROR: /api/status returned HTTP ${HTTP_CODE}${RESET}" >&2
    exit 1
  fi
  echo -e "  Status: ${GREEN}OK${RESET}"
  echo
}

# ── Send a prompt and return the response text ────────────────────────────────
send_prompt() {
  local prompt="$1"
  local payload
  payload=$(python3 -c "import json,sys; print(json.dumps({'message': sys.argv[1]}))" "$prompt" 2>/dev/null \
    || printf '{"message": "%s"}' "$(echo "$prompt" | sed 's/"/\\"/g')")

  local response
  response=$(curl -sk --max-time "${TIMEOUT}" \
    -X POST "${BASE_URL}/api/sessions/main/messages" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload}" 2>&1) || {
    echo "CURL_ERROR: $response"
    return 1
  }

  # Extract assistant reply — try .response, .message, .content, then raw
  local text
  text=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, dict):
        print(d.get('response') or d.get('message') or d.get('content') or json.dumps(d))
    else:
        print(d)
except:
    print(sys.stdin.read())
" 2>/dev/null) || text="$response"

  echo "$text"
}

# ── Keyword evaluation ────────────────────────────────────────────────────────
check_keywords() {
  local response="$1"
  shift
  local keywords=("$@")

  local lower_response
  lower_response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  for kw in "${keywords[@]}"; do
    local lower_kw
    lower_kw=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_response" | grep -q "$lower_kw"; then
      return 0
    fi
  done
  return 1
}

# ── Prompt table ──────────────────────────────────────────────────────────────
# Format: step|prompt|keyword1,keyword2,...|mode (auto or skip)
PROMPTS=(
  '1|Your name is FantaBot|FantaBot|auto'
  '1|My name is Sally Sellers|Sally|auto'
  '1|Create a memory: My Birthday is April 9 1987|memory,saved,created,stored,remembered|auto'
  '2|What are your available skills?|skill|auto'
  '2|What are your available tools?|tool|auto'
  '3|How is the 401K handled here at FantaCo|401,retirement,match|auto'
  '4|Who are my customers?|customer|auto'
  '5|What are Tech Solutions recent orders?|order|auto'
  '5|Any notes associated with Tech Solutions?|note|auto'
  '5|Any projects for Tech Solutions?|project|auto'
  '5a|Does Tech Solutions have any outstanding invoices?|invoice|auto'
  '5b|What products do we have for the Enchanted Forest theme?|product,Enchanted Forest|auto'
  '6|Create a scheduled task, every 1 minute, check Tech Solutions projects and alert me for urgent items via Telegram|scheduled,task,created|skip'
  '6a|Also create a scheduled task, every 4 hours, check if any of my customers have overdue invoices and alert me via Telegram|scheduled,task,created|skip'
  '7|What is our return sales policy?|return,policy|auto'
  '8|I wish to learn how to create my own Skills. Create a Skill that simply asks for a name and then responds with Jambo, Bonjour, Aloha <name>|skill,created|skip'
  '8|Lets test the skill, Greet Marvin|Jambo,Bonjour,Aloha|skip'
  '9|Create another skill that manages personal customer notes that uses the workspace memory and when creating the notes identifies the customer. If there is any confusion related to the customer name ask for clarity using the customer database add the URL to our internal customer browser for that specific customer|skill,created,note|skip'
  '10|Who are the contacts for Tech Solutions?|contact|skip'
  '10|Update my personal notes of Tech Solutions CEO David his wife name is Bianca, they have two children ages 4 and 8, Blake and Dion He is a big fan of Van Halen|note,saved,updated,memory|skip'
  '11|who is my primary contact at NovaSpark AI Labs?|contact,NovaSpark|skip'
  '11a|Give me a full account briefing for NovaSpark AI Labs — contacts, recent orders, invoices, and any projects|NovaSpark,order,invoice,project|skip'
  '12|Start a new project for customer NovaSpark AI Labs based on theme Enchanted Forest|project,created,Enchanted|skip'
  '12a|Show me my active agents|agent,watchdog,monitor|skip'
  '12a|What has the Account Watchdog found recently?|watchdog,found,alert,report|skip'
)

# ── Run ───────────────────────────────────────────────────────────────────────
declare -a RESULTS=()
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

run_step() {
  local entry="$1"
  local step prompt keywords_str mode
  IFS='|' read -r step prompt keywords_str mode <<< "$entry"

  # Filter by --step if set
  if [[ -n "$SINGLE_STEP" && "$step" != "$SINGLE_STEP" ]]; then
    return
  fi

  local short_prompt
  if [[ ${#prompt} -gt 50 ]]; then
    short_prompt="${prompt:0:47}..."
  else
    short_prompt="$prompt"
  fi

  # Skip interactive steps
  if [[ "$mode" == "skip" ]]; then
    printf "  ${YELLOW}SKIP${RESET}  %-6s %s ${YELLOW}(interactive)${RESET}\n" "$step" "$short_prompt"
    RESULTS+=("SKIP|$step|$short_prompt|0.0|(interactive)")
    SKIP_COUNT=$((SKIP_COUNT + 1))
    return
  fi

  # Dry-run
  if $DRY_RUN; then
    printf "  ${CYAN}DRY ${RESET}  %-6s %s\n" "$step" "$short_prompt"
    RESULTS+=("DRY|$step|$short_prompt|0.0|")
    return
  fi

  # Send
  printf "  ${CYAN}SEND${RESET}  %-6s %s " "$step" "$short_prompt"

  local start_time end_time elapsed response
  start_time=$(date +%s.%N 2>/dev/null || date +%s)

  response=$(send_prompt "$prompt")

  end_time=$(date +%s.%N 2>/dev/null || date +%s)
  elapsed=$(python3 -c "print(f'{${end_time} - ${start_time}:.1f}')" 2>/dev/null || echo "?")

  # Evaluate
  IFS=',' read -ra kw_array <<< "$keywords_str"
  if check_keywords "$response" "${kw_array[@]}"; then
    printf "\r  ${GREEN}PASS${RESET}  %-6s %-50s ${GREEN}%ss${RESET}\n" "$step" "$short_prompt" "$elapsed"
    RESULTS+=("PASS|$step|$short_prompt|$elapsed|")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "\r  ${RED}FAIL${RESET}  %-6s %-50s ${RED}%ss${RESET}\n" "$step" "$short_prompt" "$elapsed"
    # Show first 200 chars of response for debugging
    echo -e "         ${RED}Response (truncated): ${response:0:200}${RESET}"
    RESULTS+=("FAIL|$step|$short_prompt|$elapsed|$response")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

main() {
  echo
  echo -e "${BOLD}=== FantaCo Demo Runner ===${RESET}"
  echo

  if ! $DRY_RUN; then
    resolve_gateway
  else
    echo -e "${YELLOW}DRY RUN — prompts will not be sent${RESET}"
    echo
  fi

  echo -e "${BOLD}Running prompts...${RESET}"
  echo

  for entry in "${PROMPTS[@]}"; do
    run_step "$entry"
  done

  # Summary
  echo
  echo -e "${BOLD}=== Summary ===${RESET}"
  echo
  printf "  %-6s %-50s %-6s %s\n" "Step" "Prompt" "Status" "Time"
  printf "  %-6s %-50s %-6s %s\n" "----" "------" "------" "----"
  for r in "${RESULTS[@]}"; do
    local status step prompt elapsed note
    IFS='|' read -r status step prompt elapsed note <<< "$r"
    case "$status" in
      PASS) printf "  %-6s %-50s ${GREEN}%-6s${RESET} %ss\n" "$step" "$prompt" "$status" "$elapsed" ;;
      FAIL) printf "  %-6s %-50s ${RED}%-6s${RESET} %ss\n" "$step" "$prompt" "$status" "$elapsed" ;;
      SKIP) printf "  %-6s %-50s ${YELLOW}%-6s${RESET} %s\n" "$step" "$prompt" "$status" "$note" ;;
      DRY)  printf "  %-6s %-50s ${CYAN}%-6s${RESET}\n" "$step" "$prompt" "$status" ;;
    esac
  done

  echo
  if $DRY_RUN; then
    echo -e "  Total: ${#RESULTS[@]} prompts listed"
  else
    echo -e "  ${GREEN}Passed: ${PASS_COUNT}${RESET}   ${YELLOW}Skipped: ${SKIP_COUNT}${RESET}   ${RED}Failed: ${FAIL_COUNT}${RESET}"
  fi
  echo

  # Exit code: fail if any FAIL
  if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
  fi
}

main
