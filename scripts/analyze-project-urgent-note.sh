#!/usr/bin/env bash
#
# Generate a deterministic URGENT project note for an Imagination Pod project.
# Fetches milestones and includes any IN_PROGRESS tasks as context in the note.
# Always creates the note — intended for testing OpenClaw alerting/notification.
#
# Usage:
#   ./analyze-project-urgent-note.sh <customerId> <projectId>
#
# Examples (local Customer API on 8081):
#   BASE_URL=http://localhost:8081 ./analyze-project-urgent-note.sh CUST003 1
#
# OpenShift (default): discovers https://<route-host> from `oc get route fantaco-customer-service`.
#   ./analyze-project-urgent-note.sh CUST003 1
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

tmp_project="$(mktemp)"
cleanup() { rm -f "$tmp_project"; }
trap cleanup EXIT

# --- Fetch the project (includes milestones) ---
http_project=$(curl -sS -o "$tmp_project" -w "%{http_code}" \
  "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}")
if [[ "$http_project" != "200" ]]; then
  echo "Error: GET project failed (HTTP ${http_project})" >&2
  cat "$tmp_project" >&2
  exit 1
fi

# --- Build the note text from project + milestone context ---
NOTE_TEXT="$(jq -r '
  .projectName as $pname |
  .status as $pstatus |

  # Collect IN_PROGRESS milestones
  [ (.milestones // [])[] | select(.status == "IN_PROGRESS") ] as $active |

  # Collect all milestones for summary
  (.milestones // []) as $all |

  "URGENT: Project health review for \"\($pname)\" (status: \($pstatus)).\n\n" +

  "Milestone summary: \($all | length) total" +
  (if ($all | length) > 0 then
    " — " +
    "\([ $all[] | select(.status == "COMPLETED") ] | length) completed, " +
    "\([ $all[] | select(.status == "IN_PROGRESS") ] | length) in progress, " +
    "\([ $all[] | select(.status == "NOT_STARTED") ] | length) not started, " +
    "\([ $all[] | select(.status == "BLOCKED") ] | length) blocked"
  else "" end) +
  ".\n\n" +

  if ($active | length) > 0 then
    "Active tasks (IN_PROGRESS):\n" +
    ( [ $active[] |
        "  - \(.name)" +
        (if .dueDate then " (due \(.dueDate))" else "" end)
      ] | join("\n") ) +
    "\n\nImmediate attention required — review active milestones for risk."
  else
    "No milestones are currently IN_PROGRESS.\n\nImmediate attention required — project may be stalled."
  end
' "$tmp_project")"

payload="$(jq -n \
  --arg text "$NOTE_TEXT" \
  '{noteText: $text, noteType: "URGENT", author: "ProjectHealthCheck"}')"

echo "Creating URGENT project note for customer=${CUSTOMER_ID} project=${PROJECT_ID}..."
curl -sS -X POST \
  "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}/notes" \
  -H "Content-Type: application/json" \
  -d "$payload" | jq .
