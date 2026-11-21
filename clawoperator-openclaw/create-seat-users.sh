#!/usr/bin/env bash
# create-seat-users.sh — give every seat a real OpenShift identity.
#
# WHY THIS EXISTS. The demo historically had NO per-seat identities at all.
# Attendees reach their claw through the audience Route and the broker, never
# `oc login`, so a stock cluster has two users (cluster-admin and the backplane
# one) and an EMPTY `oauth/cluster` spec. Measured on rosa-wv5l4 2026-11-18.
#
# That had two consequences nobody noticed until the observability work:
#
#  1. The MaaS Usage dashboard cannot break traffic down per seat. The `user`
#     dimension records WHO MINTED THE KEY, not who called. With every key
#     minted by cluster-admin, all 100 seats collapse into one row reading
#     `user="cluster-admin"`. Verified by driving traffic from seats 1, 2 and 3
#     and reading authorized_hits_total.
#  2. Per-seat token quota is impossible for the same reason — one identity
#     means one subscription means one fleet-wide budget.
#
#  `0-admin-setup.sh` ALREADY binds the `claw-user` ClusterRole to a user named
#  `agentic-user<N>` in each namespace. Those bindings have always pointed at
#  identities that did not exist. This script creates them.
#
# It also labels each namespace `opendatahub.io/dashboard=true` so the seat is
# listed as an AI project in the RHOAI dashboard.
#
# Usage:
#   ./create-seat-users.sh                      # seats 1..100, random password each
#   ./create-seat-users.sh 1 50                 # seats 1..50
#   ./create-seat-users.sh --password 'Pw!'     # ONE shared password for all seats
#   ./create-seat-users.sh --check              # report, change nothing
#
# --password trades isolation for convenience: every attendee can log in as
# every other seat. That is usually the right call for a workshop where the
# password goes on a slide, and the wrong call for anything that outlives the
# event. Tear the cluster down or rotate afterwards.
#
# Credentials are written to .state/<cluster-guid>/seat-users.csv (mode 600,
# gitignored) and are NEVER printed. Treat that file like the broker key.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IDP_NAME="seat-users"
SECRET_NAME="htpass-seat-users"
RANGE_START=1
RANGE_END=100
MODE=apply
SHARED_PASSWORD=""   # empty => generate a distinct random password per seat

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)    MODE=check; shift ;;
    --password) SHARED_PASSWORD="${2:?--password needs a value}"; shift 2 ;;
    -*)         echo "Unknown flag: $1" >&2; exit 1 ;;
    *)          RANGE_START="$1"; RANGE_END="${2:?need an end seat}"; shift 2 ;;
  esac
done

for c in oc python3 htpasswd; do
  command -v "$c" >/dev/null || { echo "Missing required command: $c" >&2; exit 1; }
done
oc whoami >/dev/null

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; RST=$'\033[0m'
ok()   { echo "  ${GREEN}✓${RST} $*"; }
bad()  { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YEL}!${RST} $*"; }

