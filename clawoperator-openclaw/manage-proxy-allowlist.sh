#!/usr/bin/env bash
# manage-proxy-allowlist.sh — Add, remove, or list domains in the proxy allowlist
#
# Modifies the instance-proxy-config ConfigMap to dynamically control which
# domains the L7 MITM proxy allows. Approved domains are global — they apply
# to ALL user namespaces. Persists changes to a state file so
# post-restart-repatch.sh can re-apply them after operator reconciliation.
#
# Usage:
#   ./manage-proxy-allowlist.sh list                                        # all namespaces
#   ./manage-proxy-allowlist.sh list 3                                      # just user3
#   ./manage-proxy-allowlist.sh allow api.nasa.gov                          # all namespaces, passthrough
#   ./manage-proxy-allowlist.sh allow api.nasa.gov --paths '/planetary/*'   # path-restricted (L7 proxy)
#   ./manage-proxy-allowlist.sh allow api.nasa.gov --paths '/planetary/*,/neo/*'  # multiple paths
#   ./manage-proxy-allowlist.sh allow api.nasa.gov 3                        # just user3
#   ./manage-proxy-allowlist.sh allow api.nasa.gov --paths '/api/*' 1 5     # user1-user5, path-restricted
#   ./manage-proxy-allowlist.sh revoke api.nasa.gov                         # all namespaces
#   ./manage-proxy-allowlist.sh revoke api.nasa.gov 3                       # just user3
#
# Path filtering:
#   Without --paths: adds as "passthrough" (TLS tunnel, no inspection)
#   With --paths:    adds as "proxy" with L7 path inspection (glob patterns)
#
# State file (.state/custom-proxy-domains.csv) is global — one domain per line:
#   api.nasa.gov,passthrough,,2026-05-26T14:30:00Z
#   api.example.com,proxy,/planetary/*:/neo/*,2026-05-26T15:00:00Z
#
# Requires: jq
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/.state"
STATE_FILE="${STATE_DIR}/custom-proxy-domains.csv"

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
  echo "       $0 allow <domain> [--paths '/path/*,...'] [user# | start end]"
  echo "       $0 revoke <domain> [user# | start end]"
  exit 1
fi

ACTION="$1"
shift

