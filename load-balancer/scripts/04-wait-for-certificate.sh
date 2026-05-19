#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

CERT_ARN=$(cat "$STATE_DIR/certificate-arn" 2>/dev/null || true)

if [[ -z "$CERT_ARN" ]]; then
  echo "ERROR: No certificate ARN found. Run 02-request-acm-certificate.sh first." >&2
  exit 1
fi

echo "==> Waiting for certificate to be issued: $CERT_ARN"
echo "    (ACM DNS validation typically takes 2-10 minutes)"
echo ""

MAX_ATTEMPTS=40
SLEEP_SECONDS=15

for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
  STATUS=$(aws acm describe-certificate \
    --region "$AWS_REGION" \
    --certificate-arn "$CERT_ARN" \
    --query 'Certificate.Status' --output text)

  echo "  Attempt $i/$MAX_ATTEMPTS — Status: $STATUS"

  if [[ "$STATUS" == "ISSUED" ]]; then
    echo ""
    echo "Certificate is ISSUED."
    echo "You can proceed with ALB creation and then run 05-create-wildcard-dns.sh."
    exit 0
  fi

  if [[ "$STATUS" == "FAILED" || "$STATUS" == "REVOKED" ]]; then
    echo ""
    echo "ERROR: Certificate status is $STATUS. Check the ACM console for details." >&2
    exit 1
  fi

  sleep "$SLEEP_SECONDS"
done

echo ""
echo "Timed out after $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds."
echo "Re-run this script to keep waiting, or check the ACM console."
exit 1
