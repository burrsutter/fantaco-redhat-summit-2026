#!/usr/bin/env bash
# update-broker.sh — Rebuild routes.csv from live cluster routes and update the EC2 broker
#
# Discovers all audience routes across one or more OpenShift clusters,
# generates a merged routes.csv, uploads to S3, triggers a broker reload
# via SSM, and prints the share URL + QR code for the audience.
#
# Multi-cluster mode:
#   If clusters.csv exists (see clusters.csv.example), routes are discovered
#   from all listed clusters. Otherwise, falls back to single-cluster mode
#   using the current oc context.
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
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"

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
      echo "With no arguments, discovers all audience routes on the cluster(s),"
      echo "rebuilds routes.csv, uploads to S3, and reloads the broker."
      echo ""
      echo "Multi-cluster: create clusters.csv (see clusters.csv.example) to"
      echo "discover routes from multiple clusters."
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'"
      echo "Usage: $0 [--audience-code CODE] [--rotate-status-key]"
      exit 1
      ;;
  esac
done

# ── Check AWS session ───────────────────────────────────────────────
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS session expired or not configured. Run 'aws login' first.${RESET}"
  exit 1
fi

# ── Build cluster list ──────────────────────────────────────────────
# Each entry: "cluster_id kubeconfig_path"
CLUSTER_ENTRIES=()
CLUSTER_GUIDS=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  echo -e "${BOLD}Multi-cluster mode:${RESET} reading ${CLUSTERS_CSV}"
  while IFS=, read -r cluster_id kubeconfig_path; do
    # Skip comments and empty lines
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}"
      exit 1
    fi
    # Verify oc login for this kubeconfig
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})"
      exit 1
    fi
    # Extract cluster GUID
    GUID=$(KUBECONFIG="$kubeconfig_path" oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
    if [[ -z "$GUID" ]]; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: could not extract GUID from cluster-info"
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
    CLUSTER_GUIDS+=("$GUID")
    echo -e "  ${GREEN}✓${RESET} ${cluster_id} (GUID: ${GUID})"
  done < "$CLUSTERS_CSV"
  echo ""

  if [[ ${#CLUSTER_ENTRIES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
else
  # Single-cluster fallback — use current oc context
  if ! oc whoami &>/dev/null; then
    echo "Error: Not logged in to OpenShift. Run 'oc login' first."
    exit 1
  fi
  GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
  if [[ -z "$GUID" ]]; then
    echo "Error: could not extract cluster GUID from 'oc cluster-info'" >&2
    exit 1
  fi
  CLUSTER_ENTRIES+=("default ${KUBECONFIG:-$HOME/.kube/config}")
  CLUSTER_GUIDS+=("$GUID")
fi

# ── Load existing broker state if no audience code provided ─────────
STATUS_KEY=""
if [[ -z "$AUDIENCE_CODE" ]]; then
  # Try loading from any cluster's state file
  for GUID in "${CLUSTER_GUIDS[@]}"; do
    BROKER_STATE_FILE="${SCRIPT_DIR}/.state/${GUID}/broker.env"
    if [[ -f "$BROKER_STATE_FILE" ]]; then
      # shellcheck disable=SC1090
      source "$BROKER_STATE_FILE"
      break
    fi
  done
fi
if [[ -z "$AUDIENCE_CODE" ]]; then
  echo -e "${YELLOW}Note: No audience code set. Share URL will not be available.${RESET}"
  echo -e "${DIM}Use --audience-code CODE to set one, or run audience-reset.sh first.${RESET}"
  echo ""
fi

echo -e "${BOLD}=== Update Route-LB Broker ===${RESET}"
echo -e "Broker:       ${CYAN}${BROKER_DOMAIN}${RESET}"
echo -e "Clusters:     ${CYAN}${#CLUSTER_ENTRIES[@]}${RESET}"
echo ""

# ── Step 1: Discover audience routes from all clusters ───────────────
echo -e "${BOLD}--- Step 1: Generate routes.csv from cluster(s) ---${RESET}"

ROUTES_CSV=$(mktemp)
echo "# public_host,openshift_route_host,enabled,namespace" > "$ROUTES_CSV"
TOTAL_ROUTE_COUNT=0
TOTAL_SKIP_COUNT=0

# Track per-cluster counts and namespaces for summary (parallel indexed arrays)
CLUSTER_ROUTE_COUNTS=()
ALL_CLUSTER_IDS=()
CLUSTER_NS_LISTS=()
ROUTE_HOST_CACHE_FILE=$(mktemp)  # ns,route_host lines, used by summary to avoid re-querying

DISCOVERY_TMPDIR=$(mktemp -d)
MAX_PARALLEL=10

for i in "${!CLUSTER_ENTRIES[@]}"; do
  entry="${CLUSTER_ENTRIES[$i]}"
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  ALL_CLUSTER_IDS+=("$CLUSTER_ID")

  # Get apps domain for this cluster
  APPS_DOMAIN=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  if [[ -z "$APPS_DOMAIN" ]]; then
    echo -e "  ${RED}✗${RESET} Cluster ${CLUSTER_ID}: could not detect APPS_DOMAIN"
    rm -rf "$DISCOVERY_TMPDIR"
    exit 1
  fi

  echo -e "  ${BOLD}${CLUSTER_ID}${RESET} (${APPS_DOMAIN})"

  # Discover namespaces
  NAMESPACES=()
  while IFS= read -r ns; do
    NAMESPACES+=("$ns")
  done < <(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get ns --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V)

  if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
    echo -e "    ${YELLOW}⚠${RESET} No ${NAMESPACE_PREFIX}* namespaces found"
    CLUSTER_ROUTE_COUNTS+=("0")
    CLUSTER_NS_LISTS+=("")
    continue
  fi

  # Launch parallel route queries — each job writes to its own temp file
  JOB_COUNT=0
  for NS in "${NAMESPACES[@]}"; do
    (
      host=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
      if [[ -n "$host" ]]; then
        prefix="${host%%.*}"
        echo "${prefix}.${BROKER_DOMAIN},${host},true,${NS}" > "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}"
      fi
    ) &
    JOB_COUNT=$((JOB_COUNT + 1))
    if (( JOB_COUNT >= MAX_PARALLEL )); then
      wait  # wait for current batch to finish
      JOB_COUNT=0
    fi
  done
  wait  # wait for remaining jobs in this cluster

  # Collect results for this cluster
  CLUSTER_ROUTE_COUNT=0
  NS_LIST=""
  for NS in "${NAMESPACES[@]}"; do
    if [[ -f "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}" ]]; then
      ROUTE_LINE=$(cat "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}")
      echo "$ROUTE_LINE" >> "$ROUTES_CSV"
      # Cache the route host (field 2) for the summary section
      echo "$NS,$(echo "$ROUTE_LINE" | cut -d',' -f2)" >> "$ROUTE_HOST_CACHE_FILE"
      ((CLUSTER_ROUTE_COUNT++))
      ((TOTAL_ROUTE_COUNT++))
      NS_LIST+=" $NS"
    else
      echo -e "    ${YELLOW}⚠${RESET} No audience route in $NS — skipping"
      ((TOTAL_SKIP_COUNT++))
    fi
  done

  CLUSTER_ROUTE_COUNTS+=("$CLUSTER_ROUTE_COUNT")
  CLUSTER_NS_LISTS+=("$NS_LIST")
  echo -e "    Found ${GREEN}${CLUSTER_ROUTE_COUNT}${RESET} routes across ${#NAMESPACES[@]} namespaces"
done

rm -rf "$DISCOVERY_TMPDIR"

echo ""

# Print route summary line
if [[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]]; then
  SUMMARY_PARTS=""
  for i in "${!ALL_CLUSTER_IDS[@]}"; do
    [[ -n "$SUMMARY_PARTS" ]] && SUMMARY_PARTS+=" + "
    SUMMARY_PARTS+="${CLUSTER_ROUTE_COUNTS[$i]} ${ALL_CLUSTER_IDS[$i]}"
  done
  echo -e "  Routes: ${SUMMARY_PARTS} = ${GREEN}${TOTAL_ROUTE_COUNT}${RESET} total"
else
  echo -e "  Routes: ${GREEN}${TOTAL_ROUTE_COUNT}${RESET}"
fi
if [[ $TOTAL_SKIP_COUNT -gt 0 ]]; then
  echo "  Skipped: ${TOTAL_SKIP_COUNT}"
fi
echo ""
echo -e "  ${DIM}routes.csv:${RESET}"
while IFS= read -r line; do echo "    $line"; done < "$ROUTES_CSV"
echo ""

if [[ $TOTAL_ROUTE_COUNT -eq 0 ]]; then
  echo "Error: No audience routes found. Nothing to update."
  rm -f "$ROUTES_CSV"
  exit 1
fi

# ── Step 2: Upload to S3 ───────────────────────────────────────────
echo -e "${BOLD}--- Step 2: Upload to S3 ---${RESET}"

# 2a. Upload routes.csv
echo "  s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}"
if aws s3 cp "$ROUTES_CSV" "s3://${BROKER_S3_BUCKET}/${BROKER_S3_KEY}" --region "$BROKER_AWS_REGION" 2>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} routes.csv uploaded"
else
  echo -e "  ${RED}✗ S3 upload failed${RESET}"
  echo "  Check: aws login session valid? Bucket exists?"
  rm -f "$ROUTES_CSV"
  exit 1
fi
rm -f "$ROUTES_CSV"

# 2b. Upload route-lb-sync script (ensures EC2 always has the latest version)
SYNC_SCRIPT="${SCRIPT_DIR}/../load-balancer/scripts/route-lb-sync.sh"
if [[ -f "$SYNC_SCRIPT" ]]; then
  if aws s3 cp "$SYNC_SCRIPT" "s3://${BROKER_S3_BUCKET}/route-lb/route-lb-sync" --region "$BROKER_AWS_REGION" 2>/dev/null; then
    echo -e "  ${GREEN}✓${RESET} route-lb-sync uploaded"
  else
    echo -e "  ${YELLOW}⚠${RESET} route-lb-sync upload failed (non-fatal)"
  fi
else
  echo -e "  ${DIM}route-lb-sync.sh not found — skipping${RESET}"
fi
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

# 3a. Optionally rotate STATUS_KEY
if $ROTATE_STATUS_KEY; then
  STATUS_KEY=$(python3 -c "import secrets; print(secrets.token_hex(8))")
  echo "  Rotating STATUS_KEY on EC2..."
  aws ssm send-command \
    --region "$BROKER_AWS_REGION" \
    --instance-ids "$EC2_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[\"grep -q STATUS_KEY /etc/systemd/system/route-lb-broker.service && sed -i 's|Environment=STATUS_KEY=.*|Environment=STATUS_KEY=${STATUS_KEY}|' /etc/systemd/system/route-lb-broker.service || sed -i '/Environment=COOKIE_DOMAIN/a Environment=STATUS_KEY=${STATUS_KEY}' /etc/systemd/system/route-lb-broker.service\",\"systemctl daemon-reload\"]" \
    --query 'Command.CommandId' --output text &>/dev/null || true
fi

# 3b. Save broker state for demo-preflight.sh and summary output
# Save to all cluster state dirs so any cluster's demo-preflight.sh can find it
if [[ -n "$AUDIENCE_CODE" ]]; then
  for GUID in "${CLUSTER_GUIDS[@]}"; do
    mkdir -p "${SCRIPT_DIR}/.state/${GUID}"
    cat > "${SCRIPT_DIR}/.state/${GUID}/broker.env" <<BRKEOF
AUDIENCE_CODE=${AUDIENCE_CODE}
STATUS_KEY=${STATUS_KEY}
BRKEOF
    chmod 600 "${SCRIPT_DIR}/.state/${GUID}/broker.env"
  done
fi

# 3c. Trigger broker reset: update sync script, download routes.csv, sync HAProxy, restart broker
echo "  Triggering broker reset..."
COMMAND_ID=$(aws ssm send-command \
  --region "$BROKER_AWS_REGION" \
  --instance-ids "$EC2_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["source /etc/route-lb/env && aws s3 cp s3://$CONFIG_BUCKET/route-lb/route-lb-sync /usr/local/bin/route-lb-sync --region us-east-1 && chmod +x /usr/local/bin/route-lb-sync && aws s3 cp s3://$CONFIG_BUCKET/$ROUTE_CATALOG_KEY /var/lib/route-lb/routes.csv --region us-east-1 && /usr/local/bin/route-lb-sync && systemctl restart route-lb-broker && sleep 2 && curl -s -X POST http://localhost:3000/admin/reset"]}' \
  --query 'Command.CommandId' --output text 2>/dev/null || true)

if [[ -n "$COMMAND_ID" && "$COMMAND_ID" != "None" ]]; then
  echo "  SSM command: $COMMAND_ID"
  echo -n "  Waiting for broker reset..."
  SSM_STATUS="Pending"
  for _attempt in 1 2 3 4 5; do
    sleep 2
    SSM_STATUS=$(aws ssm get-command-invocation \
      --region "$BROKER_AWS_REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$EC2_INSTANCE_ID" \
      --query 'Status' --output text 2>/dev/null || echo "Pending")
    if [[ "$SSM_STATUS" == "Success" || "$SSM_STATUS" == "Failed" ]]; then
      break
    fi
    echo -n "."
  done
  echo ""
  if [[ "$SSM_STATUS" == "Success" ]]; then
    SSM_OUTPUT=$(aws ssm get-command-invocation \
      --region "$BROKER_AWS_REGION" \
      --command-id "$COMMAND_ID" \
      --instance-id "$EC2_INSTANCE_ID" \
      --query 'StandardOutputContent' --output text 2>/dev/null || echo "")
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
if [[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]]; then
  SUMMARY_PARTS=""
  for i in "${!ALL_CLUSTER_IDS[@]}"; do
    [[ -n "$SUMMARY_PARTS" ]] && SUMMARY_PARTS+=" + "
    SUMMARY_PARTS+="${CLUSTER_ROUTE_COUNTS[$i]} ${ALL_CLUSTER_IDS[$i]}"
  done
  echo -e "  Routes: ${SUMMARY_PARTS} = ${TOTAL_ROUTE_COUNT} total"
else
  echo -e "  Routes: ${TOTAL_ROUTE_COUNT} namespaces"
fi
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

# Print direct broker URLs per cluster/namespace (admin/debug)
if [[ -n "$AUDIENCE_CODE" ]]; then
  echo -e "  ${DIM}Direct URLs (admin/debug):${RESET}"
  for i in "${!CLUSTER_ENTRIES[@]}"; do
    CLUSTER_ID="${ALL_CLUSTER_IDS[$i]}"
    NS_LIST="${CLUSTER_NS_LISTS[$i]:-}"

    if [[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]]; then
      echo -e "    ${BOLD}${CLUSTER_ID}:${RESET}"
    fi

    for NS in $NS_LIST; do
      ROUTE_HOST=$(grep "^${NS}," "$ROUTE_HOST_CACHE_FILE" 2>/dev/null | cut -d',' -f2)
      if [[ -n "$ROUTE_HOST" ]]; then
        PREFIX="${ROUTE_HOST%%.*}"
        USER_NUM="${NS#${NAMESPACE_PREFIX}}"
        echo -e "    user${USER_NUM}: ${DIM}https://${PREFIX}.${BROKER_DOMAIN}${RESET}"
      fi
    done
  done
  echo ""
fi

rm -f "$ROUTE_HOST_CACHE_FILE"
