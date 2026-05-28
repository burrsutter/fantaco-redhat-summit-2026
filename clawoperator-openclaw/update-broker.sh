#!/usr/bin/env bash
# update-broker.sh — Rebuild routes.csv from live cluster routes and update the EC2 broker
#
# Discovers all audience routes on the cluster, generates routes.csv,
# uploads to S3, triggers a broker reload via SSM, and prints the
# share URL + QR code for the audience.
#
# Usage:
#   ./update-broker.sh                          # discover routes, keep existing audience code
#   ./update-broker.sh --audience-code abc12     # set a specific audience code
#   ./update-broker.sh --rotate-status-key       # also rotate the STATUS_KEY on EC2
#
# Called by:
#   - audience-reset.sh (with --audience-code and --rotate-status-key)
#   - extend-cluster.sh (without --rotate-status-key, to preserve session state)
#   - directly, to manually re-sync broker with cluster state
#
# Environment variables:
#   NAMESPACE_PREFIX    — namespace prefix (default: agentic-user)
#   BROKER_DOMAIN       — public broker domain (default: yougetaclaw.com)
#   BROKER_S3_BUCKET    — S3 bucket for routes.csv (default: yougetaclaw-route-lb-config)
#   BROKER_S3_KEY       — S3 key for routes.csv (default: route-lb/routes.csv)
#   BROKER_AWS_REGION   — AWS region for S3/EC2/SSM (default: us-east-1)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
if [[ -z "$CLUSTER_GUID" ]]; then
  echo "Error: could not extract cluster GUID from 'oc cluster-info'" >&2
  exit 1
fi

BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
BROKER_S3_BUCKET="${BROKER_S3_BUCKET:-yougetaclaw-route-lb-config}"
BROKER_S3_KEY="${BROKER_S3_KEY:-route-lb/routes.csv}"
BROKER_AWS_REGION="${BROKER_AWS_REGION:-us-east-1}"

# ── Source .env (for password display in summary) ──
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
STUDENT_OPENCLAW_PASSWORD="${STUDENT_OPENCLAW_PASSWORD:-}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ────────────────────────────────────────────────
AUDIENCE_CODE=""
ROTATE_STATUS_KEY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audience-code)
      AUDIENCE_CODE="$2"
      shift 2
      ;;
    --rotate-status-key)
      ROTATE_STATUS_KEY=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--audience-code CODE] [--rotate-status-key]"
      echo ""
      echo "  --audience-code CODE   Set the audience code (saved to .state/<cluster-guid>/broker.env)"
      echo "  --rotate-status-key    Rotate the STATUS_KEY on the EC2 broker"
      echo ""
      echo "With no arguments, discovers all audience routes on the cluster,"
      echo "rebuilds routes.csv, uploads to S3, and reloads the broker."
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'"
      echo "Usage: $0 [--audience-code CODE] [--rotate-status-key]"
      exit 1
      ;;
  esac
done

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Check AWS session ───────────────────────────────────────────────
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS session expired or not configured. Run 'aws login' first.${RESET}"
  exit 1
fi

# ── Detect apps domain ──────────────────────────────────────────────
APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
if [[ -z "$APPS_DOMAIN" ]]; then
  echo "Error: Could not detect APPS_DOMAIN from cluster."
  exit 1
fi

