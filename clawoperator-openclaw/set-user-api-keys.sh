#!/usr/bin/env bash
# set-user-api-keys.sh — Give each agentic-user namespace its own MaaS API token
#
# The gateway never holds a model credential: models.providers.openai.apiKey is a
# placeholder and the egress proxy (instance-proxy) injects the real bearer on
# the way out. That bearer comes from exactly one place per namespace —
#
#   Secret litellm-api-key (key: api-key)
#     └─ Claw CR spec.credentials[name=litellm].secretRef
#          └─ operator reconciles → Deployment/instance-proxy env CRED_LITELLM
#               (as a secretKeyRef, never a literal)
#
# so a per-user token is just a different value in each namespace's Secret plus a
# proxy restart. The gateway is never touched: no rollout, no session loss, no
# openclaw.json repatch.
#
# Why bother: students hold `get secrets` in their own namespace, so with one
# shared token any attendee can read the token all the other attendees are using.
# Per-user tokens cut that blast radius to one.
#
# Usage:
#   ./set-user-api-keys.sh --file keys.csv            # apply from a CSV
#   ./set-user-api-keys.sh --file keys.csv --dry-run  # validate only, change nothing
#   ./set-user-api-keys.sh --verify 1 50              # re-check what is deployed
#   ./set-user-api-keys.sh --file keys.csv 23 50      # restrict to a range
#
# CSV format — one row per namespace, `namespace,token`. The namespace may be
# written as a bare number. Blank lines and `#` comments are ignored:
#
#   1,sk-aaaaaaaaaaaaaaaaaaaaaa
#   2,sk-bbbbbbbbbbbbbbbbbbbbbb
#   agentic-user3,sk-cccccccccccccccccccccc
#
# The CSV holds live credentials. Keep it out of the repo — the default location
# (.state/<cluster-guid>/user-api-keys.csv) is gitignored, and the script refuses
# to read a file that `git check-ignore` does not cover.
#
# Every token is validated against the MaaS endpoint BEFORE anything is applied:
# a 50-row hand-assembled list is overwhelmingly likely to contain a typo, and a
# bad token surfaces as a dead namespace mid-demo rather than at provisioning
# time. Nothing is written unless every row passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

SECRET_NAME="litellm-api-key"
SECRET_KEY="api-key"

# ── Argument parsing ──────────────────────────────────────────────────
KEYS_FILE=""
DRY_RUN=false
VERIFY_ONLY=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)    SITE_NAME="$2"; shift 2 ;;
    --file|-f) KEYS_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --verify)  VERIFY_ONLY=true; shift ;;
    -h|--help)
      sed -n '2,42p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo -e "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    *)  POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/sites/resolve-site.sh"

if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERROR: not logged in to OpenShift. Run 'oc login' first.${RESET}" >&2
  exit 1
fi

