#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

ZONE_ID=$(cat "$STATE_DIR/hosted-zone-id" 2>/dev/null || true)

if [[ -z "$ZONE_ID" ]]; then
  echo "ERROR: No hosted zone ID found. Run 01-create-hosted-zone.sh first." >&2
  exit 1
fi

ALB_DNS_NAME="${1:-}"
ALB_HOSTED_ZONE_ID="${2:-}"

if [[ -z "$ALB_DNS_NAME" || -z "$ALB_HOSTED_ZONE_ID" ]]; then
  echo "Usage: $0 <alb-dns-name> <alb-hosted-zone-id>"
  echo ""
  echo "Find these values with:"
  echo "  aws elbv2 describe-load-balancers --names <your-alb-name> \\"
  echo "    --query 'LoadBalancers[0].[DNSName,CanonicalHostedZoneId]' --output text"
  echo ""
  echo "Example:"
  echo "  $0 my-alb-123456.us-east-1.elb.amazonaws.com Z35SXDOTRQ7X7K"
  exit 1
fi

echo "==> Creating wildcard and root alias records for $DOMAIN"
echo "    Target ALB: $ALB_DNS_NAME"
echo "    ALB Zone:   $ALB_HOSTED_ZONE_ID"
echo ""

CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Wildcard and root alias to ALB for ${DOMAIN}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}",
          "DNSName": "dualstack.${ALB_DNS_NAME}",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}",
          "DNSName": "dualstack.${ALB_DNS_NAME}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
)

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Id' --output text)

echo "Change submitted: $CHANGE_ID"
echo "Waiting for DNS propagation..."

aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

echo "Done. DNS records are active."
echo ""
echo "Verify with:"
echo "  dig +short claw-001.${DOMAIN}"
echo "  dig +short ${DOMAIN}"
echo "  curl -I https://claw-001.${DOMAIN}/"
