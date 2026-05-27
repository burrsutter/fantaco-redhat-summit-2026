#!/usr/bin/env bash
# manage-proxy-allowlist.sh — Add, remove, or list domains in the proxy allowlist
#
# Patches the Claw CR (spec.credentials) so the claw-operator generates the
# correct proxy config. Direct ConfigMap patches get overwritten by the operator.
#
# For each allowed domain, creates a Secret + credential entry with type=apiKey
# using a harmless no-op header (X-Proxy-Passthrough). The operator sees a valid
# credential and adds the domain to the proxy allowlist.
#
# Usage:
#   ./manage-proxy-allowlist.sh list                          # all namespaces
#   ./manage-proxy-allowlist.sh list 3                        # just user3
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov                   # all namespaces
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov 3                 # just user3
#   ./manage-proxy-allowlist.sh allow apod.nasa.gov 1 5               # user1-user5
#   ./manage-proxy-allowlist.sh allow xkcd.com,imgs.xkcd.com 2       # multiple domains
#   ./manage-proxy-allowlist.sh revoke apod.nasa.gov                  # all namespaces
#   ./manage-proxy-allowlist.sh revoke apod.nasa.gov 3                # just user3
#   ./manage-proxy-allowlist.sh revoke xkcd.com,imgs.xkcd.com        # multiple domains
#
# Requires: jq
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

# ── Require jq ────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed."
  exit 1
fi

# ── Parse subcommand ──────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 list [user# | start end]"
  echo "       $0 allow <domain>[,domain2,...] [user# | start end]"
  echo "       $0 revoke <domain>[,domain2,...] [user# | start end]"
  exit 1
fi

ACTION="$1"
shift

