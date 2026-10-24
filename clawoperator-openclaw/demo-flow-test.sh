#!/usr/bin/env bash
# demo-flow-test.sh — End-to-end test for the OpenClaw live demo script
#
# Replays the complete demo flow against a single namespace and reports
# PASS/FAIL per step. Safe to re-run; non-destructive to other namespaces.
#
# Usage:
#   ./demo-flow-test.sh                    # test agentic-user22 (default)
#   ./demo-flow-test.sh --namespace 3      # test agentic-user3
#   ./demo-flow-test.sh --verbose          # show full LLM replies
#   ./demo-flow-test.sh --step 2           # run only section 2
#   ./demo-flow-test.sh --cleanup          # remove test-created skills
#   ./demo-flow-test.sh --force            # run even if model has known issues
#
# Requirements:
#   - OpenShift cluster with OpenClaw deployed
#   - Working model configuration (gpt-oss-120b or compatible)
#   - MCP servers: customer, product, sales-order
#   - Pre-existing skills: platform, quote-builder

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
DEFAULT_NS="${NAMESPACE_PREFIX}22"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Arguments ---
NAMESPACE="$DEFAULT_NS"
VERBOSE=false
STEP_FILTER=""
CLEANUP_MODE=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${NAMESPACE_PREFIX}$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    --step) STEP_FILTER="$2"; shift 2 ;;
    --cleanup) CLEANUP_MODE=true; shift ;;
    --force) FORCE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Test state ---
SESSION_ID="demo-flow-$(date +%s)"
PASS=0
FAIL=0
SKIP=0
# Tool-driven steps (MCP customer lookups, skill creation, quote builder) chain
# several model calls per turn, and the MaaS-hosted models run ~10s to first
# byte, so 120s times out on the later sections.
AGENT_TIMEOUT=300  # seconds per LLM call

# --- Helper: execute oc command with namespace context ---
# stderr is discarded, not folded into stdout: `oc exec` writes "command
# terminated with exit code N" to stderr when the remote command fails, and on a
# clean namespace `ls` of a not-yet-created skills directory does exactly that.
# With 2>&1 that message became the captured listing, so cleanup_skills would
# "remove" a skill literally named `command terminated with exit code 2` and
# report success on a namespace where there was nothing to remove.
oc_exec() {
  oc exec deployment/instance -n "$NAMESPACE" -c gateway -- "$@" 2>/dev/null
}

# --- Helper: send message to gateway and capture reply ---
# Returns: JSON output from the agent command
# Side effects: prints errors to stderr
send_message() {
  local message="$1"
  local msg_timeout="${2:-$AGENT_TIMEOUT}"

  local result raw_result
  raw_result=$(timeout "$msg_timeout" oc exec deployment/instance -n "$NAMESPACE" -c gateway -- \
    node /app/dist/index.js --no-color agent \
    --session-id "$SESSION_ID" \
    --message "$message" \
    --json 2>&1) || {
    echo "$raw_result" >&2
    return 1
  }

  # Filter out warning lines before the JSON
  result=$(echo "$raw_result" | sed -n '/{/,$p')
  echo "$result"
}

# --- Helper: extract reply text from JSON, stripping <think> blocks ---
extract_reply() {
  local json="$1"
  echo "$json" | python3 -c "
import sys, json, re
try:
    data = json.load(sys.stdin)
    # Try multiple paths for the reply text
    reply = ''
    if 'reply' in data and 'text' in data['reply']:
        reply = data['reply']['text']
    elif 'result' in data and 'payloads' in data['result']:
        payloads = data['result']['payloads']
        if payloads and len(payloads) > 0 and 'text' in payloads[0]:
            reply = payloads[0]['text']
    # Strip <think>...</think> reasoning blocks
    reply = re.sub(r'<think>.*?</think>', '', reply, flags=re.DOTALL)
    print(reply.strip())
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo ""
}

