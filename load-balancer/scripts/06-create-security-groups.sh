#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

echo "==> Discovering default VPC"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: No default VPC found in $AWS_REGION." >&2
  exit 1
fi
echo "Default VPC: $VPC_ID"
echo "$VPC_ID" > "$STATE_DIR/vpc-id"

# --- ALB Security Group ---
ALB_SG_NAME="route-lb-alb"
echo "==> Checking for existing ALB security group: $ALB_SG_NAME"

ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="$ALB_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ -n "$ALB_SG_ID" && "$ALB_SG_ID" != "None" ]]; then
  echo "ALB security group already exists: $ALB_SG_ID"
else
  echo "==> Creating ALB security group"
  ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name "$ALB_SG_NAME" \
    --description "ALB SG for route-lb - allows HTTPS from internet" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress \
    --group-id "$ALB_SG_ID" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0

  aws ec2 authorize-security-group-ingress \
    --group-id "$ALB_SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0

  echo "Created ALB security group: $ALB_SG_ID"
fi
echo "$ALB_SG_ID" > "$STATE_DIR/alb-sg-id"

# --- HAProxy Security Group ---
HAPROXY_SG_NAME="route-lb-haproxy"
echo "==> Checking for existing HAProxy security group: $HAPROXY_SG_NAME"

HAPROXY_SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values="$HAPROXY_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ -n "$HAPROXY_SG_ID" && "$HAPROXY_SG_ID" != "None" ]]; then
  echo "HAProxy security group already exists: $HAPROXY_SG_ID"
else
  echo "==> Creating HAProxy security group"
  HAPROXY_SG_ID=$(aws ec2 create-security-group \
    --group-name "$HAPROXY_SG_NAME" \
    --description "HAProxy SG for route-lb - allows traffic from ALB" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)

  aws ec2 authorize-security-group-ingress \
    --group-id "$HAPROXY_SG_ID" \
    --protocol tcp --port "$HAPROXY_PORT" \
    --source-group "$ALB_SG_ID"

  echo "Created HAProxy security group: $HAPROXY_SG_ID"
fi
echo "$HAPROXY_SG_ID" > "$STATE_DIR/haproxy-sg-id"

echo ""
echo "State files written:"
echo "  $STATE_DIR/vpc-id        = $VPC_ID"
echo "  $STATE_DIR/alb-sg-id     = $ALB_SG_ID"
echo "  $STATE_DIR/haproxy-sg-id = $HAPROXY_SG_ID"
