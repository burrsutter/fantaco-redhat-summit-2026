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

if [[ -z "$NOTE_IDS" ]]; then
  echo "No ProjectHealthCheck URGENT notes found for customer=${CUSTOMER_ID} project=${PROJECT_ID}."
  exit 0
fi

COUNT=0
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