DOMAINS=()
if [[ "$ACTION" == "allow" || "$ACTION" == "revoke" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: $ACTION requires a domain argument"
    echo "Usage: $0 $ACTION <domain>[,domain2,...] [user# | start end]"
    exit 1
  fi
  IFS=',' read -ra DOMAINS <<< "$1"
  shift
fi

# ── Argument parsing (namespace selection) ────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo "Error: No ${NAMESPACE_PREFIX}* namespaces found on cluster."
    exit 1
  fi
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
  echo "Usage: $0 $ACTION <domain>[,domain2,...] [user# | start end]"
  exit 1
fi

# ── Verify oc login ───────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Helper: domain → credential name ─────────────────────────────
# Converts "apod.nasa.gov" → "allow-apod-nasa-gov"
domain_to_name() {
  echo "allow-${1//./-}"
}

# ══════════════════════════════════════════════════════════════════
# LIST
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "list" ]]; then
  echo ""
  echo -e "${BOLD}============================================${RESET}"
  echo -e "${BOLD}  Proxy Allowlist${RESET}"
  echo -e "${BOLD}============================================${RESET}"
  echo ""

  for NS in "${NAMESPACES[@]}"; do
    echo -e "${BOLD}${CYAN}$NS:${RESET}"

    CONFIG=$(oc get configmap instance-proxy-config -n "$NS" \
      -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)

    if [[ -z "$CONFIG" ]]; then
      echo -e "  ${YELLOW}(ConfigMap instance-proxy-config not found)${RESET}"
      echo ""
      continue
    fi

    ROUTES=$(echo "$CONFIG" | jq -r '.routes[] | if .allowedPaths then "  \(.domain)  (allowedPaths: \(.allowedPaths | join(", ")))" else "  \(.domain)  (\(.injector // "none"))" end' 2>/dev/null || true)
    if [[ -n "$ROUTES" ]]; then
      echo "$ROUTES"
    else
      echo -e "  ${DIM}(no routes configured)${RESET}"
    fi
    echo ""
  done
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# ALLOW
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "allow" ]]; then
  echo ""
  echo -e "${BOLD}Adding ${YELLOW}${DOMAINS[*]}${RESET}${BOLD} to proxy allowlist...${RESET}"
  echo ""

  for DOMAIN in "${DOMAINS[@]}"; do
    CRED_NAME=$(domain_to_name "$DOMAIN")
    SECRET_NAME="${CRED_NAME}-key"

    for NS in "${NAMESPACES[@]}"; do
      # 1. Create the passthrough secret if needed
      if ! oc get secret "$SECRET_NAME" -n "$NS" &>/dev/null; then
        if ! oc create secret generic "$SECRET_NAME" -n "$NS" \
          --from-literal=api-key=PASSTHROUGH 2>/dev/null; then
          echo -e "  ${RED}$NS: failed to create secret for ${DOMAIN}${RESET}"
          continue
        fi
      fi

      # 2. Check if credential already exists in the Claw CR
      EXISTS=$(oc get claw instance -n "$NS" -o json 2>/dev/null \
        | jq -r --arg n "$CRED_NAME" '.spec.credentials[]? | select(.name == $n) | .name' || true)

      if [[ -n "$EXISTS" ]]; then
        echo -e "  ${DIM}$NS: ${DOMAIN} already in allowlist${RESET}"
        continue
      fi

      # 3. Patch the Claw CR to add the credential
      CRED_JSON=$(jq -n \
        --arg name "$CRED_NAME" \
        --arg domain "$DOMAIN" \
        --arg secret "$SECRET_NAME" \
        '{
          name: $name,
          domain: $domain,
          type: "apiKey",
          apiKey: { header: "X-Proxy-Passthrough", valuePrefix: "" },
          secretRef: [{ key: "api-key", name: $secret }]
        }')

      if oc patch claw instance -n "$NS" --type json \
        -p "[{\"op\":\"add\",\"path\":\"/spec/credentials/-\",\"value\":${CRED_JSON}}]" &>/dev/null; then
        echo -e "  ${GREEN}$NS: added ${DOMAIN}${RESET}"
      else
        echo -e "  ${RED}$NS: failed to patch Claw CR for ${DOMAIN}${RESET}"
      fi
    done
  done

  echo ""
  echo -e "${DIM}Waiting for operator to reconcile...${RESET}"
  sleep 5

  # Verify all domains on first namespace
  FIRST_NS="${NAMESPACES[0]}"
  for DOMAIN in "${DOMAINS[@]}"; do
    VERIFY=$(oc get configmap instance-proxy-config -n "$FIRST_NS" \
      -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null \
      | jq -r --arg d "$DOMAIN" '.routes[]? | select(.domain == $d) | .domain' || true)

    if [[ "$VERIFY" == "$DOMAIN" ]]; then
      echo -e "${GREEN}Verified: ${DOMAIN} is in the proxy config for ${FIRST_NS}${RESET}"
    else
      echo -e "${YELLOW}Warning: ${DOMAIN} not yet in proxy config for ${FIRST_NS} — operator may still be reconciling${RESET}"
    fi
  done

  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# REVOKE
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "revoke" ]]; then
  echo ""
  echo -e "${BOLD}Removing ${YELLOW}${DOMAINS[*]}${RESET}${BOLD} from proxy allowlist...${RESET}"
  echo ""

  for DOMAIN in "${DOMAINS[@]}"; do
    CRED_NAME=$(domain_to_name "$DOMAIN")
    SECRET_NAME="${CRED_NAME}-key"

    for NS in "${NAMESPACES[@]}"; do
      # 1. Find the credential index in the Claw CR
      CRED_INDEX=$(oc get claw instance -n "$NS" -o json 2>/dev/null \
        | jq --arg n "$CRED_NAME" '[.spec.credentials[]? | .name] | to_entries[] | select(.value == $n) | .key' || true)

      if [[ -z "$CRED_INDEX" ]]; then
        echo -e "  ${DIM}$NS: ${DOMAIN} not in allowlist — skipping${RESET}"
        continue
      fi

      # 2. Remove the credential from the Claw CR
      if oc patch claw instance -n "$NS" --type json \
        -p "[{\"op\":\"remove\",\"path\":\"/spec/credentials/${CRED_INDEX}\"}]" &>/dev/null; then
        echo -e "  ${GREEN}$NS: removed ${DOMAIN}${RESET}"
      else
        echo -e "  ${RED}$NS: failed to patch Claw CR for ${DOMAIN}${RESET}"
      fi

      # 3. Clean up the secret
      oc delete secret "$SECRET_NAME" -n "$NS" &>/dev/null || true
    done
  done

  echo ""
  echo -e "${DIM}Waiting for operator to reconcile...${RESET}"
  sleep 5

  # Verify all domains on first namespace
  FIRST_NS="${NAMESPACES[0]}"
  for DOMAIN in "${DOMAINS[@]}"; do
    VERIFY=$(oc get configmap instance-proxy-config -n "$FIRST_NS" \
      -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null \
      | jq -r --arg d "$DOMAIN" '.routes[]? | select(.domain == $d) | .domain' || true)

    if [[ -z "$VERIFY" ]]; then
      echo -e "${GREEN}Verified: ${DOMAIN} removed from proxy config for ${FIRST_NS}${RESET}"
    else
      echo -e "${YELLOW}Warning: ${DOMAIN} still in proxy config for ${FIRST_NS} — operator may still be reconciling${RESET}"
    fi
  done

  echo ""
  exit 0
fi

# ── Unknown action ────────────────────────────────────────────────
echo "Error: unknown action '$ACTION'"
echo "Usage: $0 list|allow|revoke ..."
exit 1
