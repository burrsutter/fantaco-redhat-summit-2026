#!/usr/bin/env bash
# 09-broker-reset.sh — Download routes.csv from S3, sync HAProxy, and reset the broker
#
# Usage:
#   ./09-broker-reset.sh              # use routes.csv already in S3
#   ./09-broker-reset.sh routes.csv   # upload a local file first, then reset
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

LOCAL_CSV="${1:-}"

# Upload local CSV if provided
if [[ -n "$LOCAL_CSV" ]]; then
  if [[ ! -f "$LOCAL_CSV" ]]; then
    echo "ERROR: File not found: $LOCAL_CSV" >&2
    exit 1
  fi
  echo "==> Uploading $LOCAL_CSV to s3://${CONFIG_BUCKET}/${ROUTE_CATALOG_KEY}"
  aws s3 cp "$LOCAL_CSV" "s3://${CONFIG_BUCKET}/${ROUTE_CATALOG_KEY}" --region "$AWS_REGION"
fi

# Find EC2 instance
echo "==> Looking up ${EC2_TAG_NAME} instance"
EC2_INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters Name=tag:Name,Values="${EC2_TAG_NAME}" Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [[ -z "$EC2_INSTANCE_ID" || "$EC2_INSTANCE_ID" == "None" ]]; then
  echo "ERROR: No running ${EC2_TAG_NAME} instance found." >&2
  exit 1
fi
echo "  Instance: $EC2_INSTANCE_ID"

# Trigger reset via SSM
echo "==> Sending reset command via SSM"
COMMAND_ID=$(aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && /usr/local/bin/route-lb-sync && curl -s -X POST http://localhost:3000/admin/reset"]}' \
  --query 'Command.CommandId' --output text)

echo "  Command: $COMMAND_ID"
echo "  Waiting for completion..."
sleep 8

SSM_STATUS=$(aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_INSTANCE_ID" \
  --query 'Status' --output text 2>/dev/null || echo "Unknown")

SSM_OUTPUT=$(aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_INSTANCE_ID" \
  --query 'StandardOutputContent' --output text 2>/dev/null || echo "")

if [[ "$SSM_STATUS" == "Success" ]]; then
  echo "==> Broker reset OK"
  [[ -n "$SSM_OUTPUT" ]] && echo "$SSM_OUTPUT" | tail -3
else
  echo "==> SSM status: $SSM_STATUS"
  echo "Check manually:"
  echo "  aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $EC2_INSTANCE_ID --region $AWS_REGION"
  exit 1
fi
