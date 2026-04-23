#!/usr/bin/env bash
#
# add-dev-users.sh — Provision dev users in Keycloak (backstage realm) and GitLab.
#
# Idempotent: safe to re-run. Skips users/memberships that already exist.
#
# Usage:
#   ./scripts/add-dev-users.sh N            # add N users after the highest existing devN
#   ./scripts/add-dev-users.sh 5            # if dev10 exists → creates dev11–dev15
#   ./scripts/add-dev-users.sh              # no arg = re-sync existing users (no new ones)
#   START=3 END=10 ./scripts/add-dev-users.sh  # explicit range (overrides N)
#
# Environment (auto-discovered from cluster if not set):
#   CLUSTER_DOMAIN       Base cluster domain
#   KEYCLOAK_ADMIN_PASSWORD  Keycloak admin password
#   GITLAB_TOKEN         GitLab root/admin API token
#   PASSWORD             User password (default: aIgMsZ3UPPwO)
#   START / END          Explicit user range (overrides N)

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
skip() { printf "${YELLOW}⊘${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*"; }
info() { printf "${CYAN}→${NC} %s\n" "$*"; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
for cmd in oc curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "Required command not found: $cmd"; exit 1; }
done

# ── Auto-discover from cluster ──────────────────────────────────────────────
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-$(oc whoami --show-console 2>/dev/null | sed 's|https://console-openshift-console\.apps\.||')}"
[[ -z "$CLUSTER_DOMAIN" ]] && { fail "Cannot detect CLUSTER_DOMAIN — set it or log in with oc"; exit 1; }

KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-$(oc get secret keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)}"
[[ -z "$KEYCLOAK_ADMIN_PASSWORD" ]] && { fail "Cannot read keycloak-initial-admin secret — set KEYCLOAK_ADMIN_PASSWORD"; exit 1; }

GITLAB_TOKEN="${GITLAB_TOKEN:-$(oc get secret gitlab-token -n parasol-insurance-dev -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)}"
[[ -z "$GITLAB_TOKEN" ]] && { fail "Cannot read gitlab-token secret — set GITLAB_TOKEN"; exit 1; }

PASSWORD="${PASSWORD:-aIgMsZ3UPPwO}"
ADD_COUNT="${1:-0}"

# ── Derived URLs ────────────────────────────────────────────────────────────
KC_URL="https://sso.apps.${CLUSTER_DOMAIN}"
GL_URL="https://gitlab-gitlab.apps.${CLUSTER_DOMAIN}"

# ── First names (D-names pool) ──────────────────────────────────────────────
# dev1=Dave, dev2=Divya (pre-existing), then this pool for dev3+
D_NAMES="Dave Divya Diana Derek Dina Dan Dalia Doug Donna Dmitri Darcy Devin Dahlia Duncan Dara Dominic Delilah Desmond Daphne Dalton"
get_first_name() {
  local num=$1
  if [[ "$num" -lt 1 || "$num" -gt 20 ]]; then
    echo "Dev${num}"
    return
  fi
  echo "$D_NAMES" | tr ' ' '\n' | sed -n "${num}p"
}

# ── Keycloak: obtain admin token ────────────────────────────────────────────
get_kc_token() {
  local resp
  resp=$(curl -sk -X POST "${KC_URL}/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password")
  echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null \
    || { fail "Failed to obtain Keycloak admin token"; exit 1; }
}

info "Authenticating to Keycloak at ${KC_URL}"
KC_TOKEN=$(get_kc_token)
ok "Keycloak admin token acquired"

# ── Compute user range ──────────────────────────────────────────────────────
if [[ -n "${START:-}" && -n "${END:-}" ]]; then
  # Explicit range from environment
  info "Using explicit range: dev${START}–dev${END}"