# ── Load existing broker state if no audience code provided ─────────
BROKER_STATE_FILE="${SCRIPT_DIR}/.state/${CLUSTER_GUID}/broker.env"
STATUS_KEY=""
if [[ -z "$AUDIENCE_CODE" && -f "$BROKER_STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BROKER_STATE_FILE"
fi
if [[ -z "$AUDIENCE_CODE" ]]; then
  echo -e "${YELLOW}Note: No audience code set. Share URL will not be available.${RESET}"
  echo -e "${DIM}Use --audience-code CODE to set one, or run audience-reset.sh first.${RESET}"
  echo ""
fi

echo -e "${BOLD}=== Update Route-LB Broker ===${RESET}"
echo -e "Logged in as: ${CYAN}$(oc whoami)${RESET}"
echo -e "Apps domain:  ${CYAN}${APPS_DOMAIN}${RESET}"
echo -e "Broker:       ${CYAN}${BROKER_DOMAIN}${RESET}"
echo ""

# ── Step 1: Discover audience routes and generate routes.csv ────────
echo -e "${BOLD}--- Step 1: Generate routes.csv from cluster ---${RESET}"

NAMESPACES=()
while IFS= read -r ns; do
  NAMESPACES+=("$ns")
done < <(oc get ns --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)

if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
  echo "Error: No ${NAMESPACE_PREFIX}* namespaces found on cluster."
  exit 1
fi

ROUTES_CSV=$(mktemp)
echo "# public_host,openshift_route_host,enabled,namespace" > "$ROUTES_CSV"
ROUTE_COUNT=0
SKIP_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  ROUTE_HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$ROUTE_HOST" ]]; then
    PREFIX="${ROUTE_HOST%%.*}"
    echo "${PREFIX}.${BROKER_DOMAIN},${ROUTE_HOST},true,${NS}" >> "$ROUTES_CSV"
    ((ROUTE_COUNT++))
  else
    echo -e "  ${YELLOW}⚠${RESET} No audience route in $NS — skipping"
    ((SKIP_COUNT++))
  fi
done

echo "  Found ${GREEN}${ROUTE_COUNT}${RESET} audience routes across ${#NAMESPACES[@]} namespaces"
if [[ $SKIP_COUNT -gt 0 ]]; then
  echo "  Skipped: ${SKIP_COUNT}"
fi
echo ""
echo -e "  ${DIM}routes.csv:${RESET}"
while IFS= read -r line; do echo "    $line"; done < "$ROUTES_CSV"
echo ""

if [[ $ROUTE_COUNT -eq 0 ]]; then
  echo "Error: No audience routes found. Nothing to update."
  rm -f "$ROUTES_CSV"
  exit 1
fi

# ── Step 2: Upload to S3 ───────────────────────────────────────────
echo -e "${BOLD}--- Step 2: Upload routes.csv to S3 ---${RESET}"
echo "  s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}"
if aws s3 cp "$ROUTES_CSV" "s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}" --region "$BROKER_AWS_REGION" 2>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} S3 upload OK"
else
  echo -e "  ${RED}✗ S3 upload failed${RESET}"
  echo "  Check: aws login session valid? Bucket exists?"
  rm -f "$ROUTES_CSV"
  exit 1
fi
rm -f "$ROUTES_CSV"
echo ""

# ── Step 3: Update EC2 broker via SSM ──────────────────────────────
echo -e "${BOLD}--- Step 3: Update EC2 broker ---${RESET}"

EC2_INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$BROKER_AWS_REGION" \
  --filters Name=tag:Name,Values=route-lb-haproxy Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)

if [[ -z "$EC2_INSTANCE_ID" || "$EC2_INSTANCE_ID" == "None" ]]; then
  echo -e "  ${YELLOW}⚠${RESET} No route-lb-haproxy EC2 instance found."
  echo "  Routes.csv is uploaded to S3 — reload the broker manually."
  exit 0
fi

echo "  EC2 instance: ${EC2_INSTANCE_ID}"

# 3a. Update OPENSHIFT_ROUTER_DNS to point to the current cluster
CURRENT_ROUTER_DNS="router-default.${APPS_DOMAIN}"
echo "  Updating router DNS to: ${CURRENT_ROUTER_DNS}"
aws ssm send-command \
  --region "$BROKER_AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[\"sed -i 's|OPENSHIFT_ROUTER_DNS=.*|OPENSHIFT_ROUTER_DNS=${CURRENT_ROUTER_DNS}|' /etc/route-lb/env\",\"sed -i 's|server openshift-router [^ ]*:443|server openshift-router ${CURRENT_ROUTER_DNS}:443|' /etc/haproxy/haproxy.cfg\",\"systemctl reload haproxy\"]" \
  --query 'Command.CommandId' --output text &>/dev/null || true
sleep 3

# 3b. Optionally rotate STATUS_KEY
if $ROTATE_STATUS_KEY; then
  STATUS_KEY=$(python3 -c "import secrets; print(secrets.token_hex(8))")
  echo "  Rotating STATUS_KEY on EC2..."
  aws ssm send-command \
    --region "$BROKER_AWS_REGION" \
    --instance-ids "$EC2_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[\"grep -q STATUS_KEY /etc/systemd/system/route-lb-broker.service && sed -i 's|Environment=STATUS_KEY=.*|Environment=STATUS_KEY=${STATUS_KEY}|' /etc/systemd/system/route-lb-broker.service || sed -i '/Environment=COOKIE_DOMAIN/a Environment=STATUS_KEY=${STATUS_KEY}' /etc/systemd/system/route-lb-broker.service\",\"systemctl daemon-reload\"]" \
    --query 'Command.CommandId' --output text &>/dev/null || true
  sleep 3
fi

# 3c. Save broker state for demo-preflight.sh and summary output
mkdir -p "${SCRIPT_DIR}/.state/${CLUSTER_GUID}"
if [[ -n "$AUDIENCE_CODE" ]]; then
  cat > "$BROKER_STATE_FILE" <<BRKEOF
AUDIENCE_CODE=${AUDIENCE_CODE}
STATUS_KEY=${STATUS_KEY}
BRKEOF
  chmod 600 "$BROKER_STATE_FILE"
fi

# 3d. Trigger broker reset: download routes.csv from S3, sync HAProxy, restart broker
echo "  Triggering broker reset..."
COMMAND_ID=$(aws ssm send-command \
  --region "$BROKER_AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && /usr/local/bin/route-lb-sync && systemctl restart route-lb-broker && sleep 2 && curl -s -X POST http://localhost:3000/admin/reset"]}' \
  --query 'Command.CommandId' --output text 2>/dev/null || true)

