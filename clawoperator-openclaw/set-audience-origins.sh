#!/usr/bin/env bash
# set-audience-origins.sh — Make the Control UI accept the broker's audience host
#
# An attendee who arrives through the session broker lands on the namespace's
# `audience` route (claw-<code>-<hash>.apps...), not on the direct
# instance-agentic-userN route. If the gateway does not list that host in
# gateway.controlUi.allowedOrigins the Control UI refuses the connection with:
#
#   Browser origin not allowed
#   The Gateway rejected this page's origin before accepting the Control UI
#   connection. Add this browser origin to gateway.controlUi.allowedOrigins.
#
# post-restart-repatch.sh already writes those origins into openclaw.json, but
# that fix does not survive: the operator re-seeds
# gateway.controlUi.allowedOrigins from its own template on **every pod start**,
# resetting it to the instance route alone. Model, diagnostics and plugin config
# are left alone — origins specifically are operator-owned. Measured on hlm6k:
# 40 of 50 namespaces had been silently reset this way.
#
# Restarting the gateway process in place does not dodge it either. `kill 1`
# inside the gateway container causes the pod to be recreated, so the init
# containers re-run and re-seed exactly as `oc rollout restart` would.
#
# The durable fix is to stop fighting the reconcile and feed the operator the
# value instead. The Claw CRD exposes spec.config.raw — "inline openclaw.json
# configuration ... merged into operator.json before the enrichment pipeline
# runs" — so origins set there are re-applied on every pod start rather than
# overwritten. Verified: they survive `oc rollout restart`.
#
# Usage:
#   ./set-audience-origins.sh 1 50           # patch CRs, restart what needs it
#   ./set-audience-origins.sh --check 1 50   # report only, change nothing
#   ./set-audience-origins.sh --no-restart 1 50   # patch only; applies on next start
#
# A namespace whose running config is already correct is patched (so it stays
# correct) but not restarted.

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
BATCH=${BATCH:-10}

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

CHECK_ONLY=false
DO_RESTART=true
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|-n)   CHECK_ONLY=true; shift ;;
    --no-restart) DO_RESTART=false; shift ;;
    -h|--help)    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo -e "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    *)  POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 [--check] [--no-restart] <start> [end]" >&2
  exit 1
fi
START="$1"; END="${2:-$1}"

oc whoami &>/dev/null || { echo -e "${RED}ERROR: not logged in to OpenShift.${RESET}" >&2; exit 1; }

echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Control UI allowed origins${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  Namespaces: ${NAMESPACE_PREFIX}${START}..${END}"
$CHECK_ONLY && echo -e "  Mode:       ${YELLOW}--check (read-only)${RESET}"
echo ""

# Read what the *running* gateway currently accepts.
running_origins() {
  oc exec deployment/instance -n "$1" -c gateway -- node -e '
    const c = JSON.parse(require("fs").readFileSync("/home/node/.openclaw/openclaw.json"));
    console.log(((((c.gateway||{}).controlUi)||{}).allowedOrigins||[]).join(","));
  ' 2>/dev/null || true
}

NEED_RESTART=()
N_OK=0; N_PATCHED=0; N_SKIPPED=0

for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  oc get deployment instance -n "$NS" &>/dev/null || { N_SKIPPED=$((N_SKIPPED+1)); continue; }

  AUD=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$AUD" ]]; then
    echo -e "  ${YELLOW}⚠ ${NS}: no audience route — skipping${RESET}"
    N_SKIPPED=$((N_SKIPPED+1)); continue
  fi
  INST=$(oc get route instance -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)

  CUR=$(running_origins "$NS")
  if [[ ",${CUR}," == *",https://${AUD},"* ]]; then
    LIVE_OK=true
  else
    LIVE_OK=false
  fi

  if $CHECK_ONLY; then
    if $LIVE_OK; then
      N_OK=$((N_OK+1))
    else
      echo -e "  ${CYAN}${NS}${RESET}: running config rejects ${DIM}https://${AUD}${RESET}"
      N_PATCHED=$((N_PATCHED+1))
    fi
    continue
  fi

  # Build the origin list. The instance route is included so the direct URL
  # keeps working for presenters and for demo-flow-test.sh.
  ORIGINS="\"https://${AUD}\""
  [[ -n "$INST" ]] && ORIGINS="\"https://${INST}\", ${ORIGINS}"

  if ! oc patch claw instance -n "$NS" --type merge \
       -p "{\"spec\":{\"config\":{\"raw\":{\"gateway\":{\"controlUi\":{\"allowedOrigins\":[${ORIGINS}]}}}}}}" \
       >/dev/null 2>&1; then
    echo -e "  ${RED}✗ ${NS}: CR patch failed${RESET}"
    continue
  fi
  N_PATCHED=$((N_PATCHED+1))

  if $LIVE_OK; then
    N_OK=$((N_OK+1))
  else
    NEED_RESTART+=("$NS")
  fi
done

if $CHECK_ONLY; then
  echo ""
  echo -e "  ${GREEN}${N_OK}${RESET} already accept the audience host, ${YELLOW}${N_PATCHED}${RESET} do not, ${N_SKIPPED} skipped"
  exit 0
fi

echo -e "  ${GREEN}${N_PATCHED}${RESET} CR(s) patched; ${#NEED_RESTART[@]} need a restart to pick it up"

if ! $DO_RESTART || (( ${#NEED_RESTART[@]} == 0 )); then
  (( ${#NEED_RESTART[@]} > 0 )) && \
    echo -e "  ${DIM}--no-restart: origins apply on the next pod start${RESET}"
else
  echo ""
  # Restart in batches. Fifty simultaneous gateway starts on a 7-node cluster
  # stampede the scheduler and the image cache, and a gateway that is slow to
  # start looks identical to one that is broken.
  echo -e "  ${DIM}restarting in batches of ${BATCH}...${RESET}"
  n=0
  for NS in "${NEED_RESTART[@]}"; do
    oc rollout restart deployment/instance -n "$NS" >/dev/null 2>&1 || true
    n=$((n+1))
    if (( n % BATCH == 0 )); then sleep 60; fi
  done
  sleep 90
fi

echo ""
echo -e "${BOLD}Verification:${RESET}"
BAD=()
for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"
  oc get deployment instance -n "$NS" &>/dev/null || continue
  AUD=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  [[ -z "$AUD" ]] && continue
  CUR=$(running_origins "$NS")
  [[ ",${CUR}," == *",https://${AUD},"* ]] || BAD+=("$NS")
done
if (( ${#BAD[@]} == 0 )); then
  echo -e "  ${GREEN}✓ every gateway in range accepts its audience host${RESET}"
else
  echo -e "  ${YELLOW}⚠ still rejecting (${#BAD[@]}): ${BAD[*]}${RESET}"
  echo -e "  ${DIM}re-run; a gateway still starting reports the pre-restart config${RESET}"
fi
