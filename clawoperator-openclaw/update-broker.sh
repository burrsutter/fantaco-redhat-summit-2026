#!/usr/bin/env bash
# update-broker.sh — Standalone Route-LB broker update
#
# Reads existing audience routes from the cluster, generates routes.csv,
# uploads to S3, updates EC2 router DNS, and triggers a broker reset.
#
# This is the same logic as audience-reset.sh Phase 7, but standalone so
# you can retry the broker update without re-running the full reset.
#
# Usage:
#   ./update-broker.sh              # all agentic-user namespaces
#   ./update-broker.sh 1 22         # user1 through user22
#   ./update-broker.sh 3            # just user3

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Route-LB broker config ─────────────────────────────────────────
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
BROKER_S3_BUCKET="${BROKER_S3_BUCKET:-yougetaclaw-route-lb-config}"
BROKER_S3_KEY="${BROKER_S3_KEY:-route-lb/routes.csv}"
BROKER_AWS_REGION="${BROKER_AWS_REGION:-us-east-1}"

# ══════════════════════════════════════════════════════════════════════
# Pre-flight checks
# ══════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Route-LB Broker Update${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""

# Check oc login
if ! oc whoami &>/dev/null; then
  echo -e "${RED}Error: Not logged in to OpenShift. Run 'oc login' first.${RESET}"
  exit 1
fi
echo -e "OpenShift: ${CYAN}$(oc whoami)${RESET}"

# Check AWS session
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS session expired or not configured. Run 'aws login' or refresh credentials.${RESET}"
  exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
echo -e "AWS account: ${CYAN}${AWS_ACCOUNT}${RESET}"

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  # No args — discover all agentic-user namespaces on cluster
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(oc get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)
  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No ${NAMESPACE_PREFIX}* namespaces found on cluster.${RESET}"
    exit 1
  fi
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo -e "${RED}Error: start ($START) must be <= end ($END)${RESET}"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # all agentic-user namespaces"
  echo "       $0 <start> [end]  # agentic-user<start> through agentic-user<end>"
  exit 1
fi

echo ""
echo -e "Namespaces: ${CYAN}${#NAMESPACES[@]}${RESET}"
for NS in "${NAMESPACES[@]}"; do
  echo -e "  - ${DIM}${NS}${RESET}"
done

# ── Derive apps domain ──────────────────────────────────────────────
APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
if [[ -z "$APPS_DOMAIN" ]]; then
  echo -e "${RED}Error: Could not derive apps domain from ingress config.${RESET}"
  exit 1
fi
echo -e "Apps domain: ${CYAN}${APPS_DOMAIN}${RESET}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Read existing audience routes from the cluster
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Reading audience routes from cluster ---${RESET}"

declare -a AUDIENCE_HOSTS=()
declare -a AUDIENCE_LABELS=()
SKIP_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  # Extract user number from namespace name
  USER_NUM="${NS#"$NAMESPACE_PREFIX"}"

  HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$HOST" ]]; then
    AUDIENCE_HOSTS+=("$HOST")
    AUDIENCE_LABELS+=("$USER_NUM")
    echo -e "  ${GREEN}✓${RESET} ${NS}: ${DIM}${HOST}${RESET}"
  else
    echo -e "  ${YELLOW}⚠${RESET} ${NS}: no audience route found — skipping"
    SKIP_COUNT=$((SKIP_COUNT + 1))
  fi
done