# --- Helper: fold Unicode spaces to a plain ASCII space ---
# The model does not always separate words with U+0020. It reliably writes
# "Def Leppard" (narrow no-break space) when recalling the band, so a
# literal grep for "Def Leppard" never matched and step 5 scored 3/4 on every
# single run — a false negative that looked like a memory failure. Normalise
# both sides before comparing. Only whitespace is folded, so the `\|`
# alternations the callers pass still reach grep as BRE.
normalize_spaces() {
  perl -CSAD -pe 's/[\x{00A0}\x{1680}\x{2000}-\x{200B}\x{202F}\x{205F}\x{2060}\x{3000}\x{FEFF}]/ /g'
}

# --- Helper: check if reply contains expected substring (case-insensitive) ---
assert_contains() {
  local reply="$1"
  local expected="$2"
  local label="${3:-$expected}"

  if printf '%s' "$reply" | normalize_spaces | grep -qi "$(printf '%s' "$expected" | normalize_spaces)"; then
    echo -e "    ${GREEN}✓${RESET} Found: $label"
    return 0
  else
    echo -e "    ${RED}✗${RESET} Missing: $label"
    return 1
  fi
}

# --- Helper: check if reply does NOT contain substring (inverted assertion) ---
assert_not_contains() {
  local reply="$1"
  local unexpected="$2"
  local label="${3:-$unexpected}"

  if printf '%s' "$reply" | normalize_spaces | grep -qi "$(printf '%s' "$unexpected" | normalize_spaces)"; then
    echo -e "    ${RED}✗${RESET} Unexpectedly found: $label"
    return 1
  else
    echo -e "    ${GREEN}✓${RESET} Correctly blocked: $label"
    return 0
  fi
}

# Agent-authored skills land under the *agent's* workspace, not the shared one.
# /home/node/.openclaw/workspace/skills holds the seeded skills (platform,
# quote-builder); anything the main agent creates goes to .../workspace/main/skills.
AGENT_SKILLS_DIR="/home/node/.openclaw/workspace/main/skills"
PROPOSALS_DIR="/home/node/.openclaw/skill-workshop/proposals"

# --- Helper: check if a skill directory exists ---
skill_exists() {
  local skill_name="$1"
  oc_exec test -d "${AGENT_SKILLS_DIR}/$skill_name" &>/dev/null
}

# --- Helper: newest pending proposal id for a skill name ---
# `skill_workshop action=create` does NOT write a skill — it files a PROPOSAL.md
# under ~/.openclaw/skill-workshop/proposals/<name>-<date>-<hash>/ with status
# `pending`. The skill only materialises on an explicit `apply`, which is what
# the demo's "[Click on Skills]" step stands in for. Asserting on the skill
# directory straight after the create prompt therefore always fails, however
# well the model behaved.
latest_proposal_id() {
  local skill_name="$1"
  new_proposal_ids | grep "^${skill_name}-" | head -1
}

# --- Helper: proposal ids filed during this run, newest first ---
new_proposal_ids() {
  local all
  all=$(oc_exec sh -c "ls -1t '${PROPOSALS_DIR}' 2>/dev/null" | tr -d '\r' | grep -v '^$' || true)
  if [[ -n "${PRE_EXISTING_PROPOSALS:-}" ]]; then
    grep -Fxv -f <(printf '%s\n' "$PRE_EXISTING_PROPOSALS") <<< "$all" || true
  else
    printf '%s\n' "$all"
  fi
}

# --- Helper: apply a pending proposal (the "approve" click in the live demo) ---
apply_proposal() {
  local proposal_id="$1"
  oc_exec openclaw skills workshop apply "$proposal_id" --json &>/dev/null
}

# --- Helper: run a test step ---
run_step() {
  local step_num="$1"
  local step_name="$2"
  shift 2

  # Skip if --step filter is set and doesn't match
  if [[ -n "$STEP_FILTER" && "$STEP_FILTER" != "$step_num" ]]; then
    echo -e "${DIM}[SKIP] Step $step_num: $step_name${RESET}"
    SKIP=$((SKIP + 1))
    return 0
  fi

  echo ""
  echo -e "${BOLD}━━━ Step $step_num: $step_name ━━━${RESET}"

  # Run the step's test function. Step functions return non-zero when an
  # assertion fails, and `set -e` would abort the whole run on the first
  # failure — but the point of this script is to report every section, so
  # swallow the status here. PASS/FAIL counters carry the verdict.
  "$@" || true
}