if [[ -n "$COMMAND_ID" && "$COMMAND_ID" != "None" ]]; then
  echo "  SSM command: $COMMAND_ID"
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
    echo -e "  ${GREEN}✓${RESET} Broker reset OK"
    [[ -n "$SSM_OUTPUT" ]] && echo "$SSM_OUTPUT" | tail -2 | sed 's/^/    /'
  else
    echo -e "  ${YELLOW}⚠${RESET} SSM status: ${SSM_STATUS}. Check manually:"
    echo "    aws ssm get-command-invocation --command-id $COMMAND_ID --instance-id $EC2_INSTANCE_ID"
  fi
else
  echo -e "  ${YELLOW}⚠${RESET} SSM send-command failed. Trigger reset manually:"
  echo "    aws ssm start-session --target $EC2_INSTANCE_ID"
  echo "    curl -s -X POST http://localhost:3000/admin/reset"
fi
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}=== Broker update complete ===${RESET}"
echo -e "  Routes: ${ROUTE_COUNT} namespaces"
echo ""

if [[ -n "$AUDIENCE_CODE" ]]; then
  if [[ -n "$STUDENT_OPENCLAW_PASSWORD" ]]; then
    echo -e "  ${BOLD}Share this URL (password: ${CYAN}${STUDENT_OPENCLAW_PASSWORD}${RESET}${BOLD}):${RESET}"
  else
    echo -e "  ${BOLD}Share this URL:${RESET}"
  fi
  echo ""
  SHARE_URL="https://${BROKER_DOMAIN}/${AUDIENCE_CODE}"
  echo -e "    ${GREEN}${SHARE_URL}${RESET}"
  echo ""

  # Generate QR code (terminal + PNG file)
  if command -v qrencode &>/dev/null; then
    qrencode -t UTF8 "$SHARE_URL"
    QR_FILE="${SCRIPT_DIR}/qr-code.png"
    qrencode -t PNG -o "$QR_FILE" -s 10 "$SHARE_URL"
    echo ""
    echo -e "  ${DIM}QR code saved to: ${QR_FILE}${RESET}"
  fi
  echo ""
  echo -e "  ${DIM}Each visitor is auto-assigned an exclusive OpenClaw instance.${RESET}"
fi

if [[ -n "${STATUS_KEY:-}" ]]; then
  echo -e "  ${DIM}Status board: https://${BROKER_DOMAIN}/status?key=${STATUS_KEY}${RESET}"
fi
echo ""

# Print direct broker URLs per namespace (admin/debug)
if [[ -n "$AUDIENCE_CODE" ]]; then
  echo -e "  ${DIM}Direct URLs (admin/debug):${RESET}"
  for NS in "${NAMESPACES[@]}"; do
    ROUTE_HOST=$(oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$ROUTE_HOST" ]]; then
      PREFIX="${ROUTE_HOST%%.*}"
      USER_NUM="${NS#${NAMESPACE_PREFIX}}"
      echo -e "    user${USER_NUM}: ${DIM}https://${PREFIX}.${BROKER_DOMAIN}${RESET}"
    fi
  done
  echo ""
fi
