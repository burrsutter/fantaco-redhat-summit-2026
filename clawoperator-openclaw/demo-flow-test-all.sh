#!/usr/bin/env bash
# demo-flow-test-all.sh — Run demo-flow-test.sh across every user namespace
#
# Wraps ./demo-flow-test.sh and fans it out over the agentic-userN namespaces
# with a concurrency cap, one log file per namespace, live per-namespace
# progress, and a per-section failure breakdown at the end.
#
# All 22 namespaces share a single MaaS/LiteLLM endpoint, so the cap matters:
# running 22 concurrent demo flows queues ~22 in-flight completions against one
# upstream and inflates every per-call latency until the 300s AGENT_TIMEOUT in
# demo-flow-test.sh starts firing. The default of 6 keeps the endpoint busy
# without turning a model slowdown into a fleet-wide false negative.
#
# Usage:
#   ./demo-flow-test-all.sh                          # all 22, 6 at a time
#   ./demo-flow-test-all.sh --concurrency 4          # gentler on the endpoint
#   ./demo-flow-test-all.sh --from 1 --to 8          # a contiguous range
#   ./demo-flow-test-all.sh --only "3 7 12"          # an explicit list
#   ./demo-flow-test-all.sh --only "21 22" --step 1  # smoke test one section
#   ./demo-flow-test-all.sh --cleanup                # clear test artifacts
#   ./demo-flow-test-all.sh --timeout 1800           # raise the per-ns cap
#
# Logs:
#   .state/<cluster-guid>/demo-flow-runs/<timestamp>/agentic-userN.log
#   (.state/ is gitignored; if it is not, logs fall back to /tmp)
#
# Exit code: 0 only when every selected namespace finished with zero failures.

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/demo-flow-test.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Defaults ---
DEFAULT_FROM=1
DEFAULT_TO=22
CONCURRENCY=6
NS_TIMEOUT=1200        # seconds per namespace for a full run
CLEANUP_TIMEOUT=300    # cleanup is a handful of oc execs; do not wait 20 minutes
FROM=""
TO=""
ONLY=""
CLEANUP_MODE=false
declare -a PASSTHRU=()  # flags handed straight to demo-flow-test.sh

usage() {
  # Print the header comment block, stopping at the first non-comment line.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# --- Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --to) TO="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    --timeout) NS_TIMEOUT="$2"; shift 2 ;;
    --cleanup) CLEANUP_MODE=true; shift ;;
    --step) PASSTHRU+=(--step "$2"); shift 2 ;;
    --verbose) PASSTHRU+=(--verbose); shift ;;
    --force) PASSTHRU+=(--force); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo "Try --help" >&2; exit 1 ;;
  esac
done

if [[ ! -x "$TEST_SCRIPT" ]]; then
  echo "Error: $TEST_SCRIPT not found or not executable" >&2
  exit 1
fi

if ! [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || (( CONCURRENCY < 1 )); then
  echo "Error: --concurrency must be a positive integer" >&2
  exit 1
fi
if ! [[ "$NS_TIMEOUT" =~ ^[0-9]+$ ]] || (( NS_TIMEOUT < 1 )); then
  echo "Error: --timeout must be a positive integer (seconds)" >&2
  exit 1
fi

# ── Namespace selection ───────────────────────────────────────────
declare -a NUMS=()
if [[ -n "$ONLY" ]]; then
  if [[ -n "$FROM" || -n "$TO" ]]; then
    echo "Error: --only cannot be combined with --from/--to" >&2
    exit 1
  fi
  # Accept "3 7 12" and "3,7,12" alike.
  read -r -a NUMS <<< "${ONLY//,/ }"
else
  FROM="${FROM:-$DEFAULT_FROM}"
  TO="${TO:-$DEFAULT_TO}"
  for ((n = FROM; n <= TO; n++)); do
    NUMS+=("$n")
  done
fi

for n in "${NUMS[@]}"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 )); then
    echo "Error: invalid namespace number '$n'" >&2
    exit 1
  fi