# ══════════════════════════════════════════════════════════════════════
# Test steps (each function runs assertions and updates PASS/FAIL)
# ══════════════════════════════════════════════════════════════════════

step_1_basic_interaction() {
  echo "  Prompt: Hello"
  local json reply
  json=$(send_message "Hello") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if [[ -n "$reply" ]]; then
    echo -e "  ${GREEN}Reply:${RESET} ${reply:0:100}..."
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}No reply received${RESET}"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo ""
  echo "  Prompt: Your name is FantaBot"
  json=$(send_message "Your name is FantaBot") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")
  echo -e "  ${DIM}Reply: ${reply:0:80}...${RESET}"
  PASS=$((PASS + 1))

  echo ""
  echo "  Prompt: My name is Sally Sellers"
  json=$(send_message "My name is Sally Sellers") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")
  echo -e "  ${DIM}Reply: ${reply:0:80}...${RESET}"
  PASS=$((PASS + 1))

  echo ""
  echo "  Prompt: what are Tech Solutions Orders (exercises sales-order MCP)"
  json=$(send_message "what are Tech Solutions Orders") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Full reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Should mention sales/orders data from MCP
  if assert_contains "$reply" "order" "order data"; then
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}Note: sales-order MCP may not have responded${RESET}"
    FAIL=$((FAIL + 1))
  fi

  echo ""
  echo "  Prompt: what are the pod themes in the catalog? (exercises product MCP)"
  json=$(send_message "what are the pod themes in the catalog?") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Full reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Should mention product catalog data
  if assert_contains "$reply" "theme\|product\|catalog" "catalog/product data"; then
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}Note: product MCP may not have responded${RESET}"
    FAIL=$((FAIL + 1))
  fi
}

step_2_skill_friendly_greeter() {
  echo "  Creating friendly-greeter skill..."
  # The trailing sentence about the description is load-bearing, not padding.
  # Skill auto-triggering routes on the `description:` frontmatter line, never on
  # the SKILL.md body — so whatever the model happens to write there decides
  # whether "Greet George" fires the skill at all. Left to itself it writes
  # something vague ("Greets user by name with Aloha message") and the router
  # misses: measured 2/13 across the fleet. Asking for the literal greeting in
  # the description takes it to 12/14, and 15 of 18 runs produce the same
  # byte-identical string. Ask for the intent *and* the literal: demanding only
  # the literal makes the model write the bare line with no "greets a person by
  # name", which routes worse (3/6).
  # Residual miss rate is still ~1 in 7, so the presenter's recovery line stays
  # "Use the friendly-greeter skill. Greet George" — see step 2's retry below.
  local prompt='create a skill called friendly-greeter that when trigger responds with "Aloha <name>, Welcome to FantaCo". replace <name> with the name provided in the triggering prompt. If no name is given ask for one. No extra commentary, only one line output. The skill description should say it greets a person by name with "Aloha <name>, Welcome to FantaCo".'

  local json reply
  json=$(send_message "$prompt" 180) || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Creation reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Wait a moment for the proposal to be written
  sleep 2

  local proposal_id
  proposal_id=$(latest_proposal_id "friendly-greeter")
  if [[ -n "$proposal_id" ]]; then
    echo -e "    ${GREEN}✓${RESET} Proposal filed: ${DIM}${proposal_id}${RESET}"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}✗${RESET} No friendly-greeter proposal was filed"
    FAIL=$((FAIL + 1))
    return 1
  fi

  # Stand in for the presenter clicking through Skills → approve.
  echo "  Applying the proposal (the '[Click on Skills]' step)..."
  apply_proposal "$proposal_id"

  if skill_exists "friendly-greeter"; then
    echo -e "    ${GREEN}✓${RESET} Skill directory created"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}✗${RESET} Skill directory not found after apply"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo ""
  echo "  Testing: Greet George"
  json=$(send_message "Greet George") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Greeting reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  if assert_contains "$reply" "Aloha George" "correct greeting"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    # Distinguish "the skill is wrong" from "the skill is fine but the model did
    # not pick it up off a bare 'Greet George'". Auto-selection depends on the
    # description the model wrote into its own SKILL.md frontmatter, so it is the
    # part most likely to drift between models. Diagnostic only — not scored.
    echo "    Retrying with the skill named explicitly (diagnostic)..."
    json=$(send_message "Use the friendly-greeter skill: Greet George") || json=""
    reply=$(extract_reply "$json")
    if echo "$reply" | grep -qi "Aloha George"; then
      echo -e "    ${YELLOW}!${RESET} Skill works when named, but did not auto-trigger"
    else
      echo -e "    ${RED}✗${RESET} Skill does not produce the greeting even when named"
    fi
  fi

  echo ""
  echo "  Testing: Greet me (should remember Sally)"
  json=$(send_message "Greet me") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Greeting reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Should either greet Sally or ask for name
  if assert_contains "$reply" "Aloha Sally\|name" "greet Sally or ask for name"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

