#!/usr/bin/env bash
# 07c-deploy-broker.sh — Upload broker to S3, deploy to EC2, restart service
#
# Packages the broker source, uploads to S3, then deploys to the EC2 instance
# via SSM. Handles the correct service directory (/opt/route-lb-broker/),
# DB migration (deletes broker.db so schema changes take effect), and
# reloads routes from the current CSV.
#
# Usage:
#   ./07c-deploy-broker.sh              # deploy and reload routes
#   ./07c-deploy-broker.sh --keep-db    # deploy without wiping the DB
#
# The --keep-db flag skips deleting broker.db. Use this when deploying
# code-only changes that don't modify the DB schema.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

KEEP_DB=false
if [[ "${1:-}" == "--keep-db" ]]; then
  KEEP_DB=true
fi

BROKER_DIR="$SCRIPT_DIR/../broker"

# ── Step 1: Package and upload to S3 ──────────────────────────────
echo "==> Packaging broker..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/broker/pages"
cp "$BROKER_DIR/package.json" "$BROKER_DIR/package-lock.json" "$TMPDIR/broker/"
cp "$BROKER_DIR/server.js" "$BROKER_DIR/app.js" "$BROKER_DIR/db.js" "$BROKER_DIR/routes-csv.js" "$TMPDIR/broker/"
cp "$BROKER_DIR/pages/"*.html "$TMPDIR/broker/pages/"

tar -czf "$TMPDIR/broker.tar.gz" -C "$TMPDIR" broker/

echo "==> Uploading to s3://$CONFIG_BUCKET/route-lb/broker.tar.gz"
aws s3 cp "$TMPDIR/broker.tar.gz" "s3://$CONFIG_BUCKET/route-lb/broker.tar.gz" --region "$AWS_REGION"

# ── Step 2: Find the EC2 instance ─────────────────────────────────
echo "==> Finding ${EC2_TAG_NAME} EC2 instance..."
EC2_ID=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters Name=tag:Name,Values="${EC2_TAG_NAME}" Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [[ -z "$EC2_ID" || "$EC2_ID" == "None" ]]; then
  echo "ERROR: No running ${EC2_TAG_NAME} instance found." >&2
  exit 1
fi
echo "    Instance: $EC2_ID"

# ── Step 3: Deploy via SSM ────────────────────────────────────────
echo "==> Deploying to $EC2_ID via SSM..."

DB_CMD=""
if [[ "$KEEP_DB" == "false" ]]; then
  DB_CMD="rm -f /var/lib/route-lb/broker.db && "
  echo "    DB: will be deleted (schema migration)"
else
  echo "    DB: keeping existing (--keep-db)"
fi

COMMAND_ID=$(aws ssm send-command --region "$AWS_REGION" \
  --instance-ids "$EC2_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["cd /opt && aws s3 cp s3://'"$CONFIG_BUCKET"'/route-lb/broker.tar.gz broker.tar.gz --region '"$AWS_REGION"' && tar xzf broker.tar.gz && cp -r broker/* route-lb-broker/ && cd route-lb-broker && npm install --production 2>&1 | tail -3 && '"$DB_CMD"'systemctl restart route-lb-broker && sleep 3 && systemctl is-active route-lb-broker && source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && curl -s -X POST http://localhost:3000/admin/reset"]}' \
  --query 'Command.CommandId' --output text)

echo "    SSM command: $COMMAND_ID"
echo "    Waiting..."
sleep 12

SSM_STATUS=$(aws ssm get-command-invocation --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" --instance-id "$EC2_ID" \
  --query 'Status' --output text 2>/dev/null || echo "Unknown")

SSM_OUTPUT=$(aws ssm get-command-invocation --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" --instance-id "$EC2_ID" \
  --query 'StandardOutputContent' --output text 2>/dev/null || echo "")

SSM_STDERR=$(aws ssm get-command-invocation --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" --instance-id "$EC2_ID" \
  --query 'StandardErrorContent' --output text 2>/dev/null || echo "")

if [[ "$SSM_STATUS" == "Success" ]]; then
  echo "==> Deploy successful"
  echo "$SSM_OUTPUT" | tail -5 | sed 's/^/    /'
else
  echo "==> Deploy FAILED (status: $SSM_STATUS)" >&2
  echo "    stdout: $SSM_OUTPUT" | tail -10
  echo "    stderr: $SSM_STDERR" | tail -10
  echo "    Check: aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $EC2_ID"
  exit 1
fi

# ── Step 4: Verify ────────────────────────────────────────────────
echo ""
echo "==> Verifying status API..."
STATUS=$(curl -sk "https://${DOMAIN}/status/api" 2>/dev/null || echo '{}')
echo "$STATUS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
s = d.get('stats', {})
r = d.get('routes', [])
print(f'    Routes: {s.get(\"total\", 0)} ({s.get(\"assigned\", 0)} assigned, {s.get(\"available\", 0)} available)')
print(f'    Audience: {s.get(\"audience_id\", \"—\")}')
if r:
    ns = r[0].get('namespace', '')
    print(f'    Namespace column: {\"yes\" if ns else \"no\"}')
    masked = '••' in r[0].get('backend_host', '')
    print(f'    Backend masked: {\"yes\" if masked else \"no\"}')
" 2>/dev/null || echo "    (could not parse status API)"
echo ""
echo "    Status board: https://${DOMAIN}/status"
