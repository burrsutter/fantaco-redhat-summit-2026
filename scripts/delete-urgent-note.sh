#!/bin/bash
HOST=$(oc get route fantaco-customer-service -o jsonpath='{.spec.host}')
if [ -z "$HOST" ]; then
  echo "Error: could not find route 'fantaco-customer-service' in namespace $(oc project -q)"
  exit 1
fi
BASE_URL="https://${HOST}/api/customers/CUST003/notes"

NOTE_ID=$(curl -s "$BASE_URL" | jq -r '.[] | select(.noteText | startswith("Urgent")) | .id')

if [ -z "$NOTE_ID" ]; then
  echo "No note starting with 'Urgent' found for CUST003"
  exit 1
fi

echo "Deleting note ID: $NOTE_ID"
curl -s -X DELETE "$BASE_URL/$NOTE_ID" -w "\nHTTP Status: %{http_code}\n"
