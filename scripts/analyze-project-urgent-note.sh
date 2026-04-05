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
  .siteAddress as $site |
  .estimatedEndDate as $deadline |

  # Collect IN_PROGRESS milestones
  [ (.milestones // [])[] | select(.status == "IN_PROGRESS") ] as $active |

  "URGENT: Electrical inspection failed on build-out for \"\($pname)\"." +
  (if $site then " Site: \($site)." else "" end) +
  " City inspector flagged wiring for the holographic display array as non-compliant with updated fire code (NEC 2026 Article 600). All ceiling work halted until a licensed electrician re-routes conduit. Estimated 5-day delay and $12,000 additional cost." +
  (if $deadline then " Client is concerned about the \($deadline) deadline." else "" end) +
  " Sales rep needs to schedule a site visit and manage expectations immediately." +

  if ($active | length) > 0 then
    "\n\nAffected active milestones:\n" +
    ( [ $active[] |
        "  - \(.name)" +
        (if .dueDate then " (due \(.dueDate))" else "" end)
      ] | join("\n") )
  else ""
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