GUID=$(oc whoami --show-server | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
STATE_DIR="$SCRIPT_DIR/.state/$GUID"
CRED_CSV="$STATE_DIR/seat-users.csv"

# Refuse to write credentials anywhere git can see them.
if ! git -C "$SCRIPT_DIR" check-ignore -q "$STATE_DIR" 2>/dev/null; then
  echo "REFUSING: $STATE_DIR is not gitignored; credentials would be committable." >&2
  exit 1
fi

report() {
  echo "── seat identities ─────────────────────────────────"
  local idp topo
  topo=$(oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}' 2>/dev/null)
  idp=$(oc get oauth cluster -o jsonpath="{.spec.identityProviders[?(@.name=='$IDP_NAME')].name}" 2>/dev/null)
  if [[ "$topo" == "External" ]]; then
    # On HCP the IdP lives on the HostedCluster and is NOT visible here, so an
    # empty oauth/cluster proves nothing either way. Do not report it as a
    # failure — check from the management side instead.
    warn "ROSA HCP: IdP state is not visible in-cluster. Verify with:"
    echo "        rosa list idp --cluster=$GUID"
    [[ -f "$STATE_DIR/seat-users.htpasswd" ]] \
      && ok "htpasswd file ready for 'rosa create idp'" \
      || warn "no htpasswd file yet — run this script without --check"
  else
    [[ -n "$idp" ]] && ok "identity provider '$IDP_NAME' configured" \
                    || bad "identity provider '$IDP_NAME' NOT configured"
    oc get secret "$SECRET_NAME" -n openshift-config >/dev/null 2>&1 \
      && ok "htpasswd secret present" || bad "htpasswd secret missing"
  fi
  local n
  n=$(oc get ns -l opendatahub.io/dashboard=true --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ok "namespaces flagged as AI projects: $n"
  n=$(oc get users --no-headers 2>/dev/null | grep -c '^agentic-user' || true)
  echo "      (OpenShift User objects materialise only after first login: $n so far)"
  [[ -f "$CRED_CSV" ]] && ok "credentials file present: ${CRED_CSV/#$HOME/\~}" \
                       || warn "no credentials file yet"
}

if [[ "$MODE" == check ]]; then report; exit 0; fi

mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"

echo "── building htpasswd for seats $RANGE_START..$RANGE_END ──"
HT_FILE=$(mktemp); CSV_TMP=$(mktemp)
cleanup() { rm -f "$HT_FILE" "$CSV_TMP"; }
trap cleanup EXIT
chmod 600 "$HT_FILE" "$CSV_TMP"
echo "username,password" > "$CSV_TMP"

[[ -n "$SHARED_PASSWORD" ]] && \
  warn "using ONE shared password for every seat (--password). Fine for a
      workshop where it goes on a slide; it means any attendee can log in as
      any other seat, so rotate or tear the cluster down afterwards."

for i in $(seq "$RANGE_START" "$RANGE_END"); do
  user="agentic-user$i"
  if [[ -n "$SHARED_PASSWORD" ]]; then
    pass="$SHARED_PASSWORD"
  else
    # Unambiguous alphabet: no O/0/I/l/1 so it can be read off a screen on stage.
    pass=$(python3 -I -c "
import secrets
a='ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
print(''.join(secrets.choice(a) for _ in range(14)))")
  fi
  htpasswd -bB "$HT_FILE" "$user" "$pass" >/dev/null 2>&1 || \
    htpasswd -cbB "$HT_FILE" "$user" "$pass" >/dev/null 2>&1
  printf '%s,%s\n' "$user" "$pass" >> "$CSV_TMP"
  unset pass
done
ok "hashed $(( RANGE_END - RANGE_START + 1 )) users (bcrypt)"

echo "── OAuth identity provider ─────────────────────────"
# ROSA HCP: oauth/cluster is IMMUTABLE from inside the guest cluster. A
# ValidatingAdmissionPolicy rejects any write with:
#   "This resource cannot be created, updated, or deleted. Please ask your
#    administrator to modify the resource in the HostedCluster object."
# IdPs must be set on the management side with the `rosa` CLI (or OCM), so on
# HCP this script prepares the htpasswd file and prints the exact command
# instead of failing. Classic (non-HCP) OpenShift takes the in-cluster path.
TOPOLOGY=$(oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}' 2>/dev/null)
HT_OUT="$STATE_DIR/seat-users.htpasswd"

if [[ "$TOPOLOGY" == "External" ]]; then
  install -m 600 "$HT_FILE" "$HT_OUT"
  warn "ROSA HCP detected (controlPlaneTopology=External)."
  warn "oauth/cluster cannot be modified from inside the cluster."
  echo
  echo "  htpasswd file written to: ${HT_OUT/#$HOME/\~}"
  echo "  Create the identity provider from a host that has the rosa CLI"
  echo "  (your bastion), with an OCM login:"
  echo
  echo "      rosa create idp --cluster=$GUID --type=htpasswd \\"
  echo "        --name=$IDP_NAME --from-file=$HT_OUT"
  echo
  echo "  Everything else below (RBAC, AI project labels) is applied now and"
  echo "  does not depend on the identities existing yet."
  echo
else
  oc create secret generic "$SECRET_NAME" \
    --from-file=htpasswd="$HT_FILE" -n openshift-config \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  ok "secret $SECRET_NAME applied"
  NEW_SPEC=$(python3 -I - "$IDP_NAME" "$SECRET_NAME" <<'PY'
import json, subprocess, sys
name, secret = sys.argv[1], sys.argv[2]
cur = json.loads(subprocess.run(
    ["oc", "get", "oauth", "cluster", "-o", "json"],
    capture_output=True, text=True, check=True).stdout)
spec = cur.get("spec") or {}
idps = [p for p in (spec.get("identityProviders") or []) if p.get("name") != name]
idps.append({
    "name": name,
    "mappingMethod": "claim",
    "type": "HTPasswd",
    "htpasswd": {"fileData": {"name": secret}},
})
print(json.dumps({"spec": {"identityProviders": idps}}))
PY
)
  oc patch oauth cluster --type=merge -p "$NEW_SPEC" >/dev/null
  ok "identity provider '$IDP_NAME' configured (HTPasswd, bcrypt)"
fi

echo "── per-seat RBAC + AI project label ────────────────"
GRANTED=0
for i in $(seq "$RANGE_START" "$RANGE_END"); do
  ns="agentic-user$i"; user="agentic-user$i"
  oc get namespace "$ns" >/dev/null 2>&1 || { warn "$ns missing, skipped"; continue; }
  # admin on their OWN namespace only — this is what makes the seat usable as
  # an RHOAI project, and it is namespace-scoped so seats cannot see each other.
  oc adm policy add-role-to-user admin "$user" -n "$ns" >/dev/null 2>&1 || true
  # claw-user is what lets them drive their Claw CR; 0-admin-setup.sh binds it
  # too, but re-assert so this script stands alone.
  oc adm policy add-role-to-user claw-user "$user" -n "$ns" --role-namespace="" >/dev/null 2>&1 || true
  # Flag the namespace as an AI project so RHOAI lists it under Projects.
  oc label namespace "$ns" opendatahub.io/dashboard=true --overwrite >/dev/null 2>&1 || true
  GRANTED=$((GRANTED + 1))
done
ok "granted admin + claw-user and flagged as AI project on $GRANTED namespaces"

install -m 600 "$CSV_TMP" "$CRED_CSV"
ok "credentials written to ${CRED_CSV/#$HOME/\~} (mode 600, gitignored, not printed)"

echo
if [[ "$TOPOLOGY" == "External" ]]; then
  echo "Logins will NOT work until you run the 'rosa create idp' command above."
else
  echo "The oauth-openshift pods redeploy now; logins work in roughly 1-2 minutes."
fi
echo "User objects appear in 'oc get users' only after each seat logs in once."
echo
report
