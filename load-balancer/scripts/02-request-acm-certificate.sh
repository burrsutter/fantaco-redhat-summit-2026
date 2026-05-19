#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

echo "==> Checking for existing ACM certificate for $DOMAIN in $AWS_REGION"

EXISTING_ARN=$(aws acm list-certificates \
  --region "$AWS_REGION" \
  --query "CertificateSummaryList[?DomainName=='${DOMAIN}'].CertificateArn" \
  --output text | head -1)

if [[ -n "$EXISTING_ARN" ]]; then
  echo "Certificate already exists: $EXISTING_ARN"
  STATUS=$(aws acm describe-certificate \
    --region "$AWS_REGION" \
    --certificate-arn "$EXISTING_ARN" \
    --query 'Certificate.Status' --output text)
  echo "Status: $STATUS"
  echo "$EXISTING_ARN" > "$STATE_DIR/certificate-arn"
  echo ""
  echo "If status is PENDING_VALIDATION, run 03-create-dns-validation-records.sh next."
  echo "If status is ISSUED, you can skip ahead to 05-create-wildcard-dns.sh."
  exit 0
fi

echo "==> Requesting ACM certificate for $DOMAIN and *.$DOMAIN"

CERT_ARN=$(aws acm request-certificate \
  --region "$AWS_REGION" \
  --domain-name "$DOMAIN" \
  --subject-alternative-names "*.$DOMAIN" \
  --validation-method DNS \
  --query 'CertificateArn' --output text)

echo "Certificate requested: $CERT_ARN"
echo "$CERT_ARN" > "$STATE_DIR/certificate-arn"

echo ""
echo "Status: PENDING_VALIDATION"
echo "Run 03-create-dns-validation-records.sh next to create the DNS validation records."