echo ""
if [[ ${#AUDIENCE_HOSTS[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No audience routes found across ${#NAMESPACES[@]} namespaces. Nothing to update.${RESET}"
  exit 1
fi
echo -e "Found ${CYAN}${#AUDIENCE_HOSTS[@]}${RESET} routes (${SKIP_COUNT} skipped)"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Generate routes.csv
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Generating routes.csv ---${RESET}"

ROUTES_CSV=$(mktemp)
echo "# public_host,openshift_route_host,enabled,namespace" > "$ROUTES_CSV"
for idx in "${!AUDIENCE_HOSTS[@]}"; do
  HOST="${AUDIENCE_HOSTS[$idx]}"
  PREFIX="${HOST%%.*}"
  NS_LABEL="${NAMESPACE_PREFIX}${AUDIENCE_LABELS[$idx]}"
  echo "${PREFIX}.${BROKER_DOMAIN},${HOST},true,${NS_LABEL}" >> "$ROUTES_CSV"
done

echo "  Generated ${#AUDIENCE_HOSTS[@]} routes:"
while IFS= read -r line; do echo "    $line"; done < "$ROUTES_CSV"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Upload to S3
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Uploading to S3 ---${RESET}"
echo "  s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}"

if aws s3 cp "$ROUTES_CSV" "s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}" --region "$BROKER_AWS_REGION" 2>/dev/null; then
  echo -e "  ${GREEN}✓ S3 upload OK${RESET}"
else
  echo -e "  ${RED}✗ S3 upload failed${RESET}"
  rm -f "$ROUTES_CSV"
  exit 1
fi
rm -f "$ROUTES_CSV"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Update EC2 router DNS + trigger broker reset via SSM
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Updating EC2 broker ---${RESET}"

EC2_INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$BROKER_AWS_REGION" \
  --filters Name=tag:Name,Values=route-lb-haproxy Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)

if [[ -z "$EC2_INSTANCE_ID" || "$EC2_INSTANCE_ID" == "None" ]]; then
  echo -e "${RED}Error: No route-lb-haproxy EC2 instance found.${RESET}"
  echo "  Check AWS console or tag the instance with Name=route-lb-haproxy"
  exit 1
fi
echo -e "  EC2 instance: ${CYAN}${EC2_INSTANCE_ID}${RESET}"

# Update OPENSHIFT_ROUTER_DNS on EC2 to point to the current cluster
CURRENT_ROUTER_DNS="router-default.${APPS_DOMAIN}"
echo -e "  Updating router DNS to: ${CYAN}${CURRENT_ROUTER_DNS}${RESET}"
aws ssm send-command \
  --region "$BROKER_AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[\"sed -i 's|OPENSHIFT_ROUTER_DNS=.*|OPENSHIFT_ROUTER_DNS=${CURRENT_ROUTER_DNS}|' /etc/route-lb/env\",\"sed -i 's|server openshift-router [^ ]*:443|server openshift-router ${CURRENT_ROUTER_DNS}:443|' /etc/haproxy/haproxy.cfg\",\"systemctl reload haproxy\"]" \
  --query 'Command.CommandId' --output text &>/dev/null || true
sleep 3

# Trigger broker reset
echo "  Triggering broker reset via SSM..."
COMMAND_ID=$(aws ssm send-command \
  --region "$BROKER_AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && /usr/local/bin/route-lb-sync && curl -s -X POST http://localhost:3000/admin/reset"]}' \
  --query 'Command.CommandId' --output text 2>/dev/null || true)

if [[ -z "$COMMAND_ID" || "$COMMAND_ID" == "None" ]]; then
  echo -e "  ${RED}✗ SSM send-command failed.${RESET}"
  echo "    Manual fallback:"
  echo "    aws ssm start-session --target $EC2_INSTANCE_ID"
  echo "    curl -s -X POST http://localhost:3000/admin/reset"
  exit 1
fi

echo -e "  SSM command: ${DIM}${COMMAND_ID}${RESET}"
echo "  Waiting for broker reset..."
sleep 8

SSM_STATUS=$(aws ssm get-command-invocation \
  --region "$BROKER_AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_INSTANCE_ID" \
  --query 'Status' --output text 2>/dev/null || echo "Unknown")
SSM_OUTPUT=$(aws ssm get-command-invocation \
  --region "$BROKER_AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$EC2_INSTANCE_ID" \
  --query 'StandardOutputContent' --output text 2>/dev/null || echo "")

if [[ "$SSM_STATUS" == "Success" ]]; then
  echo -e "  ${GREEN}✓ Broker reset OK${RESET}"
  [[ -n "$SSM_OUTPUT" ]] && echo "$SSM_OUTPUT" | tail -2 | sed 's/^/    /'
else
  echo -e "  ${YELLOW}⚠ SSM status: ${SSM_STATUS}${RESET}"
  echo "    Check manually:"
  echo "    aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $EC2_INSTANCE_ID"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════
# Verify broker status
# ══════════════════════════════════════════════════════════════════════
echo -e "${BOLD}--- Verifying broker status ---${RESET}"
echo "  https://${BROKER_DOMAIN}/status"

STATUS_JSON=$(curl -s --max-time 10 "https://${BROKER_DOMAIN}/status/api" 2>/dev/null || true)
if [[ -n "$STATUS_JSON" ]]; then
  # Parse stats from /status/api JSON (structure: { stats: { assigned, available, ... }, routes: [...] })
  TOTAL=$(echo "$STATUS_JSON" | grep -o '"total":[0-9]*' | head -1 | grep -o '[0-9]*' || true)
  ASSIGNED=$(echo "$STATUS_JSON" | grep -o '"assigned":[0-9]*' | head -1 | grep -o '[0-9]*' || true)
  AVAILABLE=$(echo "$STATUS_JSON" | grep -o '"available":[0-9]*' | head -1 | grep -o '[0-9]*' || true)

  if [[ -n "$TOTAL" ]]; then
    if [[ "$TOTAL" -eq "${#AUDIENCE_HOSTS[@]}" ]]; then
      echo -e "  ${GREEN}✓ Broker has ${TOTAL} routes (${ASSIGNED:-0} assigned, ${AVAILABLE:-0} available) — matches expected ${#AUDIENCE_HOSTS[@]}${RESET}"
    else
      echo -e "  ${YELLOW}⚠ Broker has ${TOTAL} routes but expected ${#AUDIENCE_HOSTS[@]}${RESET}"
    fi
  else
    # Couldn't parse JSON, show raw response (truncated)
    echo -e "  Response: ${DIM}${STATUS_JSON:0:200}${RESET}"
  fi
else
  echo -e "  ${YELLOW}⚠ Could not reach ${BROKER_DOMAIN}/status — check manually${RESET}"
fi

echo ""
echo -e "${GREEN}${BOLD}Done.${RESET}"
