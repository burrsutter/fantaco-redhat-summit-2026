#!/usr/bin/env bash
# monitor-pods.sh — Live pod monitor for OpenClaw instances across agentic-user namespaces
#
# Usage:
#   ./monitor-pods.sh          # monitor all agentic-user namespaces found on cluster
#   Ctrl+C to stop

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Clean exit on Ctrl+C ─────────────────────────────────────────────
cleanup() {
  printf '\n%bMonitor stopped.%b\n' "$YELLOW" "$RESET"
  exit 0
}
trap cleanup INT TERM

# ── Verify oc login ──────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Get cluster info once ────────────────────────────────────────────
CLUSTER=$(oc whoami --show-server 2>/dev/null | sed 's|https://api\.||; s|:.*||')

# ── Main loop ────────────────────────────────────────────────────────
while true; do
  clear

  # Discover agentic-user namespaces
  NAMESPACES=$(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep '^agentic-user' | sort -V)

  if [[ -z "$NAMESPACES" ]]; then
    printf '%b  OpenClaw Pod Monitor%b — %s\n' "$GREEN$BOLD" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '  Cluster: %s\n\n' "$CLUSTER"
    printf '  %bNo agentic-user namespaces found.%b\n' "$YELLOW" "$RESET"
  else
    printf '%b  OpenClaw Pod Monitor%b — %s\n' "$GREEN$BOLD" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '  Cluster: %s\n' "$CLUSTER"

    for NS in $NAMESPACES; do
      POD_OUTPUT=$(oc get pods -n "$NS" \
        -l claw.sandbox.redhat.com/instance=instance \
        --no-headers 2>/dev/null | grep -v '^instance-device-pairing' || true)

      # Get audience route hostname
      AUDIENCE_HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)

      if [[ -z "$POD_OUTPUT" ]]; then
        printf '  %b%-16s%b %b(no instance pods)%b\n' "$BOLD" "$NS" "$RESET" "$YELLOW" "$RESET"
      else
        FIRST=true
        while IFS= read -r line; do
          STATUS=$(echo "$line" | awk '{print $3}')
          if $FIRST; then
            PREFIX=$(printf '%b%-16s%b' "$BOLD" "$NS" "$RESET")
            FIRST=false
          else
            PREFIX=$(printf '%-16s' "")
          fi
          if [[ "$STATUS" == "Running" ]]; then
            printf '  %s %s\n' "$PREFIX" "$line"
          else
            printf '  %s %b%s%b\n' "$PREFIX" "$RED" "$line" "$RESET"
          fi
        done <<< "$POD_OUTPUT"
        if [[ -n "$AUDIENCE_HOST" ]]; then
          printf '  %-16s %b%s%b\n' "" "$GREEN" "$AUDIENCE_HOST" "$RESET"
        fi
      fi
    done
  fi

  printf '  (refreshing every 3s — Ctrl+C to stop)\n'
  sleep 3
done
