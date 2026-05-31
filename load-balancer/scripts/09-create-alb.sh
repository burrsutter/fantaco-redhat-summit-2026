#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

# --- Read state from previous scripts ---
EC2_INSTANCE_ID=$(cat "$STATE_DIR/ec2-instance-id" 2>/dev/null || true)
ALB_SG_ID=$(cat "$STATE_DIR/alb-sg-id" 2>/dev/null || true)
CERT_ARN=$(cat "$STATE_DIR/certificate-arn" 2>/dev/null || true)
VPC_ID=$(cat "$STATE_DIR/vpc-id" 2>/dev/null || true)

if [[ -z "$EC2_INSTANCE_ID" ]]; then
  echo "ERROR: No ec2-instance-id found. Run 08-launch-ec2.sh first." >&2
  exit 1
fi
if [[ -z "$ALB_SG_ID" ]]; then
  echo "ERROR: No alb-sg-id found. Run 06-create-security-groups.sh first." >&2
  exit 1
fi
if [[ -z "$CERT_ARN" ]]; then
  echo "ERROR: No certificate-arn found. Run 02-request-acm-certificate.sh first." >&2
  exit 1
fi
if [[ -z "$VPC_ID" ]]; then
  echo "ERROR: No vpc-id found. Run 06-create-security-groups.sh first." >&2
  exit 1
fi

# --- Discover public subnets (need >= 2 AZs for ALB) ---
echo "==> Discovering public subnets in VPC $VPC_ID"
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[*].SubnetId' --output text)

SUBNET_COUNT=$(echo "$SUBNET_IDS" | wc -w | tr -d ' ')
if [[ "$SUBNET_COUNT" -lt 2 ]]; then
  echo "ERROR: ALB requires subnets in at least 2 AZs. Found $SUBNET_COUNT." >&2
  exit 1
fi
echo "Using $SUBNET_COUNT subnets: $SUBNET_IDS"

# TG_NAME and ALB_NAME are set by 00-env.sh from site config

# --- Target Group ---
echo "==> Checking for existing target group: $TG_NAME"
TG_ARN=$(aws elbv2 describe-target-groups \
  --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)

if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  echo "Target group already exists: $TG_ARN"
else
  echo "==> Creating target group"
  TG_ARN=$(aws elbv2 create-target-group \
    --name "$TG_NAME" \
    --protocol HTTP \
    --port "$HAPROXY_PORT" \
    --vpc-id "$VPC_ID" \
    --target-type instance \
    --health-check-protocol HTTP \
    --health-check-port "8081" \
    --health-check-path "/ready" \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
  echo "Created target group: $TG_ARN"
fi
echo "$TG_ARN" > "$STATE_DIR/target-group-arn"

# --- Register EC2 instance ---
echo "==> Registering instance $EC2_INSTANCE_ID with target group"
aws elbv2 register-targets \
  --target-group-arn "$TG_ARN" \
  --targets "Id=$EC2_INSTANCE_ID"
echo "Instance registered."

# --- ALB ---
echo "==> Checking for existing ALB: $ALB_NAME"
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)

if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
  echo "ALB already exists: $ALB_ARN"
else
  echo "==> Creating ALB"
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "$ALB_NAME" \
    --type application \
    --scheme internet-facing \
    --subnets $SUBNET_IDS \
    --security-groups "$ALB_SG_ID" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
  echo "Created ALB: $ALB_ARN"

  echo "==> Waiting for ALB to become active..."
  aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"
  echo "ALB is active."
fi
echo "$ALB_ARN" > "$STATE_DIR/alb-arn"

# --- Read ALB DNS info ---
ALB_INFO=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].[DNSName,CanonicalHostedZoneId]' --output text)
ALB_DNS_NAME=$(echo "$ALB_INFO" | awk '{print $1}')
ALB_HOSTED_ZONE_ID=$(echo "$ALB_INFO" | awk '{print $2}')

echo "$ALB_DNS_NAME" > "$STATE_DIR/alb-dns-name"
echo "$ALB_HOSTED_ZONE_ID" > "$STATE_DIR/alb-hosted-zone-id"

# --- HTTPS Listener (443) ---
echo "==> Checking for existing HTTPS listener"
HTTPS_LISTENER=$(aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`443\`].ListenerArn" --output text)

if [[ -n "$HTTPS_LISTENER" && "$HTTPS_LISTENER" != "None" ]]; then
  echo "HTTPS listener already exists: $HTTPS_LISTENER"
else
  echo "==> Creating HTTPS listener (443 → target group)"
  aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTPS \
    --port 443 \
    --certificates "CertificateArn=$CERT_ARN" \
    --default-actions "Type=forward,TargetGroupArn=$TG_ARN"
  echo "HTTPS listener created."
fi

# --- HTTP Listener (80 → redirect to HTTPS) ---
echo "==> Checking for existing HTTP listener"
HTTP_LISTENER=$(aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --query "Listeners[?Port==\`80\`].ListenerArn" --output text)

if [[ -n "$HTTP_LISTENER" && "$HTTP_LISTENER" != "None" ]]; then
  echo "HTTP listener already exists: $HTTP_LISTENER"
else
  echo "==> Creating HTTP listener (80 → redirect to HTTPS)"
  aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'
  echo "HTTP redirect listener created."
fi

echo ""
echo "State files written:"
echo "  $STATE_DIR/target-group-arn   = $TG_ARN"
echo "  $STATE_DIR/alb-arn            = $ALB_ARN"
echo "  $STATE_DIR/alb-dns-name       = $ALB_DNS_NAME"
echo "  $STATE_DIR/alb-hosted-zone-id = $ALB_HOSTED_ZONE_ID"
echo ""
echo "Next step: run 10-create-wildcard-dns.sh"