done
if (( ${#NUMS[@]} == 0 )); then
  echo "Error: no namespaces selected" >&2
  exit 1
fi

# Never spawn more workers than there is work.
if (( CONCURRENCY > ${#NUMS[@]} )); then
  CONCURRENCY=${#NUMS[@]}
fi

# ── Run directory ─────────────────────────────────────────────────
# Same GUID convention as post-restart-repatch.sh: the sandbox id embedded in
# the API server hostname (api.ocp.<guid>.sandboxNNN.opentlc.com).
CLUSTER_GUID=$(oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|') || true
CLUSTER_GUID=$(printf '%s' "$CLUSTER_GUID" | tr -cd 'a-zA-Z0-9-')
if [[ -z "$CLUSTER_GUID" ]]; then
  echo "Error: could not extract cluster GUID from 'oc whoami --show-server'" >&2
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_ROOT="${SCRIPT_DIR}/.state/${CLUSTER_GUID}/demo-flow-runs"
# Logs contain full LLM replies, so they must never be committable. .state/ is
# gitignored in this repo; if that ever changes, fall back to /tmp rather than
# quietly staging transcripts.
if git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
  if ! git -C "$SCRIPT_DIR" check-ignore -q "$RUN_ROOT" 2>/dev/null; then
    RUN_ROOT="/tmp/demo-flow-runs/${CLUSTER_GUID}"
    echo -e "${YELLOW}⚠ .state/ is not gitignored — logging to ${RUN_ROOT} instead${RESET}" >&2
  fi
fi
RUN_DIR="${RUN_ROOT}/${TIMESTAMP}"
mkdir -p "$RUN_DIR"

# ── Helpers ───────────────────────────────────────────────────────

# demo-flow-test.sh colours its output; every parse below runs on the stripped
# text so that "  Passed:  \e[0;32m22\e[0m" reads as "  Passed:  22".
strip_ansi() {
  sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\r$//'
}

# Worker: full demo flow for one namespace. Writes the transcript to its own log
# and a parsed verdict to <ns>.result. Never exits non-zero — a dead namespace
# must not take the batch down with it.
run_namespace() {
  local num="$1"
  local ns="${NAMESPACE_PREFIX}${num}"
  local log="${RUN_DIR}/${ns}.log"
  local result="${RUN_DIR}/${ns}.result"
  local start end elapsed rc=0 status reason="" have pass fail

  start=$(date +%s)
  # Without --foreground, timeout puts the child in its own process group and
  # signals the whole group, so a wedged `oc exec` dies with the test script.
  timeout -k 30 "$NS_TIMEOUT" "$TEST_SCRIPT" --namespace "$num" "${PASSTHRU[@]}" \
    > "$log" 2>&1 || rc=$?
  end=$(date +%s)
  elapsed=$((end - start))

  # Pull the summary block. awk (not grep) so a missing block is an empty value
  # rather than a pipefail that would abort the worker.
  read -r have pass fail <<< "$(strip_ansi < "$log" | awk '
    /^[[:space:]]*Passed:[[:space:]]/ { p = $2; seen = 1 }
    /^[[:space:]]*Failed:[[:space:]]/ { q = $2 }
    END { print seen + 0, p + 0, q + 0 }
  ')"

  if (( rc == 124 || rc == 137 )); then
    status="TIMEOUT"
    reason="exceeded ${NS_TIMEOUT}s"
  elif (( have == 0 )); then
    # No summary block: pre-flight bailed (missing namespace, no pod, dead
    # model) or the script died. Surface the most useful line from the log.
    status="ERROR"
    reason=$(strip_ansi < "$log" | awk '
      NF { last = $0 }
      /Error:|Cannot proceed|✗/ { hit = $0 }
      END { s = (hit != "" ? hit : last); sub(/^[[:space:]]+/, "", s); print substr(s, 1, 64) }
    ')
    [[ -n "$reason" ]] || reason="no output (exit $rc)"
  elif (( fail == 0 && rc == 0 )); then
    status="PASS"
  else
    status="FAIL"
  fi

  {
    echo "STATUS=${status}"
    echo "PASS=${pass}"
    echo "FAIL=${fail}"
    echo "ELAPSED=${elapsed}"
    echo "RC=${rc}"
    echo "REASON=${reason}"
  } > "$result"
}

# Worker: --cleanup for one namespace. demo-flow-test.sh --cleanup swallows its
# own oc failures and still prints "Cleanup complete", so check the pod first —
# otherwise a scaled-down namespace reports a clean bill of health.
cleanup_namespace() {
  local num="$1"
  local ns="${NAMESPACE_PREFIX}${num}"
  local log="${RUN_DIR}/cleanup-${ns}.log"
  local result="${RUN_DIR}/${ns}.result"
  local start end elapsed rc=0 status reason="" removed=0

  start=$(date +%s)
  if ! oc get namespace "$ns" &>/dev/null; then
    status="ERROR"; reason="namespace does not exist"
    echo "namespace $ns does not exist" > "$log"
  elif ! oc get pods -n "$ns" -l app=claw --no-headers 2>/dev/null | grep -q Running; then
    status="ERROR"; reason="no running gateway pod"
    echo "no running gateway pod in $ns" > "$log"
  else
    timeout -k 30 "$CLEANUP_TIMEOUT" "$TEST_SCRIPT" --namespace "$num" --cleanup \
      > "$log" 2>&1 || rc=$?
    # demo-flow-test.sh's oc_exec folds stderr into stdout, so when the agent
    # skills directory does not exist the "skill list" is literally
    # "command terminated with exit code 2" and cleanup reports a phantom
    # removal. Do not count those. (Bug is in demo-flow-test.sh, not here.)
    removed=$(strip_ansi < "$log" | awk '
      /^  Removing skill / && !/command terminated/ { n++ }
      END { print n + 0 }
    ')
    if (( rc == 124 || rc == 137 )); then
      status="TIMEOUT"; reason="exceeded ${CLEANUP_TIMEOUT}s"
    elif (( rc != 0 )); then
      status="ERROR"; reason="cleanup exited $rc"
    else
      status="PASS"; reason="${removed} skill(s) removed"
    fi
  fi
  end=$(date +%s)
  elapsed=$((end - start))

  {
    echo "STATUS=${status}"
    echo "PASS=0"
    echo "FAIL=0"
    echo "ELAPSED=${elapsed}"
    echo "RC=${rc}"
    echo "REASON=${reason}"
  } > "$result"
}

# Read a worker's verdict back into the R_* variables.
load_result() {
  local ns="$1"
  local file="${RUN_DIR}/${ns}.result"
  R_STATUS="ERROR"; R_PASS=0; R_FAIL=0; R_ELAPSED=0; R_REASON="no result file"
  [[ -f "$file" ]] || return 0
  local key value
  # RC= is written to the file for post-mortem debugging but is not surfaced in
  # the tables — STATUS/REASON already carry the verdict.
  while IFS='=' read -r key value; do
    case "$key" in
      STATUS) R_STATUS="$value" ;;
      PASS) R_PASS="$value" ;;
      FAIL) R_FAIL="$value" ;;
      ELAPSED) R_ELAPSED="$value" ;;
      REASON) R_REASON="$value" ;;
    esac
  done < "$file"
}

# One live progress line per namespace, printed by the parent only, so worker
# output never interleaves on the terminal.
print_progress() {
  local ns="$1"
  load_result "$ns"
  local colour detail
  colour=$(status_colour "$R_STATUS")
  case "$R_STATUS" in
    PASS|FAIL)
      if $CLEANUP_MODE; then
        detail="$R_REASON"
      else
        detail=$(printf '%3s passed %3s failed' "$R_PASS" "$R_FAIL")
      fi
      ;;
    *) detail="$R_REASON" ;;
  esac
  # Truncate so a long pre-flight error cannot shove the time column sideways.
  printf "  %-16s ${colour}%-7s${RESET} %-34s %5ss\n" \
    "$ns" "$R_STATUS" "${detail:0:34}" "$R_ELAPSED"
}

# One status -> colour mapping, shared by the live lines and the final table.
status_colour() {
  case "$1" in
    PASS) printf '%s' "$GREEN" ;;
    FAIL|TIMEOUT) printf '%s' "$RED" ;;
    *) printf '%s' "$YELLOW" ;;
  esac
}

