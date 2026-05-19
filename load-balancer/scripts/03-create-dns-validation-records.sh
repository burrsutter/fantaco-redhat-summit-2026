#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

CERT_ARN=$(cat "$STATE_DIR/certificate-arn" 2>/dev/null || true)
ZONE_ID=$(cat "$STATE_DIR/hosted-zone-id" 2>/dev/null || true)

if [[ -z "$CERT_ARN" ]]; then
  echo "ERROR: No certificate ARN found. Run 02-request-acm-certificate.sh first." >&2
  exit 1
fi
if [[ -z "$ZONE_ID" ]]; then
  echo "ERROR: No hosted zone ID found. Run 01-create-hosted-zone.sh first." >&2
  exit 1
fi

echo "==> Fetching DNS validation records for certificate: $CERT_ARN"

VALIDATION_JSON=$(aws acm describe-certificate \
  --region "$AWS_REGION" \
  --certificate-arn "$CERT_ARN" \
  --query 'Certificate.DomainValidationOptions[].ResourceRecord' \
  --output json)

RECORD_COUNT=$(echo "$VALIDATION_JSON" | jq 'length')

if [[ "$RECORD_COUNT" -eq 0 ]]; then
  echo "ERROR: No validation records found. The certificate may already be validated or the request failed." >&2
  exit 1
fi

echo "Found $RECORD_COUNT validation record(s) to create."

CHANGES=$(echo "$VALIDATION_JSON" | jq -c '[.[] | {
  Action: "UPSERT",
  ResourceRecordSet: {
    Name: .Name,
    Type: .Type,
    TTL: 300,
    ResourceRecords: [{ Value: .Value }]
  }
}] | unique_by(.ResourceRecordSet.Name)')

CHANGE_BATCH=$(jq -n --argjson changes "$CHANGES" '{
  Comment: "ACM DNS validation for ${DOMAIN}",
  Changes: $changes
}')

echo "==> Creating validation CNAME records in hosted zone: $ZONE_ID"
echo "$CHANGE_BATCH" | jq '.Changes[].ResourceRecordSet | "\(.Name) -> \(.ResourceRecords[0].Value)"'

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Id' --output text)

echo ""
echo "Change submitted: $CHANGE_ID"
echo "Waiting for DNS propagation (this can take 30-60 seconds)..."

aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

echo "DNS records propagated."
echo ""
echo "Run 04-wait-for-certificate.sh to poll until ACM validates and issues the certificate."