CLUSTER_GUID=$(oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
[[ -z "$CLUSTER_GUID" ]] && CLUSTER_GUID="default"

# ── Load .env for the MaaS base URL ───────────────────────────────────
for candidate in "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/../.env"; do
  if [[ -f "$candidate" ]]; then
    # shellcheck disable=SC1090
    source "$candidate"
    break
  fi
done
BASE_URL="${LLM_API_BASE_URL:-}"
if [[ -z "$BASE_URL" ]]; then
  echo -e "${RED}ERROR: LLM_API_BASE_URL not set in .env — cannot validate tokens.${RESET}" >&2
  exit 1
fi
REQUIRED_MODEL="${LLM_MODEL_NAME:-}"
EMBED_MODEL="${LLM_EMBEDDING_MODEL:-}"

# ── Namespace range ───────────────────────────────────────────────────
RANGE_START=""
RANGE_END=""
if [[ $# -eq 1 ]]; then
  RANGE_START="$1"; RANGE_END="$1"
elif [[ $# -eq 2 ]]; then
  RANGE_START="$1"; RANGE_END="$2"
elif [[ $# -gt 2 ]]; then
  echo -e "${RED}ERROR: expected at most <start> <end>.${RESET}" >&2
  exit 1
fi

in_range() {
  local n="$1"
  [[ -z "$RANGE_START" ]] && return 0
  (( n >= RANGE_START && n <= RANGE_END ))
}

mask() {
  # Show enough to tell two tokens apart in a log, never enough to use one.
  local k="$1"
  if (( ${#k} <= 10 )); then printf '****'; else printf '%s…%s' "${k:0:6}" "${k: -3}"; fi
}

# ─────────────────────────────────────────────────────────────────────
# Verify mode — report what is actually deployed, change nothing
# ─────────────────────────────────────────────────────────────────────
if $VERIFY_ONLY; then
  echo -e "${BOLD}=== Deployed per-namespace tokens (${CLUSTER_GUID}) ===${RESET}"
  echo ""
  declare -A SEEN=()
  TOTAL=0; SHARED=0
  for i in $(seq "${RANGE_START:-1}" "${RANGE_END:-50}"); do
    NS="${NAMESPACE_PREFIX}${i}"
    oc get ns "$NS" &>/dev/null || continue
    TOTAL=$((TOTAL + 1))
    VAL=$(oc get secret "$SECRET_NAME" -n "$NS" -o jsonpath="{.data.${SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -z "$VAL" ]]; then
      printf "  %-16s ${RED}%s${RESET}\n" "$NS" "no ${SECRET_NAME} secret"
      continue
    fi
    # Fingerprint rather than the token, so duplicates are visible in the output
    # without the output itself becoming a credential dump.
    FP=$(printf '%s' "$VAL" | sha256sum | cut -c1-8)
    if [[ -n "${SEEN[$FP]:-}" ]]; then
      printf "  %-16s %-16s ${YELLOW}shared with %s${RESET}\n" "$NS" "$(mask "$VAL")" "${SEEN[$FP]}"
      SHARED=$((SHARED + 1))
    else
      SEEN[$FP]="$NS"
      printf "  %-16s %-16s ${DIM}fp:%s${RESET}\n" "$NS" "$(mask "$VAL")" "$FP"
    fi
  done
  echo ""
  echo -e "  ${BOLD}${TOTAL}${RESET} namespaces · ${BOLD}${#SEEN[@]}${RESET} distinct tokens · ${BOLD}${SHARED}${RESET} sharing"
  if (( SHARED > 0 )); then
    echo -e "  ${DIM}Sharing is fine if intentional — each shared group hits one rate limit.${RESET}"
  fi
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────
# Apply mode
# ─────────────────────────────────────────────────────────────────────
DEFAULT_KEYS_FILE="${SCRIPT_DIR}/.state/${CLUSTER_GUID}/user-api-keys.csv"
[[ -z "$KEYS_FILE" ]] && KEYS_FILE="$DEFAULT_KEYS_FILE"

if [[ ! -f "$KEYS_FILE" ]]; then
  echo -e "${RED}ERROR: keys file not found: ${KEYS_FILE}${RESET}" >&2
  echo "" >&2
  echo "Create it as <namespace>,<token> per line, e.g.:" >&2
  echo "  mkdir -p $(dirname "$DEFAULT_KEYS_FILE")" >&2
  echo "  \$EDITOR $DEFAULT_KEYS_FILE" >&2
  exit 1
fi

# The file holds live credentials. Refuse to read one git would happily stage.
if git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
  if git -C "$SCRIPT_DIR" ls-files --error-unmatch "$KEYS_FILE" &>/dev/null; then
    echo -e "${RED}ERROR: ${KEYS_FILE} is TRACKED BY GIT. It holds live API tokens.${RESET}" >&2
    echo "  Run: git rm --cached '$KEYS_FILE' and add it to .gitignore." >&2
    exit 1
  fi
  if ! git -C "$SCRIPT_DIR" check-ignore -q "$KEYS_FILE" 2>/dev/null; then
    echo -e "${RED}ERROR: ${KEYS_FILE} is not gitignored. It holds live API tokens.${RESET}" >&2
    echo "  Put it under .state/ (already ignored) or add it to .gitignore first." >&2
    exit 1
  fi
fi

echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Per-user API tokens${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Cluster:   ${CYAN}${CLUSTER_GUID}${RESET}"
echo -e "  Keys file: ${DIM}${KEYS_FILE}${RESET}"
echo -e "  Endpoint:  ${DIM}${BASE_URL}${RESET}"
$DRY_RUN && echo -e "  Mode:      ${YELLOW}DRY RUN — nothing will be applied${RESET}"
echo ""

# ── Parse ─────────────────────────────────────────────────────────────
NAMESPACES=()
TOKENS=()
PARSE_ERRORS=0
LINE_NO=0

while IFS= read -r line || [[ -n "$line" ]]; do
  LINE_NO=$((LINE_NO + 1))
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  ns_raw="${line%%,*}"
  tok="${line#*,}"
  ns_raw=$(echo "$ns_raw" | xargs)
  tok=$(echo "$tok" | xargs)

  if [[ -z "$ns_raw" || -z "$tok" || "$ns_raw" == "$line" ]]; then
    echo -e "  ${RED}✗${RESET} line ${LINE_NO}: expected '<namespace>,<token>'"
    PARSE_ERRORS=$((PARSE_ERRORS + 1))
    continue
  fi

  if [[ "$ns_raw" =~ ^[0-9]+$ ]]; then
    num="$ns_raw"; ns="${NAMESPACE_PREFIX}${ns_raw}"
  else
    ns="$ns_raw"; num="${ns_raw#"$NAMESPACE_PREFIX"}"
    [[ "$num" =~ ^[0-9]+$ ]] || num=0
  fi

  in_range "$num" || continue
  NAMESPACES+=("$ns")
  TOKENS+=("$tok")
done < "$KEYS_FILE"

if (( PARSE_ERRORS > 0 )); then
  echo ""
  echo -e "${RED}Aborting: ${PARSE_ERRORS} malformed row(s).${RESET}"
  exit 1
fi

if (( ${#NAMESPACES[@]} == 0 )); then
  echo -e "${RED}ERROR: no rows matched.${RESET}" >&2
  exit 1
fi

# Duplicate namespaces mean the later row silently wins — never what was meant.
mapfile -t DUPES < <(printf '%s\n' "${NAMESPACES[@]}" | sort | uniq -d)
if (( ${#DUPES[@]} > 0 )); then
  echo -e "${RED}ERROR: duplicate namespace rows:${RESET}"
  printf '    %s\n' "${DUPES[@]}"
  exit 1
fi

echo -e "${BOLD}--- Validating ${#NAMESPACES[@]} token(s) against MaaS ---${RESET}"

# Distinct tokens only: a group-shared token should be probed once, not ten times.
declare -A TOKEN_STATUS=()
declare -A TOKEN_NOTE=()
VALID=0
INVALID=0

for idx in "${!NAMESPACES[@]}"; do
  tok="${TOKENS[$idx]}"
  [[ -n "${TOKEN_STATUS[$tok]:-}" ]] && continue

  BODY=$(curl -sS --max-time 30 -H "Authorization: Bearer ${tok}" "${BASE_URL}/models" 2>/dev/null || true)
  if [[ -z "$BODY" ]]; then
    TOKEN_STATUS[$tok]="fail"; TOKEN_NOTE[$tok]="no response from endpoint"
  elif ! echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('data'),list) else 1)" 2>/dev/null; then
    MSG=$(echo "$BODY" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); e=d.get('error')
    print((e.get('message') if isinstance(e,dict) else e) or 'rejected')
except Exception:
    print('non-JSON response')
" 2>/dev/null | head -c 120)
    TOKEN_STATUS[$tok]="fail"; TOKEN_NOTE[$tok]="${MSG}"
  else
    MODELS=$(echo "$BODY" | python3 -c "
import json,sys
print(' '.join(m.get('id','') for m in json.load(sys.stdin)['data']))
" 2>/dev/null)
    MISSING=""
    [[ -n "$REQUIRED_MODEL" && " $MODELS " != *" $REQUIRED_MODEL "* ]] && MISSING="$REQUIRED_MODEL"
    [[ -n "$EMBED_MODEL" && " $MODELS " != *" $EMBED_MODEL "* ]] && MISSING="${MISSING:+$MISSING, }$EMBED_MODEL"
    if [[ -n "$MISSING" ]]; then
      # Scoped to the wrong models is as fatal as a bad token, and far easier to
      # miss: the token authenticates, then every completion 404s mid-demo.
      TOKEN_STATUS[$tok]="fail"; TOKEN_NOTE[$tok]="not scoped to: ${MISSING}"
    else
      TOKEN_STATUS[$tok]="ok"; TOKEN_NOTE[$tok]="$(echo "$MODELS" | wc -w) models"
    fi
  fi
done

for idx in "${!NAMESPACES[@]}"; do
  ns="${NAMESPACES[$idx]}"; tok="${TOKENS[$idx]}"
  if [[ "${TOKEN_STATUS[$tok]}" == "ok" ]]; then
    printf "  ${GREEN}✓${RESET} %-16s %-14s ${DIM}%s${RESET}\n" "$ns" "$(mask "$tok")" "${TOKEN_NOTE[$tok]}"
    VALID=$((VALID + 1))
  else
    printf "  ${RED}✗${RESET} %-16s %-14s ${RED}%s${RESET}\n" "$ns" "$(mask "$tok")" "${TOKEN_NOTE[$tok]}"
    INVALID=$((INVALID + 1))
  fi
done

echo ""
if (( INVALID > 0 )); then
  echo -e "${RED}Aborting: ${INVALID} of ${#NAMESPACES[@]} token(s) failed validation. Nothing was applied.${RESET}"
  echo -e "${DIM}All-or-nothing on purpose — a half-applied fleet is worse than an unchanged one.${RESET}"
  exit 1
fi
echo -e "  ${GREEN}All ${VALID} token(s) valid.${RESET}"
echo ""

# ── Missing namespaces ────────────────────────────────────────────────
MISSING_NS=()
for ns in "${NAMESPACES[@]}"; do
  oc get ns "$ns" &>/dev/null || MISSING_NS+=("$ns")
done
if (( ${#MISSING_NS[@]} > 0 )); then
  echo -e "${RED}ERROR: these namespaces do not exist:${RESET}"
  printf '    %s\n' "${MISSING_NS[@]}"
  exit 1
fi

if $DRY_RUN; then
  echo -e "${YELLOW}Dry run — would update ${#NAMESPACES[@]} secret(s) and restart their proxies.${RESET}"
  exit 0
fi

# ── Apply ─────────────────────────────────────────────────────────────
echo -e "${BOLD}--- Writing secrets ---${RESET}"
APPLIED=0
FAILED=0
CHANGED_NS=()

for idx in "${!NAMESPACES[@]}"; do
  ns="${NAMESPACES[$idx]}"; tok="${TOKENS[$idx]}"

  CURRENT=$(oc get secret "$SECRET_NAME" -n "$ns" -o jsonpath="{.data.${SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ "$CURRENT" == "$tok" ]]; then
    printf "  ${DIM}·${RESET} %-16s ${DIM}unchanged${RESET}\n" "$ns"
    APPLIED=$((APPLIED + 1))
    continue
  fi

  if oc create secret generic "$SECRET_NAME" \
       --from-literal="${SECRET_KEY}=${tok}" \
       -n "$ns" --dry-run=client -o yaml | oc apply -f - &>/dev/null; then
    printf "  ${GREEN}✓${RESET} %-16s %s\n" "$ns" "$(mask "$tok")"
    APPLIED=$((APPLIED + 1))
    CHANGED_NS+=("$ns")
  else
    printf "  ${RED}✗${RESET} %-16s ${RED}secret write failed${RESET}\n" "$ns"
    FAILED=$((FAILED + 1))
  fi
done

echo ""

# ── Restart proxies ───────────────────────────────────────────────────
# Only the namespaces whose token actually changed: CRED_LITELLM is injected
# from the Secret at pod start, so a running proxy keeps serving the old token
# until it is replaced — but restarting an unchanged one is pure churn.
if (( ${#CHANGED_NS[@]} == 0 )); then
  echo -e "${DIM}No token changed — no proxy restarts needed.${RESET}"
else
  echo -e "${BOLD}--- Restarting ${#CHANGED_NS[@]} proxy pod(s) ---${RESET}"
  echo -e "${DIM}Gateways are left alone: no session loss, no route change.${RESET}"
  for ns in "${CHANGED_NS[@]}"; do
    oc rollout restart deployment/instance-proxy -n "$ns" &>/dev/null || true
  done
  ROLLOUT_FAILED=0
  for ns in "${CHANGED_NS[@]}"; do
    if oc rollout status deployment/instance-proxy -n "$ns" --timeout=120s &>/dev/null; then
      printf "  ${GREEN}✓${RESET} %-16s proxy ready\n" "$ns"
    else
      printf "  ${YELLOW}⚠${RESET} %-16s proxy rollout did not settle in 120s\n" "$ns"
      ROLLOUT_FAILED=$((ROLLOUT_FAILED + 1))
    fi
  done
  echo ""
fi

# ── Summary ───────────────────────────────────────────────────────────
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  Secrets:  ${GREEN}${APPLIED} applied${RESET}, ${RED}${FAILED} failed${RESET}"
echo -e "  Restarts: ${#CHANGED_NS[@]} proxy pod(s)"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${DIM}Verify what is deployed:  ./set-user-api-keys.sh --verify 1 50${RESET}"
echo -e "${DIM}End-to-end model check:   ./demo-preflight.sh --site ${SITE_NAME:-ocp} 1 50${RESET}"

if (( FAILED > 0 || ${ROLLOUT_FAILED:-0} > 0 )); then
  exit 1
fi
