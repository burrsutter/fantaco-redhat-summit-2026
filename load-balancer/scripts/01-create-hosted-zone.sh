#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

echo "==> Checking for existing hosted zone: $DOMAIN"

ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text | head -1 | sed 's|/hostedzone/||')

if [[ -n "$ZONE_ID" ]]; then
  echo "Hosted zone already exists: $ZONE_ID"
else
  echo "==> Creating hosted zone for $DOMAIN"
  CREATE_OUTPUT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN" \
    --caller-reference "route-lb-$(date +%s)" \
    --output json)

  ZONE_ID=$(echo "$CREATE_OUTPUT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')
  echo "Created hosted zone: $ZONE_ID"
fi

echo "$ZONE_ID" > "$STATE_DIR/hosted-zone-id"
echo "Zone ID saved to $STATE_DIR/hosted-zone-id"

echo ""
echo "==> Name servers for $DOMAIN:"
aws route53 get-hosted-zone --id "$ZONE_ID" \
  --query 'DelegationSet.NameServers' --output table

echo ""
echo "If $DOMAIN is registered outside Route 53, update the registrar's"
echo "name servers to the values shown above."