step_3_customer_details() {
  echo "  Prompt: show me the details of Tech Solutions"
  local json reply
  json=$(send_message "show me the details of Tech Solutions") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Full reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Should have customer data from MCP
  if assert_contains "$reply" "Tech Solutions" "customer name"; then
    PASS=$((PASS + 1))
  else
    echo -e "  ${YELLOW}Note: customer MCP may not have responded${RESET}"
    FAIL=$((FAIL + 1))
  fi
}

step_4_skill_customer_notes() {
  echo "  Creating personal customer notes skill..."
  local prompt='create a new workspace skill that manages personal customer notes that uses workspace memory and when creating the notes identifies the customer record, if there is any confusion ask me for clarity. use the customer database and mcp'

  local json reply
  json=$(send_message "$prompt" 180) || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Creation reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Wait for the proposal to be written
  sleep 2

  # The model picks the skill name itself, so match on any pending proposal that
  # is neither of the seeded skills. (The previous check counted
  # `find -maxdepth 1 -type d -newer quote-builder`, which includes the skills
  # directory itself and so reported success even when nothing was created.)
  local proposal_id
  proposal_id=$(new_proposal_ids | grep -v "^friendly-greeter-" | head -1)

  if [[ -n "$proposal_id" ]]; then
    echo -e "    ${GREEN}✓${RESET} Proposal filed: ${DIM}${proposal_id}${RESET}"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}✗${RESET} No notes-skill proposal was filed"
    FAIL=$((FAIL + 1))
    return 1
  fi

  echo "  Applying the proposal (the '[Click on Skills]' step)..."
  apply_proposal "$proposal_id"

  # Proposal ids are <skill-name>-<date>-<hash>; strip the two trailing segments.
  local skill_name="${proposal_id%-*}"
  skill_name="${skill_name%-*}"
  if skill_exists "$skill_name"; then
    echo -e "    ${GREEN}✓${RESET} Skill created: ${skill_name}"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}✗${RESET} Skill directory not found after apply: ${skill_name}"
    FAIL=$((FAIL + 1))
  fi
}

step_5_customer_notes_usage() {
  echo "  Prompt: who are the contacts for Tech Solutions?"
  local json reply
  json=$(send_message "who are the contacts for Tech Solutions?") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo "$reply" | sed 's/^/    /'
  else
    echo -e "  ${DIM}${reply:0:100}...${RESET}"
  fi
  PASS=$((PASS + 1))

  echo ""
  echo "  Building personal notes (David, Bianca, Blake, Dion, Def Leppard)..."

  for note_prompt in \
    "update my personal notes for Tech Solutions CEO David" \
    "his wife's name is Bianca" \
    "they have two children ages 4 and 8, Blake and Dion" \
    "he loves Def Leppard"; do

    json=$(send_message "$note_prompt") || { FAIL=$((FAIL + 1)); return 1; }
    reply=$(extract_reply "$json")
    echo -e "  ${DIM}${reply:0:60}...${RESET}"
    PASS=$((PASS + 1))
  done

  echo ""
  echo "  Prompt: show me the files in the workspace"
  json=$(send_message "show me the files in the workspace") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")
  echo -e "  ${DIM}${reply:0:100}...${RESET}"
  PASS=$((PASS + 1))

  echo ""
  echo "  Prompt: what notes do you have about David of Tech Solutions"
  json=$(send_message "what notes do you have about David of Tech Solutions") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Full notes recall:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  # Assert on specific facts from the notes
  local checks=0
  assert_contains "$reply" "Bianca" "wife's name" && checks=$((checks + 1))
  assert_contains "$reply" "Blake" "child Blake" && checks=$((checks + 1))
  assert_contains "$reply" "Dion" "child Dion" && checks=$((checks + 1))
  assert_contains "$reply" "Def Leppard" "favorite band" && checks=$((checks + 1))

  if [[ $checks -ge 3 ]]; then
    echo -e "    ${GREEN}✓${RESET} Recalled ${checks}/4 key facts"
    PASS=$((PASS + 1))
  else
    echo -e "    ${YELLOW}⚠${RESET} Only recalled ${checks}/4 key facts"
    FAIL=$((FAIL + 1))
  fi
}

