#!/usr/bin/env bash
#
# maas-mint-seat-keys.sh — mint one distinct MaaS API key per seat, write them
# to a CSV, and hand that CSV to set-user-api-keys.sh.
#
# This is the step that had no script at all. For Darmstadt the 100 keys in
# .state/rosa-tztnl/maas-seat-keys.csv were produced by hand; nothing in the
# repo could regenerate them.
#
# WHAT "PER-SEAT" ACTUALLY BUYS YOU
# ---------------------------------
# Every key is minted by ONE identity (whoever runs this script), so all seats
# share one MaaSSubscription and therefore ONE fleet-wide token budget. The
# keys are distinct *strings*, not distinct quotas. The win is blast radius:
# students hold `get secrets` in their own namespace, so with a single shared
# token any attendee could read everyone else's. Per-seat keys cut that to one.
#
# Per-seat QUOTA would need one OpenShift identity per seat, each in its own
# group, with a MaaSSubscription per group. The docs are explicit that group
# membership is captured at key-creation time. Out of scope here.
#
# Usage:
#   ./maas-mint-seat-keys.sh --smoke-test       # mint 1 key, call the model, revoke it
#   ./maas-mint-seat-keys.sh 1 100              # mint into a CSV (does NOT apply)
#   ./maas-mint-seat-keys.sh --apply 1 100      # mint, then run set-user-api-keys.sh
#   ./maas-mint-seat-keys.sh --remint 1 100     # discard existing CSV rows and re-mint
#   ./maas-mint-seat-keys.sh --verify 1 100     # compare CSV against what is deployed
#   ./maas-mint-seat-keys.sh --revoke           # revoke ALL active agentic-user* keys
#   ./maas-mint-seat-keys.sh --as-seat 1 100    # mint each key AS that seat's own user
#
# --as-seat is what makes the MaaS Usage dashboard break traffic down per seat.
# The `user` dimension in authorized_hits_total / authorized_calls_total records
# WHO MINTED THE KEY, not who called it. Minted the normal way every key belongs
# to whoever ran this script, so all 100 seats collapse into one row reading
# user="cluster-admin". Measured on rosa-wv5l4 2026-11-18, then proved the fix:
# a key minted as agentic-user1 reports user="agentic-user1".
#
# It requires per-seat OpenShift identities, which do NOT exist by default —
# run ./create-seat-users.sh first. Credentials are read from
# .state/<guid>/seat-users.csv. On ROSA HCP that script cannot create the
# identity provider itself; see HANDOFF.md.
#
# Reads from ../.env:
#   MAAS_MODEL                  default qwen3-235b-a22b
#   MAAS_KEY_EXPIRATION_DAYS    default 90 (the tenant max; /v1/api-keys/config reports it)
#
# The CSV holds live credentials. It is written to
# .state/<cluster-guid>/maas-seat-keys.csv, which is gitignored, chmod 600, and
# which set-user-api-keys.sh refuses to read unless `git check-ignore` covers it.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
MAAS_MODEL="${MAAS_MODEL:-qwen3-235b-a22b}"
MAAS_KEY_EXPIRATION_DAYS="${MAAS_KEY_EXPIRATION_DAYS:-90}"

MODE=mint; APPLY=0; REMINT=0; AS_SEAT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --smoke-test) MODE=smoke; shift ;;
    --verify)     MODE=verify; shift ;;
    --revoke)     MODE=revoke; shift ;;
    --apply)      APPLY=1; shift ;;
    --remint)     REMINT=1; shift ;;
    --as-seat)    AS_SEAT=1; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
START="${1:-1}"; END="${2:-$START}"

oc whoami >/dev/null 2>&1 || { bad "not logged in to a cluster"; exit 1; }
GUID=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null | cut -d. -f3)
GW_HOST=$(oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null)
[ -z "$GW_HOST" ] && { bad "maas-default-gateway has no hostname — run ./maas-bootstrap.sh"; exit 1; }
MAAS="https://${GW_HOST}"
STATE_DIR="${SCRIPT_DIR}/.state/${GUID}"
CSV="${CSV:-${STATE_DIR}/maas-seat-keys.csv}"
mkdir -p "$STATE_DIR"