# ── Scheduler ─────────────────────────────────────────────────────
# bash 5.1+ can tell us *which* job finished (`wait -n -p`), which is what makes
# completion-ordered progress lines possible. Older bash falls back to reaping
# the oldest job, which still throttles correctly but reports in launch order.
declare -a PENDING=()
declare -A PID_NS=()
HAVE_WAIT_P=false
if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
  HAVE_WAIT_P=true
fi

# Ctrl-C on a 20-minute fleet run must not leave 6 demo flows chewing on the
# model endpoint. Each worker's direct child is the `timeout` process, and
# terminating that makes timeout signal the whole test-script process group.
# shellcheck disable=SC2329  # invoked via trap
on_interrupt() {
  trap - INT TERM
  echo "" >&2
  echo -e "${YELLOW}Interrupted — stopping ${#PENDING[@]} in-flight namespace(s)...${RESET}" >&2
  local p
  for p in "${PENDING[@]}"; do
    pkill -TERM -P "$p" 2>/dev/null || true
    kill -TERM "$p" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo -e "  Partial logs: ${DIM}${RUN_DIR}${RESET}" >&2
  exit 130
}
trap on_interrupt INT TERM

reap_one() {
  local pid="" i
  # The worker's exit status is deliberately discarded: the verdict lives in the
  # .result file, and letting a non-zero `wait` propagate under `set -e` would
  # abort the batch the first time a namespace failed.
  if $HAVE_WAIT_P; then
    wait -n -p pid || true
    if [[ -z "$pid" ]]; then
      # bash could not attribute the exit (or nothing was running) — fall back.
      pid="${PENDING[0]}"
      wait "$pid" 2>/dev/null || true
    fi
  else
    pid="${PENDING[0]}"
    wait "$pid" 2>/dev/null || true
  fi

  # Drop the reaped pid from the pending list.
  for i in "${!PENDING[@]}"; do
    if [[ "${PENDING[$i]}" == "$pid" ]]; then
      unset 'PENDING[i]'
      break
    fi
  done
  PENDING=("${PENDING[@]}")

  if [[ -n "${PID_NS[$pid]:-}" ]]; then
    print_progress "${PID_NS[$pid]}"
    unset 'PID_NS[$pid]'
  fi
}