step_6_quote_builder() {
  echo "  Prompt: /quote-builder Start a new project NovaSpark Enchanted Forest"
  local json reply
  json=$(send_message "/quote-builder Start a new project NovaSpark Enchanted Forest" 180) || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Quote builder reply:${RESET}"
    echo "$reply" | sed 's/^/    /'
  else
    echo -e "  ${DIM}${reply:0:100}...${RESET}"
  fi

  if assert_contains "$reply" "NovaSpark\|project\|quote" "quote project"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi

  echo ""
  echo "  Prompt: approve"
  json=$(send_message "approve") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")
  echo -e "  ${DIM}${reply:0:100}...${RESET}"
  PASS=$((PASS + 1))

  echo ""
  echo "  Prompt: give me a draft email for that quote so I can send to Priya"
  json=$(send_message "give me a draft email for that quote so I can send to Priya") || { FAIL=$((FAIL + 1)); return 1; }
  reply=$(extract_reply "$json")

  if $VERBOSE; then
    echo -e "  ${CYAN}Email draft:${RESET}"
    echo "$reply" | sed 's/^/    /'
  fi

  if assert_contains "$reply" "Priya\|email\|quote" "email draft"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

step_7_network_isolation() {
  # The verdict has to come from the egress proxy, not from the model's prose.
  # APOD text is all over the training data, so an LLM will happily produce a
  # convincing "Astronomy Picture of the Day" answer from memory even when the
  # network is fully sealed — grading the reply text reports a phantom breach.
  echo "  Checking egress to api.nasa.gov (should be blocked by instance-proxy)..."
  local code
  # Keep the fallback outside the command substitution: curl already prints
  # "000" on a refused connection and then exits non-zero, so `|| echo 000`
  # inside $( ) would concatenate into "000000".
  code=$(oc exec deployment/instance -n "$NAMESPACE" -c gateway -- \
    curl -s -o /dev/null -w '%{http_code}' -m 30 \
    "https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY" 2>/dev/null) || true
  code="${code:-000}"

  # "000" means curl never completed a connection — which is what a blocked
  # egress looks like, and *also* what a broken `oc exec` looks like. Those are
  # opposite outcomes with identical output: during a DNS outage this check
  # cheerfully reported "isolation working" when nothing had run at all. Prove
  # the exec path itself works before reading 000 as proof of anything.
  if ! oc exec deployment/instance -n "$NAMESPACE" -c gateway -- true 2>/dev/null; then
    echo -e "    ${RED}✗${RESET} INCONCLUSIVE: cannot exec into the gateway — isolation not verified"
    FAIL=$((FAIL + 1))
  elif [[ "$code" == "000" ]]; then
    echo -e "    ${GREEN}✓${RESET} Network isolation working (egress refused, HTTP $code)"
    PASS=$((PASS + 1))
  else
    echo -e "    ${RED}✗${RESET} SECURITY ISSUE: api.nasa.gov reachable (HTTP $code)"
    FAIL=$((FAIL + 1))
  fi

  # Demo-fidelity check only: what the presenter will actually see on screen.
  # Not scored — the model may answer from memory, which is a model-behaviour
  # observation rather than an isolation failure.
  echo "  Prompt: give me the NASA APOD (demo-fidelity check, not scored)"
  local json reply
  if json=$(send_message "give me the NASA APOD"); then
    reply=$(extract_reply "$json")
    if echo "$reply" | grep -qi "Astronomy Picture of the Day"; then
      echo -e "    ${YELLOW}⚠${RESET} Model answered from memory rather than reporting the block"
    else
      echo -e "    ${GREEN}✓${RESET} Model reported it could not fetch the APOD"
    fi
    if $VERBOSE; then
      echo -e "  ${CYAN}Reply:${RESET}"
      echo "$reply" | sed 's/^/    /'
    fi
  else
    echo -e "    ${DIM}(agent call failed — isolation verdict above still stands)${RESET}"
  fi
}

# ══════════════════════════════════════════════════════════════════════
# Cleanup mode — remove test-created skills
# ══════════════════════════════════════════════════════════════════════

cleanup_skills() {
  echo -e "${BOLD}Cleanup mode: removing test-created skills${RESET}"
  echo ""

  # Every agent-authored skill lives under the agent workspace; the seeded
  # platform/quote-builder skills live in the shared one and must survive.
  local created
  created=$(oc_exec sh -c "ls -1 '${AGENT_SKILLS_DIR}' 2>/dev/null" | tr -d '\r' | grep -v '^$' || true)
  if [[ -n "$created" ]]; then
    while IFS= read -r skill_name; do
      echo "  Removing skill $skill_name..."
      oc_exec rm -rf "${AGENT_SKILLS_DIR}/${skill_name}" &>/dev/null
      echo -e "    ${GREEN}✓${RESET} Removed"
    done <<< "$created"
  else
    echo -e "    ${DIM}No agent-created skills (already clean)${RESET}"
  fi

  # Proposals accumulate one directory per create attempt, so clear them too —
  # otherwise the next run's latest_proposal_id picks up a stale proposal and
  # reports a pass without the model having done anything.
  local proposals
  proposals=$(oc_exec sh -c "ls -1 '${PROPOSALS_DIR}' 2>/dev/null" | tr -d '\r' | grep -v '^$' || true)
  if [[ -n "$proposals" ]]; then
    while IFS= read -r proposal_id; do
      echo "  Removing proposal $proposal_id..."
      oc_exec rm -rf "${PROPOSALS_DIR}/${proposal_id}" &>/dev/null
    done <<< "$proposals"
    oc_exec sh -c "rm -f /home/node/.openclaw/skill-workshop/proposals.json" &>/dev/null
    echo -e "    ${GREEN}✓${RESET} Proposals cleared"
  fi

  echo ""
  echo -e "${GREEN}Cleanup complete${RESET}"
}

# ══════════════════════════════════════════════════════════════════════
# Main execution
# ══════════════════════════════════════════════════════════════════════

if $CLEANUP_MODE; then
  cleanup_skills
  exit 0
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  OpenClaw Demo Flow Test${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Namespace:  ${CYAN}$NAMESPACE${RESET}"
echo -e "  Session ID: ${DIM}$SESSION_ID${RESET}"
echo -e "  Timeout:    ${AGENT_TIMEOUT}s per LLM call"
echo ""

# Verify namespace exists and pod is running
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
  echo -e "${RED}Error: namespace $NAMESPACE does not exist${RESET}"
  exit 1
fi

POD=$(oc get pods -n "$NAMESPACE" -l app=claw --no-headers 2>/dev/null | grep Running | head -1 | awk '{print $1}')
if [[ -z "$POD" ]]; then
  echo -e "${RED}Error: no running gateway pod in $NAMESPACE${RESET}"
  exit 1
fi

# Check model configuration
echo -e "${DIM}Pre-flight: checking gateway configuration...${RESET}"
MODEL_CHECK=$(oc_exec node -e "
  const c = JSON.parse(require('fs').readFileSync('/home/node/.openclaw/openclaw.json'));
  console.log(c.agents?.defaults?.model?.primary || 'not-set');
" 2>/dev/null || echo "error")

if [[ "$MODEL_CHECK" == "error" || "$MODEL_CHECK" == "not-set" ]]; then
  echo -e "${RED}Error: cannot read gateway model configuration${RESET}"
  exit 1
fi

echo -e "  Model:      ${CYAN}$MODEL_CHECK${RESET}"

# Test model connectivity
# `|| true` is load-bearing: under set -e a failing command substitution aborts
# the script on the spot. When the endpoint is rate-limited the ping blocks past
# `timeout 30` and exits 124, so the whole test died here silently — no message,
# no summary — and the fleet runner could only report it as a 33s "TIMEOUT".
# The inconclusive branch below is the intended handling for a probe that does
# not answer; let it be reached.
echo -e "${DIM}Testing model connectivity...${RESET}"
MODEL_TEST=$(timeout 30 oc exec deployment/instance -n "$NAMESPACE" -c gateway -- \
  node /app/dist/index.js --no-color agent \
  --session-id "preflight-$$" \
  --message "ping" \
  --json 2>&1) || true

if echo "$MODEL_TEST" | grep -q "404 status code.*model_not_found"; then
  echo -e "${RED}✗ Model not available at LLM provider (404)${RESET}"
  echo ""
  echo "The configured model ($MODEL_CHECK) is not available."
  echo "This usually means:"
  echo "  1. The LLM API key was recently rotated to a different model"
  echo "  2. The model name in .env needs to be updated"
  echo "  3. The LiteLLM/OpenRouter endpoint doesn't have this model"
  echo ""
  echo "Cannot proceed with demo flow test until model is working."
  exit 1
elif echo "$MODEL_TEST" | grep -q "FallbackSummaryError"; then
  echo -e "${RED}✗ All models failed (including fallbacks)${RESET}"
  echo ""
  echo "Error output:"
  echo "$MODEL_TEST" | grep -A 3 "FallbackSummaryError"
  echo ""
  echo "Cannot proceed with demo flow test until model is working."
  exit 1
elif echo "$MODEL_TEST" | grep -q '"incomplete_result"'; then
  echo -e "${YELLOW}⚠ Model responding but generating malformed output${RESET}"
  echo "  Model: $MODEL_CHECK"
  echo "  Error: incomplete_result (response format issue)"
  echo ""
  echo "The model is reachable but responses may be empty or partial."
  echo "Demo tests will likely FAIL due to missing content."
  if $FORCE; then
    echo "  Continuing anyway (--force)..."
  else
    echo ""
    echo "Use --force to run tests anyway, or fix the model configuration first."
    exit 1
  fi
elif echo "$MODEL_TEST" | grep -q '"status": "ok"'; then
  echo -e "${GREEN}✓ Model responding${RESET}"
else
  echo -e "${YELLOW}⚠ Model test inconclusive${RESET}"
  echo "Continuing anyway, but tests may fail..."
fi

echo ""

# Proposals are never garbage-collected, so a re-run without --cleanup would see
# last run's pending proposals and score the skill steps as passing without the
# model having produced anything. Snapshot what is already there and ignore it.
PRE_EXISTING_PROPOSALS=$(oc_exec sh -c "ls -1 '${PROPOSALS_DIR}' 2>/dev/null" | tr -d '\r' | grep -v '^$' || true)

# Run test steps
START_TIME=$(date +%s)

run_step 1 "Introduction & basic interaction" step_1_basic_interaction
run_step 2 "Skill creation — friendly greeter" step_2_skill_friendly_greeter
run_step 3 "Customer details" step_3_customer_details
run_step 4 "Skill creation — personal customer notes" step_4_skill_customer_notes
run_step 5 "Customer notes in action" step_5_customer_notes_usage
run_step 6 "Quote builder" step_6_quote_builder
run_step 7 "Network isolation" step_7_network_isolation

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Summary
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Test Summary${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Passed:  ${GREEN}$PASS${RESET}"
echo -e "  Failed:  ${RED}$FAIL${RESET}"
if [[ $SKIP -gt 0 ]]; then
  echo -e "  Skipped: ${DIM}$SKIP${RESET} (--step filter)"
fi
echo -e "  Time:    ${ELAPSED}s"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed${RESET}"
  echo ""
  exit 0
else
  echo -e "${RED}✗ $FAIL test(s) failed${RESET}"
  echo ""
  echo "To clean up test artifacts:"
  echo "  $0 --namespace $(echo "$NAMESPACE" | sed "s/${NAMESPACE_PREFIX}//") --cleanup"
  echo ""
  exit 1
fi