DOMAIN=""
PATHS=""
if [[ "$ACTION" == "allow" || "$ACTION" == "revoke" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: $ACTION requires a domain argument"
    echo "Usage: $0 $ACTION <domain> [--paths '/path/*,...'] [user# | start end]"
    exit 1
  fi
  DOMAIN="$1"
  shift

  # Parse --paths flag (only meaningful for allow, but consume it either way)
  if [[ ${1:-} == "--paths" ]]; then
    PATHS="$2"
    shift 2
  fi
fi

# ── Argument parsing (namespace selection) ────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  # No args — discover all agentic-user namespaces on cluster
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
  echo "Usage: $0 $ACTION ${DOMAIN:+<domain> }[user# | start end]"
  exit 1
fi

# ── Verify oc login ───────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Ensure state directory exists ─────────────────────────────────
mkdir -p "$STATE_DIR"

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

    ROUTES=$(echo "$CONFIG" | jq -r '.routes[] | if .paths then "  \(.domain)  (\(.action): \([.paths[].path] | join(", ")))" else "  \(.domain)  (\(.action))" end' 2>/dev/null || true)
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
  # Build the route JSON based on --paths flag
  if [[ -n "$PATHS" ]]; then
    # L7 proxy mode with path filtering
    PATHS_JSON=$(echo "$PATHS" | tr ',' '\n' | jq -R '{path: .}' | jq -s '.')
    ROUTE_JSON=$(jq -n --arg d "$DOMAIN" --argjson p "$PATHS_JSON" \
      '{"domain": $d, "action": "proxy", "paths": $p}')
    ACTION_DESC="proxy: ${PATHS}"
    STATE_ACTION="proxy"
    # Store paths with : separator for CSV (commas are field delimiters)
    STATE_PATHS="${PATHS//,/:}"
  else
    # TLS passthrough — no inspection
    ROUTE_JSON=$(jq -n --arg d "$DOMAIN" '{"domain": $d, "action": "passthrough"}')
    ACTION_DESC="passthrough"
    STATE_ACTION="passthrough"
    STATE_PATHS=""
  fi

  echo ""
  echo -e "${BOLD}Adding ${YELLOW}${DOMAIN}${RESET}${BOLD} to proxy allowlist (${ACTION_DESC})...${RESET}"
  echo ""

  for NS in "${NAMESPACES[@]}"; do
    # Read current config
    CURRENT=$(oc get configmap instance-proxy-config -n "$NS" \
      -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)

    if [[ -z "$CURRENT" ]]; then
      echo -e "  ${YELLOW}$NS: ConfigMap not found — skipping${RESET}"
      continue
    fi

    # Check if domain already exists — remove old entry so we can replace with new config
    EXISTS=$(echo "$CURRENT" | jq -r --arg d "$DOMAIN" '.routes[] | select(.domain == $d) | .domain' 2>/dev/null || true)
    if [[ -n "$EXISTS" ]]; then
      CURRENT=$(echo "$CURRENT" | jq --arg d "$DOMAIN" '.routes |= map(select(.domain != $d))')
    fi

    # Append the new route
    UPDATED=$(echo "$CURRENT" | jq --argjson r "$ROUTE_JSON" '.routes += [$r]')

    # Escape for ConfigMap patch (JSON inside JSON)
    ESCAPED=$(echo "$UPDATED" | jq -c '.' | jq -Rs '.')

    # Patch the ConfigMap
    if oc patch configmap instance-proxy-config -n "$NS" \
      --type merge -p "{\"data\":{\"proxy-config.json\":${ESCAPED}}}" &>/dev/null; then

      # Restart proxy to pick up new config
      oc rollout restart deployment/instance-proxy -n "$NS" &>/dev/null || true

      if [[ -n "$EXISTS" ]]; then
        echo -e "  ${GREEN}$NS: updated ${DOMAIN} (${ACTION_DESC}) — proxy restarting${RESET}"
      else
        echo -e "  ${GREEN}$NS: added ${DOMAIN} (${ACTION_DESC}) — proxy restarting${RESET}"
      fi
    else
      echo -e "  ${RED}$NS: failed to patch ConfigMap${RESET}"
    fi
  done

  # Save domain globally to state file (once, not per-namespace)
  # Format: domain,action,paths(colon-separated),timestamp
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [[ -f "$STATE_FILE" ]]; then
    grep -v "^${DOMAIN}," "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi
  echo "${DOMAIN},${STATE_ACTION},${STATE_PATHS},${TIMESTAMP}" >> "$STATE_FILE"

  echo ""
  echo -e "${GREEN}Done.${RESET} Proxy pods are restarting to pick up the new config."
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════════
# REVOKE
# ══════════════════════════════════════════════════════════════════
if [[ "$ACTION" == "revoke" ]]; then
  echo ""
  echo -e "${BOLD}Removing ${YELLOW}${DOMAIN}${RESET}${BOLD} from proxy allowlist...${RESET}"
  echo ""

  for NS in "${NAMESPACES[@]}"; do
    # Read current config
    CURRENT=$(oc get configmap instance-proxy-config -n "$NS" \
      -o jsonpath='{.data.proxy-config\.json}' 2>/dev/null || true)

    if [[ -z "$CURRENT" ]]; then
      echo -e "  ${YELLOW}$NS: ConfigMap not found — skipping${RESET}"
      continue
    fi

    # Check if domain exists
    EXISTS=$(echo "$CURRENT" | jq -r --arg d "$DOMAIN" '.routes[] | select(.domain == $d) | .domain' 2>/dev/null || true)
    if [[ -z "$EXISTS" ]]; then
      echo -e "  ${DIM}$NS: ${DOMAIN} not in allowlist — skipping${RESET}"
      continue
    fi

    # Remove the route
    UPDATED=$(echo "$CURRENT" | jq --arg d "$DOMAIN" '.routes |= map(select(.domain != $d))')

    # Escape for ConfigMap patch
    ESCAPED=$(echo "$UPDATED" | jq -c '.' | jq -Rs '.')

    # Patch the ConfigMap
    if oc patch configmap instance-proxy-config -n "$NS" \
      --type merge -p "{\"data\":{\"proxy-config.json\":${ESCAPED}}}" &>/dev/null; then

      # Restart proxy
      oc rollout restart deployment/instance-proxy -n "$NS" &>/dev/null || true

      echo -e "  ${GREEN}$NS: removed ${DOMAIN} — proxy restarting${RESET}"
    else
      echo -e "  ${RED}$NS: failed to patch ConfigMap${RESET}"
    fi
  done

  # Remove domain from global state file
  if [[ -f "$STATE_FILE" ]]; then
    grep -v "^${DOMAIN}," "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
    # Clean up empty state file
    if [[ ! -s "$STATE_FILE" ]]; then
      rm -f "$STATE_FILE"
    fi
  fi

  echo ""
  echo -e "${GREEN}Done.${RESET} Proxy pods are restarting to pick up the updated config."
  echo ""
  exit 0
fi

# ── Unknown action ────────────────────────────────────────────────
echo "Error: unknown action '$ACTION'"
echo "Usage: $0 list|allow|revoke ..."
exit 1