bold "MaaS key minting"
info "gateway : $MAAS"
info "model   : $MAAS_MODEL"
if [ "$AS_SEAT" = 1 ]; then
  info "identity: PER SEAT (--as-seat) — each key is owned by its own user,"
  info "          which is what makes the Usage dashboard break down per seat"
else
  info "identity: $(oc whoami)  (owns every key minted below;"
  info "          the Usage dashboard will show ONE user — use --as-seat to split)"
fi
info "csv     : $CSV"

# ------------------------------------------------------------------ mint one
# Returns the plaintext key on stdout. The key is shown ONCE at creation and
# cannot be retrieved later, so the caller must persist it immediately.
# Log in as a seat and echo its token, WITHOUT disturbing the admin session:
# a throwaway KUBECONFIG keeps the caller's context untouched. Returns empty on
# failure so the caller can fail loudly rather than silently minting as admin.
SEAT_USERS_CSV="${SEAT_USERS_CSV:-}"
seat_token() {
  local user="$1" pass kc
  [ -z "$SEAT_USERS_CSV" ] && SEAT_USERS_CSV="${STATE_DIR}/seat-users.csv"
  [ -f "$SEAT_USERS_CSV" ] || return 1
  pass=$(awk -F, -v u="$user" '$1==u {print $2; exit}' "$SEAT_USERS_CSV")
  [ -z "$pass" ] && return 1
  kc=$(mktemp)
  if KUBECONFIG="$kc" oc login --server="$(oc whoami --show-server)" \
       -u "$user" -p "$pass" >/dev/null 2>&1; then
    KUBECONFIG="$kc" oc whoami -t 2>/dev/null
    rm -f "$kc"; return 0
  fi
  rm -f "$kc"; return 1
}

# $2, when given, is the bearer token to mint with. Defaults to the caller's.
mint_key() {
  local name="$1" tok body resp
  tok="${2:-$(oc whoami -t)}"
  body=$(printf '{"name":"%s","description":"FantaCo demo seat key","expiration":"%sd"}' \
           "$name" "$MAAS_KEY_EXPIRATION_DAYS")
  resp=$(curl -sk -m 45 -X POST "${MAAS}/v1/api-keys" \
           -H "Authorization: Bearer ${tok}" \
           -H 'Content-Type: application/json' \
           -d "$body" 2>/dev/null)
  printf '%s' "$resp" | python3 -I -c "
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw)
except Exception:
    sys.stderr.write('unparseable response: '+raw[:300]+'\n'); sys.exit(1)
# the field name has moved between RHOAI builds; accept the known spellings
for f in ('api_key','apiKey','key','token','secret'):
    v=d.get(f)
    if isinstance(v,str) and v.startswith('sk-'):
        print(v); sys.exit(0)
sys.stderr.write('no sk- key in response: '+json.dumps(d)[:300]+'\n'); sys.exit(1)
"
}

# List ACTIVE keys whose name matches a prefix, as "id<TAB>name".
#
# Two things about /v1/api-keys/search that will waste your afternoon:
#   - the envelope is {"object":"list","data":[...]} — not items/keys/api_keys;
#   - it hard-caps at 50 rows and IGNORES every paging parameter
#     (limit/page_size/pageSize/per_page/size/page/offset all return page 1).
# So the only way to walk the whole set is: revoke a batch, search again.
# Revoked keys stay in the listing forever, hence the status filter.
search_active() {
  local prefix="$1" tok; tok=$(oc whoami -t)
  curl -sk -m 30 -X POST "${MAAS}/v1/api-keys/search" \
       -H "Authorization: Bearer ${tok}" -H 'Content-Type: application/json' \
       -d '{}' 2>/dev/null \
  | python3 -I -c "
import json,sys
pre=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for it in d.get('data',[]):
    if it.get('status')!='active': continue
    n=it.get('name','')
    if pre and not n.startswith(pre): continue
    if it.get('id'): print(it['id']+'\t'+n)
" "$prefix" 2>/dev/null
}

revoke_id() {
  local id="$1" tok; tok=$(oc whoami -t)
  [ "$(curl -sk -m 25 -o /dev/null -w '%{http_code}' -X DELETE \
        "${MAAS}/v1/api-keys/${id}" -H "Authorization: Bearer ${tok}")" = 200 ]
}

