#!/usr/bin/env bash
# review-blocked-requests.sh — Scan proxy logs for blocked outbound requests
#
# Shows which users hit proxy blocks and what domains they were trying to reach.
# Useful during demos to identify domains that need to be added to the allowlist.
#
# Usage:
#   ./review-blocked-requests.sh                  # all namespaces, last 1h
#   ./review-blocked-requests.sh 1 5              # user1-user5, last 1h
#   ./review-blocked-requests.sh 3                # just user3, last 1h
#   ./review-blocked-requests.sh --since 30m      # all namespaces, last 30m
#   ./review-blocked-requests.sh --since 2h 1 5   # user1-user5, last 2h
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

# ── Parse --since flag ────────────────────────────────────────────
SINCE="1h"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

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
  echo "Usage: $0 [--since <duration>]              # all namespaces"
  echo "       $0 [--since <duration>] <start> [end] # range of namespaces"
  exit 1
fi

# ── Verify oc login ───────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Blocked Request Scanner${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  Namespaces: ${CYAN}${NAMESPACES[*]}${RESET}"
echo -e "  Time window: ${CYAN}${SINCE}${RESET}"
echo ""

# ── Collect blocked entries ───────────────────────────────────────
DETAIL_LINES=()
SUMMARY_LINES=()
TOTAL_BLOCKED=0

for NS in "${NAMESPACES[@]}"; do
  # Check if proxy pod is running
  PROXY_POD=$(oc get pods -n "$NS" -l app=instance-proxy --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$PROXY_POD" ]]; then
    echo -e "  ${DIM}$NS: proxy pod not running — skipping${RESET}"
    continue
  fi

  # Fetch proxy logs
  LOGS=$(oc logs deployment/instance-proxy -n "$NS" --since="$SINCE" 2>/dev/null || true)
  if [[ -z "$LOGS" ]]; then
    continue
  fi

  # Filter for blocked/denied entries
  BLOCKED=$(echo "$LOGS" | grep -iE "blocked|denied|deny|403|reject|WARN" || true)
  if [[ -z "$BLOCKED" ]]; then
    continue
  fi

  while IFS= read -r line; do
    # Extract domain — try several patterns the proxy might use
    DOMAIN=""
    # Pattern: domain=example.com or "domain":"example.com"
    if [[ -z "$DOMAIN" ]]; then
      DOMAIN=$(echo "$line" | grep -oP '(?<="?domain"?\s*[=:]\s*"?)[\w.-]+\.\w+' 2>/dev/null | head -1 || true)
    fi
    # Pattern: CONNECT host:443
    if [[ -z "$DOMAIN" ]]; then
      DOMAIN=$(echo "$line" | grep -oP 'CONNECT\s+\K[\w.-]+(?=:\d+)' 2>/dev/null | head -1 || true)
    fi
    # Pattern: host=example.com or "host":"example.com"
    if [[ -z "$DOMAIN" ]]; then
      DOMAIN=$(echo "$line" | grep -oP '(?<="?host"?\s*[=:]\s*"?)[\w.-]+\.\w+' 2>/dev/null | head -1 || true)
    fi
    # Fallback: any URL-like domain in the line
    if [[ -z "$DOMAIN" ]]; then
      DOMAIN=$(echo "$line" | grep -oP 'https?://\K[\w.-]+' 2>/dev/null | head -1 || true)
    fi
    [[ -z "$DOMAIN" ]] && DOMAIN="(unknown)"

    # Extract timestamp — ISO 8601 pattern
    TIMESTAMP=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' 2>/dev/null | head -1 || true)
    [[ -z "$TIMESTAMP" ]] && TIMESTAMP=$(echo "$line" | grep -oP '\d{2}:\d{2}:\d{2}' 2>/dev/null | head -1 || true)
    [[ -z "$TIMESTAMP" ]] && TIMESTAMP="-"

    DETAIL_LINES+=("${NS}|${TIMESTAMP}|${DOMAIN}")
    SUMMARY_LINES+=("${NS}|${DOMAIN}")
    TOTAL_BLOCKED=$((TOTAL_BLOCKED + 1))
  done <<< "$BLOCKED"
done

# ── Output ────────────────────────────────────────────────────────
if [[ $TOTAL_BLOCKED -eq 0 ]]; then
  echo -e "${GREEN}No blocked requests found in the last ${SINCE}.${RESET}"
  echo ""
  exit 0
fi

echo -e "${BOLD}${RED}Found ${TOTAL_BLOCKED} blocked request(s)${RESET}"
echo ""

# Detailed table (last 30 entries)
echo -e "${BOLD}── Recent Blocked Requests (last 30) ──────────────────${RESET}"
echo ""
printf "  ${BOLD}%-25s %-20s %s${RESET}\n" "NAMESPACE" "TIMESTAMP" "DOMAIN"
printf "  %-25s %-20s %s\n" "─────────────────────────" "────────────────────" "──────────────────────"

COUNT=0
START_IDX=0
if [[ ${#DETAIL_LINES[@]} -gt 30 ]]; then
  START_IDX=$(( ${#DETAIL_LINES[@]} - 30 ))
fi
for (( i=START_IDX; i<${#DETAIL_LINES[@]}; i++ )); do
  IFS='|' read -r ns ts domain <<< "${DETAIL_LINES[$i]}"
  printf "  ${CYAN}%-25s${RESET} ${DIM}%-20s${RESET} ${YELLOW}%s${RESET}\n" "$ns" "$ts" "$domain"
done
echo ""

# Summary — deduplicated with counts
echo -e "${BOLD}── Summary (by namespace + domain) ─────────────────────${RESET}"
echo ""
printf "  ${BOLD}%-25s %-35s %s${RESET}\n" "NAMESPACE" "DOMAIN" "COUNT"
printf "  %-25s %-35s %s\n" "─────────────────────────" "───────────────────────────────────" "─────"

printf '%s\n' "${SUMMARY_LINES[@]}" | sort | uniq -c | sort -rn | while read -r count entry; do
  IFS='|' read -r ns domain <<< "$entry"
  printf "  ${CYAN}%-25s${RESET} ${YELLOW}%-35s${RESET} ${RED}%s${RESET}\n" "$ns" "$domain" "$count"
done
echo ""

echo -e "${DIM}Tip: Use ./manage-proxy-allowlist.sh allow <domain> [user#] to approve a domain${RESET}"
echo ""
