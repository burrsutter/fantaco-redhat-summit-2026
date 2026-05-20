#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

ROLE_NAME="route-lb-haproxy"
PROFILE_NAME="route-lb-haproxy"

echo "==> Checking for existing IAM role: $ROLE_NAME"

if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "IAM role already exists: $ROLE_NAME"
else
  echo "==> Creating IAM role: $ROLE_NAME"

  TRUST_POLICY=$(cat <<'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST
)

  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "EC2 role for route-lb HAProxy instance"

  echo "Role created."
fi

echo "==> Attaching managed policies"
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || true
echo "Managed policies attached."

echo "==> Adding inline S3 read policy for $CONFIG_BUCKET"
S3_POLICY=$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${CONFIG_BUCKET}",
        "arn:aws:s3:::${CONFIG_BUCKET}/*"
      ]
    }
  ]
}
POLICY
)

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "route-lb-s3-read" \
  --policy-document "$S3_POLICY"
echo "Inline policy attached."

echo "==> Checking for instance profile: $PROFILE_NAME"
if aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" &>/dev/null; then
  echo "Instance profile already exists: $PROFILE_NAME"
else
  echo "==> Creating instance profile"
  aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME"

  echo "==> Adding role to instance profile"
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$PROFILE_NAME" \
    --role-name "$ROLE_NAME"

  echo "Waiting 10s for IAM propagation..."
  sleep 10
fi

PROFILE_ARN=$(aws iam get-instance-profile \
  --instance-profile-name "$PROFILE_NAME" \
  --query 'InstanceProfile.Arn' --output text)

echo "$PROFILE_ARN" > "$STATE_DIR/instance-profile-arn"

echo ""
echo "State files written:"
echo "  $STATE_DIR/instance-profile-arn = $PROFILE_ARN"