# Revoke every ACTIVE key whose name starts with $1. Loops because search is
# capped at 50 and unpageable; stops when a pass revokes nothing. Sets
# REVOKED_COUNT rather than echoing it, so progress can go to the terminal.
REVOKED_COUNT=0
# revoke_prefix <prefix> [range_start range_end]
#
# RANGE SCOPING IS NOT OPTIONAL. Without it this revokes EVERY key matching the
# prefix regardless of the seats you asked for. On 2026-11-18
# `--remint 1 2` revoked 49 live keys (seats 52-100, whichever the 50-row
# search returned first) and left those seats answering HTTP 403 with no
# warning. Always pass the range when the caller gave one.
revoke_prefix() {
  local prefix="$1" rs="${2:-}" re="${3:-}" pass
  REVOKED_COUNT=0
  while :; do
    pass=0
    while IFS=$'\t' read -r id name; do
      [ -z "$id" ] && continue
      if [ -n "$rs" ]; then
        # name is "<prefix><n>"; skip anything outside the requested range.
        local n="${name#"$prefix"}"
        case "$n" in
          ''|*[!0-9]*) continue ;;
        esac
        [ "$n" -lt "$rs" ] && continue
        [ "$n" -gt "$re" ] && continue
      fi
      if revoke_id "$id"; then
        pass=$((pass+1)); REVOKED_COUNT=$((REVOKED_COUNT+1))
        printf '  revoked %-26s (%d)\r' "$name" "$REVOKED_COUNT"
      fi
    done < <(search_active "$prefix")
    [ "$pass" -eq 0 ] && break
  done
  [ "$REVOKED_COUNT" -gt 0 ] && echo
  return 0
}

# ------------------------------------------------------------------ smoke
if [ "$MODE" = smoke ]; then
  bold "Smoke test — mint, infer, revoke"
  NAME="smoke-$(date +%s)"
  KEY=$(mint_key "$NAME") || { bad "mint failed"; exit 1; }
  ok "minted a key (${#KEY} chars, prefix ${KEY:0:7}…)"

  CODE=$(curl -sk -m 90 -o /tmp/maas-smoke.json -w '%{http_code}' \
    -X POST "${MAAS}/v1/chat/completions" \
    -H "Authorization: Bearer ${KEY}" -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MAAS_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ready\"}],\"max_tokens\":16}")

  if [ "$CODE" = 200 ]; then
    ok "inference OK (HTTP 200)"
    info "$(head -c 300 /tmp/maas-smoke.json)"
  else
    bad "inference FAILED (HTTP $CODE)"
    info "$(head -c 400 /tmp/maas-smoke.json)"
    grep -q "credentials not found" /tmp/maas-smoke.json 2>/dev/null && {
      warn "This is the label trap."
      info "oc label secret qwen-upstream-maas inference.llm-d.ai/ipp-managed=true -n models-as-a-service"
      info "or just re-run: ./maas-publish-model.sh"
    }
  fi
  revoke_prefix "$NAME"
  [ "$REVOKED_COUNT" -gt 0 ] && ok "revoked the smoke-test key" \
    || warn "could not auto-revoke $NAME — revoke it in the dashboard"
  rm -f /tmp/maas-smoke.json
  [ "$CODE" = 200 ] || exit 1
  exit 0
fi

# ------------------------------------------------------------------ revoke
if [ "$MODE" = revoke ]; then
  bold "Revoking ALL active keys named ${NAMESPACE_PREFIX}*"
  warn "every seat will lose model access until keys are re-minted and applied"
  revoke_prefix "$NAMESPACE_PREFIX"
  ok "revoked $REVOKED_COUNT keys"
  exit 0
fi

# ------------------------------------------------------------------ verify
if [ "$MODE" = verify ]; then
  bold "Verify CSV against deployed secrets ($START..$END)"
  [ -f "$CSV" ] || { bad "no CSV at $CSV"; exit 1; }
  miss=0; diff=0; match=0
  for i in $(seq "$START" "$END"); do
    ns="${NAMESPACE_PREFIX}${i}"
    want=$(awk -F, -v n="$ns" -v b="$i" '$1==n||$1==b{print $2}' "$CSV" | head -1)
    have=$(oc get secret litellm-api-key -n "$ns" -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null)
    if   [ -z "$want" ]; then miss=$((miss+1))
    elif [ "$want" = "$have" ]; then match=$((match+1))
    else diff=$((diff+1)); fi
  done
  ok "match=$match  differ=$diff  missing-from-csv=$miss"
  [ "$diff" = 0 ] && [ "$miss" = 0 ] || exit 1
  exit 0