elif [[ "$ADD_COUNT" -gt 0 ]]; then
  # Find highest existing devN in Keycloak
  MAX_DEV=$(curl -sk "${KC_URL}/admin/realms/backstage/users?max=500" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    | python3 -c "
import sys, json, re
users = json.load(sys.stdin)
nums = [int(m.group(1)) for u in users for m in [re.match(r'^dev(\d+)$', u['username'])] if m]
print(max(nums) if nums else 0)
" 2>/dev/null)
  MAX_DEV="${MAX_DEV:-0}"
  START=$((MAX_DEV + 1))
  END=$((MAX_DEV + ADD_COUNT))
  info "Highest existing dev user: dev${MAX_DEV}"
  info "Will create: dev${START}–dev${END} (${ADD_COUNT} new users)"
else
  # No arg, no explicit range — re-sync all existing dev users
  MAX_DEV=$(curl -sk "${KC_URL}/admin/realms/backstage/users?max=500" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    | python3 -c "
import sys, json, re
users = json.load(sys.stdin)
nums = [int(m.group(1)) for u in users for m in [re.match(r'^dev(\d+)$', u['username'])] if m]
print(max(nums) if nums else 0)
" 2>/dev/null)
  MAX_DEV="${MAX_DEV:-0}"
  if [[ "$MAX_DEV" -eq 0 ]]; then
    info "No existing dev users found and no count specified — nothing to do"
    exit 0
  fi
  START=1
  END="$MAX_DEV"
  info "Re-syncing existing users: dev${START}–dev${END}"
fi

# ── Keycloak: provision users ───────────────────────────────────────────────
printf "\n${BOLD}══ Keycloak (backstage realm) ══${NC}\n"

for i in $(seq "$START" "$END"); do
  USER="dev${i}"
  FIRST=$(get_first_name "$i")
  EMAIL="${USER}@rhdemo.com"

  # Check if user exists
  EXISTING=$(curl -sk "${KC_URL}/admin/realms/backstage/users?username=${USER}&exact=true" \
    -H "Authorization: Bearer ${KC_TOKEN}")
  COUNT=$(echo "$EXISTING" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)

  if [[ "$COUNT" -gt 0 ]]; then
    skip "Keycloak: ${USER} already exists"
  else
    # Create user
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
      "${KC_URL}/admin/realms/backstage/users" \
      -H "Authorization: Bearer ${KC_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"username\": \"${USER}\",
        \"email\": \"${EMAIL}\",
        \"firstName\": \"${FIRST}\",
        \"lastName\": \"Developer\",
        \"enabled\": true,
        \"emailVerified\": true
      }")

    if [[ "$HTTP_CODE" == "201" ]]; then
      ok "Keycloak: created ${USER} (${FIRST} Developer)"
    elif [[ "$HTTP_CODE" == "409" ]]; then
      skip "Keycloak: ${USER} already exists (409)"
    else
      fail "Keycloak: failed to create ${USER} (HTTP ${HTTP_CODE})"
      continue
    fi
  fi

  # Set password — fetch user ID first
  USER_ID=$(curl -sk "${KC_URL}/admin/realms/backstage/users?username=${USER}&exact=true" \
    -H "Authorization: Bearer ${KC_TOKEN}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])" 2>/dev/null)

  if [[ -n "$USER_ID" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
      "${KC_URL}/admin/realms/backstage/users/${USER_ID}/reset-password" \
      -H "Authorization: Bearer ${KC_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"type\": \"password\",
        \"value\": \"${PASSWORD}\",
        \"temporary\": false
      }")

    if [[ "$HTTP_CODE" == "204" ]]; then
      ok "Keycloak: password set for ${USER}"
    else
      fail "Keycloak: failed to set password for ${USER} (HTTP ${HTTP_CODE})"
    fi
  fi
done

# ── GitLab: provision users and group memberships ───────────────────────────
printf "\n${BOLD}══ GitLab ══${NC}\n"

# Cache group IDs
PARASOL_GID=$(curl -sk "${GL_URL}/api/v4/groups/parasol" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
DEVTEAM1_GID=$(curl -sk "${GL_URL}/api/v4/groups/devteam1" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)

info "Group IDs — parasol=${PARASOL_GID}, devteam1=${DEVTEAM1_GID}"

for i in $(seq "$START" "$END"); do
  USER="dev${i}"
  FIRST=$(get_first_name "$i")
  EMAIL="${USER}@rhdemo.com"
  FULL_NAME="${FIRST} Developer"

  printf "\n${CYAN}─ ${USER} ─${NC}\n"

  # Check if GitLab user exists
  GL_USER_ID=$(curl -sk "${GL_URL}/api/v4/users?username=${USER}" \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    | python3 -c "
import sys,json
users = json.load(sys.stdin)
print(users[0]['id'] if users else '')
" 2>/dev/null)

  if [[ -n "$GL_USER_ID" ]]; then
    skip "GitLab: ${USER} already exists (id=${GL_USER_ID})"
  else
    # Create GitLab user
    RESP=$(curl -sk -X POST "${GL_URL}/api/v4/users" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"username\": \"${USER}\",
        \"email\": \"${EMAIL}\",
        \"name\": \"${FULL_NAME}\",
        \"password\": \"${PASSWORD}\",
        \"skip_confirmation\": true
      }")

    GL_USER_ID=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

    if [[ -n "$GL_USER_ID" && "$GL_USER_ID" != "None" ]]; then
      ok "GitLab: created ${USER} (id=${GL_USER_ID})"
    else
      ERROR_MSG=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message', d.get('error','unknown')))" 2>/dev/null || echo "unknown")
      fail "GitLab: failed to create ${USER}: ${ERROR_MSG}"
      continue
    fi
  fi

  # Add to parasol group (Owner = access_level 50)
  if [[ -n "$PARASOL_GID" ]]; then
    # Check existing membership
    MEMBER_CHECK=$(curl -sk -o /dev/null -w "%{http_code}" \
      "${GL_URL}/api/v4/groups/${PARASOL_GID}/members/${GL_USER_ID}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

    if [[ "$MEMBER_CHECK" == "200" ]]; then
      skip "GitLab: ${USER} already in parasol group"
    else
      HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
        "${GL_URL}/api/v4/groups/${PARASOL_GID}/members" \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": ${GL_USER_ID}, \"access_level\": 50}")

      if [[ "$HTTP_CODE" == "201" ]]; then
        ok "GitLab: added ${USER} to parasol (Owner)"
      elif [[ "$HTTP_CODE" == "409" ]]; then
        skip "GitLab: ${USER} already in parasol group (409)"
      else
        fail "GitLab: failed to add ${USER} to parasol (HTTP ${HTTP_CODE})"
      fi
    fi
  fi

  # Add to devteam1 group (Owner = access_level 50)
  if [[ -n "$DEVTEAM1_GID" ]]; then
    MEMBER_CHECK=$(curl -sk -o /dev/null -w "%{http_code}" \
      "${GL_URL}/api/v4/groups/${DEVTEAM1_GID}/members/${GL_USER_ID}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

    if [[ "$MEMBER_CHECK" == "200" ]]; then
      skip "GitLab: ${USER} already in devteam1 group"
    else
      HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
        "${GL_URL}/api/v4/groups/${DEVTEAM1_GID}/members" \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": ${GL_USER_ID}, \"access_level\": 50}")

      if [[ "$HTTP_CODE" == "201" ]]; then
        ok "GitLab: added ${USER} to devteam1 (Owner)"
      elif [[ "$HTTP_CODE" == "409" ]]; then
        skip "GitLab: ${USER} already in devteam1 group (409)"
      else
        fail "GitLab: failed to add ${USER} to devteam1 (HTTP ${HTTP_CODE})"
      fi
    fi
  fi
done

# ── OpenShift: grant admin on parasol-insurance-dev ─────────────────────────
printf "\n${BOLD}══ OpenShift (parasol-insurance-dev) ══${NC}\n"

for i in $(seq "$START" "$END"); do
  USER="dev${i}"

  # Check if role binding already exists
  if oc get rolebinding "${USER}-admin" -n parasol-insurance-dev >/dev/null 2>&1; then
    skip "OpenShift: ${USER} already has admin in parasol-insurance-dev"
  else
    if oc adm policy add-role-to-user admin "${USER}" -n parasol-insurance-dev >/dev/null 2>&1; then
      ok "OpenShift: granted admin to ${USER} in parasol-insurance-dev"
    else
      fail "OpenShift: failed to grant admin to ${USER}"
    fi
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────
printf "\n${BOLD}══ Done ══${NC}\n"
ok "Processed dev${START}–dev${END} in Keycloak, GitLab, and OpenShift"
info "Users can log in to OpenShift via the 'developers' identity provider"
info "DevSpaces will auto-provision on first login"
