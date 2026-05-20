#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

echo "==> Checking for existing S3 bucket: $CONFIG_BUCKET"

if aws s3api head-bucket --bucket "$CONFIG_BUCKET" 2>/dev/null; then
  echo "Bucket already exists: $CONFIG_BUCKET"
else
  echo "==> Creating S3 bucket: $CONFIG_BUCKET in $AWS_REGION"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$CONFIG_BUCKET" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$CONFIG_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi
  echo "Bucket created."
fi

echo "==> Enabling versioning on $CONFIG_BUCKET"
aws s3api put-bucket-versioning --bucket "$CONFIG_BUCKET" \
  --versioning-configuration Status=Enabled

echo "==> Uploading initial route catalog"
ROUTES_FILE="$SCRIPT_DIR/../routes.example.csv"
if [[ ! -f "$ROUTES_FILE" ]]; then
  echo "ERROR: $ROUTES_FILE not found." >&2
  exit 1
fi

aws s3 cp "$ROUTES_FILE" "s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"
echo "Uploaded to s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"

echo ""
echo "Verify with:"
echo "  aws s3 ls s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY"