fi

# ------------------------------------------------------------------ mint all
bold "Minting keys for ${NAMESPACE_PREFIX}${START}..${NAMESPACE_PREFIX}${END}"

declare -a EXISTING_NS=()
if [ -f "$CSV" ] && [ "$REMINT" = 0 ]; then
  while IFS=, read -r ns _; do
    [ -n "$ns" ] && [ "$ns" != "namespace" ] && EXISTING_NS+=("$ns")
  done < "$CSV"
  [ "${#EXISTING_NS[@]}" -gt 0 ] && info "CSV already has ${#EXISTING_NS[@]} rows; those seats are skipped (use --remint to replace)"
fi

# Reinstalling onto a cluster that already has keys would otherwise leave the
# old ones active forever — MaaS never expires them early and the dashboard
# listing keeps every revoked key, so they pile up install after install.
if [ "$REMINT" = 1 ]; then
  bold "Revoking previous keys for ${NAMESPACE_PREFIX}${START}..${NAMESPACE_PREFIX}${END} before re-minting"
  # Scoped to the requested range. Unscoped, this once revoked 49 seats the
  # caller never mentioned — see the comment on revoke_prefix.
  revoke_prefix "$NAMESPACE_PREFIX" "$START" "$END"
  ok "revoked $REVOKED_COUNT stale keys"
fi

TMP="${CSV}.tmp.$$"
if [ -f "$CSV" ] && [ "$REMINT" = 0 ]; then cp "$CSV" "$TMP"; else echo "namespace,api_key" > "$TMP"; fi
chmod 600 "$TMP"

minted=0; skipped=0; failed=0
for i in $(seq "$START" "$END"); do
  ns="${NAMESPACE_PREFIX}${i}"
  if printf '%s\n' "${EXISTING_NS[@]:-}" | grep -qx "$ns"; then
    skipped=$((skipped+1)); continue
  fi
  seat_tok=""
  if [ "$AS_SEAT" = 1 ]; then
    # Fail loudly: minting as admin here would silently give back a key whose
    # `user` label is cluster-admin, which is the exact bug --as-seat exists
    # to fix, and nothing downstream would reveal it.
    if ! seat_tok=$(seat_token "$ns"); then
      failed=$((failed+1)); bad "could not log in as $ns — not minting as admin"; continue
    fi
  fi
  if key=$(mint_key "${ns}" "$seat_tok"); then
    printf '%s,%s\n' "$ns" "$key" >> "$TMP"
    minted=$((minted+1))
    printf '  [%3d/%3d] %-18s minted\r' "$((minted+skipped))" "$((END-START+1))" "$ns"
  else
    failed=$((failed+1)); bad "mint failed for $ns"
  fi
done
echo

if [ "$failed" -gt 0 ]; then
  bad "$failed mints failed — NOT replacing $CSV"
  info "partial results kept at $TMP for inspection"
  exit 1
fi

mv "$TMP" "$CSV"; chmod 600 "$CSV"
ok "minted=$minted skipped=$skipped  →  $CSV"

# Count by hand rather than trusting exit codes — several steps in this repo
# report success while having done nothing.
rows=$(grep -vc '^namespace,' "$CSV")
uniq=$(cut -d, -f2 "$CSV" | grep -c '^sk-')
ok "rows=$rows  distinct sk- keys=$(cut -d, -f2 "$CSV" | grep '^sk-' | sort -u | wc -l | tr -d ' ') (of $uniq)"

if [ "$APPLY" = 1 ]; then
  bold "Applying via set-user-api-keys.sh"
  "${SCRIPT_DIR}/set-user-api-keys.sh" --file "$CSV" "$START" "$END"
else
  echo
  echo "  Not applied. To apply:"
  echo "    ./set-user-api-keys.sh --file $CSV $START $END"
  echo "  It validates every token against the MaaS endpoint before writing anything."
fi
