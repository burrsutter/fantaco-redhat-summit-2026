#!/bin/bash
HOST=$(oc get route fantaco-customer-service -o jsonpath='{.spec.host}')
if [ -z "$HOST" ]; then
  echo "Error: could not find route 'fantaco-customer-service' in namespace $(oc project -q)"
  exit 1
fi
curl -s -X POST \
  "https://${HOST}/api/customers/CUST003/notes" \
  -H "Content-Type: application/json" \
  -d '{"noteText": "Urgent: customer called back again today and wants immediate help"}' | jq .