# ── Banner ────────────────────────────────────────────────────────
MODE_LABEL="demo flow"
if $CLEANUP_MODE; then
  MODE_LABEL="cleanup"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  OpenClaw Demo Flow — Fleet Run (${MODE_LABEL})${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Cluster:      ${CYAN}${CLUSTER_GUID}${RESET}"
# Spell the list out when it is short; --only can be non-contiguous, so a
# "first … last" range would misdescribe e.g. --only "3 7 12".
if (( ${#NUMS[@]} <= 8 )); then
  NS_LABEL="${NUMS[*]/#/${NAMESPACE_PREFIX}}"
else
  NS_LABEL="${NAMESPACE_PREFIX}${NUMS[0]} … ${NAMESPACE_PREFIX}${NUMS[-1]}"
fi
echo -e "  Namespaces:   ${CYAN}${#NUMS[@]}${RESET} (${NS_LABEL})"
echo -e "  Concurrency:  ${CYAN}${CONCURRENCY}${RESET}"
if ! $CLEANUP_MODE; then
  echo -e "  Timeout:      ${NS_TIMEOUT}s per namespace"
  if (( ${#PASSTHRU[@]} > 0 )); then
    echo -e "  Passthrough:  ${DIM}${PASSTHRU[*]}${RESET}"
  fi
fi
echo -e "  Logs:         ${DIM}${RUN_DIR}${RESET}"
echo ""
echo -e "${BOLD}  Progress (completion order)${RESET}"
echo ""

# ── Fan out ───────────────────────────────────────────────────────
BATCH_START=$(date +%s)

for num in "${NUMS[@]}"; do
  # Throttle before launching so we never exceed the cap.
  while (( ${#PENDING[@]} >= CONCURRENCY )); do
    reap_one
  done

  if $CLEANUP_MODE; then
    cleanup_namespace "$num" &
  else
    run_namespace "$num" &
  fi
  PENDING+=($!)
  PID_NS[$!]="${NAMESPACE_PREFIX}${num}"
done

while (( ${#PENDING[@]} > 0 )); do
  reap_one
done

BATCH_END=$(date +%s)
BATCH_ELAPSED=$((BATCH_END - BATCH_START))

# ── Aggregate ─────────────────────────────────────────────────────
TOTAL_PASS=0
TOTAL_FAIL=0
NS_PASS=0
NS_FAIL=0
NS_ERROR=0
NS_TIMEDOUT=0
NS_TIME_SUM=0

declare -A SECTION_NAME=()     # step number -> section title
declare -A SECTION_NS=()       # step number -> namespaces with ≥1 ✗
declare -A ASSERT_COUNT=()     # "step|label" -> namespaces hitting it

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Results${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
printf "  %-16s %-8s %7s %7s %7s  %s\n" "NAMESPACE" "STATUS" "PASSED" "FAILED" "TIME" "NOTE"

for num in "${NUMS[@]}"; do
  ns="${NAMESPACE_PREFIX}${num}"
  load_result "$ns"
  NS_TIME_SUM=$((NS_TIME_SUM + R_ELAPSED))

  colour=$(status_colour "$R_STATUS")
  case "$R_STATUS" in
    PASS)    NS_PASS=$((NS_PASS + 1)) ;;
    FAIL)    NS_FAIL=$((NS_FAIL + 1)) ;;
    TIMEOUT) NS_TIMEDOUT=$((NS_TIMEDOUT + 1)) ;;
    *)       NS_ERROR=$((NS_ERROR + 1)) ;;
  esac
  TOTAL_PASS=$((TOTAL_PASS + R_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + R_FAIL))

  if ! $CLEANUP_MODE && [[ "$R_STATUS" == "PASS" || "$R_STATUS" == "FAIL" ]]; then
    printf "  %-16s ${colour}%-8s${RESET} %7s %7s %6ss  %s\n" \
      "$ns" "$R_STATUS" "$R_PASS" "$R_FAIL" "$R_ELAPSED" "$R_REASON"
  else
    printf "  %-16s ${colour}%-8s${RESET} %7s %7s %6ss  %s\n" \
      "$ns" "$R_STATUS" "-" "-" "$R_ELAPSED" "$R_REASON"
  fi

  # Per-section breakdown, from the transcript rather than the counters:
  # demo-flow-test.sh only reports fleet-wide PASS/FAIL totals, so the section
  # attribution has to come from the "━━━ Step N: ... ━━━" headers and the ✗
  # assertion lines underneath them.
  log="${RUN_DIR}/${ns}.log"
  [[ -f "$log" ]] || continue
  while IFS=$'\t' read -r kind field1 field2; do
    case "$kind" in
      NAME) SECTION_NAME[$field1]="$field2" ;;
      SECT) SECTION_NS[$field1]=$(( ${SECTION_NS[$field1]:-0} + 1 )) ;;
      ASRT) ASSERT_COUNT["${field1}|${field2}"]=$(( ${ASSERT_COUNT["${field1}|${field2}"]:-0} + 1 )) ;;
    esac
  done < <(strip_ansi < "$log" | awk '
    # Section header: ━━━ Step 3: Customer details ━━━
    /^━+ Step [0-9]+:/ {
      step = $3; sub(/:$/, "", step)
      title = $0
      sub(/^━+ Step [0-9]+:[[:space:]]*/, "", title)
      sub(/[[:space:]]*━+$/, "", title)
      cur = step
      name[cur] = title
      next
    }
    # The Test Summary banner closes the last section. Without this the final
    # "✗ N test(s) failed" line would be charged to step 7 in every namespace
    # that failed anything at all.
    /^═+$/ { cur = ""; next }
    # Failed assertion inside the current section.
    cur != "" && /✗/ {
      label = $0
      sub(/^[[:space:]]*✗[[:space:]]*/, "", label)
      sub(/[[:space:]]+$/, "", label)
      if (label == "") next
      fails[cur]++
      # One vote per namespace per distinct label, not per occurrence.
      if (!((cur SUBSEP label) in seenlabel)) {
        seenlabel[cur SUBSEP label] = 1
        labels[++nl] = cur "\t" label
      }
    }
    END {
      for (s in name) print "NAME\t" s "\t" name[s]
      for (s in fails) print "SECT\t" s "\t" fails[s]
      for (i = 1; i <= nl; i++) print "ASRT\t" labels[i]
    }
  ')
done

echo ""
echo -e "  Namespaces:  ${#NUMS[@]} total — ${GREEN}${NS_PASS} pass${RESET}, ${RED}${NS_FAIL} fail${RESET}, ${RED}${NS_TIMEDOUT} timeout${RESET}, ${YELLOW}${NS_ERROR} error${RESET}"
if ! $CLEANUP_MODE; then
  echo -e "  Assertions:  ${GREEN}${TOTAL_PASS} passed${RESET}, ${RED}${TOTAL_FAIL} failed${RESET}"
fi
echo -e "  Wall clock:  ${BATCH_ELAPSED}s  ${DIM}(serial equivalent ${NS_TIME_SUM}s)${RESET}"

# ── Per-section failure breakdown ─────────────────────────────────
if ! $CLEANUP_MODE && (( ${#SECTION_NS[@]} > 0 )); then
  echo ""
  echo -e "${BOLD}  Section failures${RESET} ${DIM}(namespaces with at least one ✗)${RESET}"
  echo ""
  # Count first, title last: section titles contain em dashes, and printf pads
  # by bytes, so a trailing variable-width column keeps the table straight.
  while IFS=$'\t' read -r step count; do
    printf "    Step %-3s %3s/%-3s  %s\n" \
      "$step" "$count" "${#NUMS[@]}" "${SECTION_NAME[$step]:-(unknown section)}"
  done < <(
    for step in "${!SECTION_NS[@]}"; do
      printf '%s\t%s\n' "$step" "${SECTION_NS[$step]}"
    done | sort -n
  )

  if (( ${#ASSERT_COUNT[@]} > 0 )); then
    echo ""
    echo -e "${BOLD}  Failing assertions${RESET} ${DIM}(most widespread first)${RESET}"
    echo ""
    while IFS=$'\t' read -r count step label; do
      printf "    %3s/%-3s  Step %-3s %s\n" "$count" "${#NUMS[@]}" "$step" "$label"
    done < <(
      for key in "${!ASSERT_COUNT[@]}"; do
        printf '%s\t%s\t%s\n' "${ASSERT_COUNT[$key]}" "${key%%|*}" "${key#*|}"
      done | sort -t$'\t' -k1,1nr -k2,2n -k3,3
    )
    echo ""
    echo -e "  ${DIM}Counts are namespaces, not occurrences. A few ✗ lines in${RESET}"
    echo -e "  ${DIM}demo-flow-test.sh are diagnostic only (e.g. the step 2 'even when${RESET}"
    echo -e "  ${DIM}named' retry), so they appear here without moving Passed/Failed.${RESET}"
  fi
fi

echo ""
echo -e "  Logs: ${DIM}${RUN_DIR}${RESET}"
echo ""

if (( NS_FAIL == 0 && NS_ERROR == 0 && NS_TIMEDOUT == 0 )); then
  echo -e "${GREEN}✓ All ${#NUMS[@]} namespace(s) passed${RESET}"
  echo ""
  exit 0
else
  echo -e "${RED}✗ ${NS_FAIL} failed, ${NS_TIMEDOUT} timed out, ${NS_ERROR} errored${RESET}"
  if ! $CLEANUP_MODE; then
    echo ""
    echo "To clear test artifacts before a re-run:"
    echo "  $0 --cleanup${ONLY:+ --only \"$ONLY\"}"
  fi
  echo ""
  exit 1
fi
