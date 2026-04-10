#!/usr/bin/env bash
#
# Delete all URGENT notes created by ProjectHealthCheck for a given project.
# Used to reset test runs for OpenClaw alerting/notification testing.
#
# Usage:
#   ./delete-project-urgent-notes.sh <customerId> <projectId>
#
# Examples:
#   BASE_URL=http://localhost:8081 ./delete-project-urgent-notes.sh CUST003 1
#   ./delete-project-urgent-notes.sh CUST003 1   # OpenShift route auto-discovery
#
# Requires: bash, curl, jq.
#
set -euo pipefail

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  echo "Usage: $0 <customerId> <projectId>" >&2
  echo "Optional: BASE_URL=http://localhost:8081 (default: OpenShift route for fantaco-customer-service)" >&2
  exit 1
fi

CUSTOMER_ID="$1"
PROJECT_ID="$2"

resolve_base_url() {
  if [[ -n "${BASE_URL:-}" ]]; then
    echo "${BASE_URL%/}"
    return
  fi
  local host
  host=$(oc get route fantaco-customer-service -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$host" ]]; then
    echo "Error: set BASE_URL (e.g. http://localhost:8081) or ensure oc route fantaco-customer-service exists." >&2
    exit 1
  fi
  echo "https://${host}"
}

BASE_URL="$(resolve_base_url)"
NOTES_URL="${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}/notes"

# Find URGENT notes authored by ProjectHealthCheck
NOTE_IDS="$(curl -sS "$NOTES_URL" | jq -r '.[] | select(.noteType == "URGENT" and .author == "ProjectHealthCheck") | .id')"

COUNT=0
if [[ -z "$NOTE_IDS" ]]; then
  echo "No ProjectHealthCheck URGENT notes found for customer=${CUSTOMER_ID} project=${PROJECT_ID}."
else
for id in $NOTE_IDS; do
  http_code=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "${NOTES_URL}/${id}")
  if [[ "$http_code" == "204" ]]; then
    echo "Deleted note id=${id}"
    ((COUNT++))
  else
    echo "Warning: DELETE note id=${id} returned HTTP ${http_code}" >&2
  fi
done

echo "Done. Deleted ${COUNT} URGENT note(s)."
fi

# --- Reset Account Watchdog state so the next heartbeat treats this project fresh ---
WATCHDOG_STATE="/home/node/.openclaw/workspace/watchdog/last-check.json"
OPENCLAW_POD=$(oc get pods -l app=openclaw -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$OPENCLAW_POD" ]]; then
  echo "Warning: OpenClaw pod not found — skipping watchdog state reset." >&2
  exit 0
fi

ENTRY_KEY="${CUSTOMER_ID}:${PROJECT_ID}"
echo "Resetting watchdog state for ${ENTRY_KEY}..."

# Read current state, remove this project's entry, write back
UPDATED=$(oc exec "$OPENCLAW_POD" -c gateway -- cat "$WATCHDOG_STATE" 2>/dev/null \
  | jq --arg key "$ENTRY_KEY" 'del(.[$key])' 2>/dev/null || echo "{}")

echo "$UPDATED" | oc exec -i "$OPENCLAW_POD" -c gateway -- sh -c "cat > ${WATCHDOG_STATE}"

echo "Watchdog state reset for ${ENTRY_KEY}."

# --- Remove project from watchlist so Sally must re-add it for the next demo run ---
WATCHLIST="/home/node/.openclaw/workspace/watchdog/watchlist.json"
echo "Removing ${ENTRY_KEY} from watchlist..."

UPDATED_WL=$(oc exec "$OPENCLAW_POD" -c gateway -- cat "$WATCHLIST" 2>/dev/null \
  | jq --arg cid "$CUSTOMER_ID" --argjson pid "$PROJECT_ID" \
    '[.[] | select(.customerId != $cid or (.projectId | tostring) != ($pid | tostring))]' 2>/dev/null || echo "[]")

echo "$UPDATED_WL" | oc exec -i "$OPENCLAW_POD" -c gateway -- sh -c "cat > ${WATCHLIST}"

echo "Removed ${ENTRY_KEY} from watchlist. Full demo reset complete."
