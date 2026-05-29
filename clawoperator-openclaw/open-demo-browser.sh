#!/usr/bin/env bash
# open-demo-browser.sh — Open Brave with the broker status board and audience URL
#
# Reads audience code and status key from .state/<cluster-guid>/broker.env
#
# Usage:
#   ./open-demo-browser.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
BRAVE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"

# Find broker state from any cluster
AUDIENCE_CODE=""
STATUS_KEY=""
for STATE_FILE in "$SCRIPT_DIR"/.state/*/broker.env; do
  [[ -f "$STATE_FILE" ]] || continue
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  [[ -n "${AUDIENCE_CODE:-}" ]] && break
done

if [[ -z "$AUDIENCE_CODE" ]]; then
  echo "Error: No audience code found. Run audience-reset.sh or update-broker.sh first."
  exit 1
fi

STATUS_URL="https://${BROKER_DOMAIN}/status"
[[ -n "$STATUS_KEY" ]] && STATUS_URL+="?key=${STATUS_KEY}"

AUDIENCE_URL="https://${BROKER_DOMAIN}/${AUDIENCE_CODE}"

echo "Status:   $STATUS_URL"
echo "Audience: $AUDIENCE_URL"

"$BRAVE" --app="$STATUS_URL" &
sleep 1
"$BRAVE" --app="$AUDIENCE_URL" &
