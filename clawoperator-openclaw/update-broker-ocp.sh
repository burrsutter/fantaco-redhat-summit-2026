#!/usr/bin/env bash
# update-broker-ocp.sh — Rebuild routes.csv and update the OpenShift-hosted broker
#
# Discovers all audience routes across one or more OpenShift clusters,
# generates a merged routes.csv (with direct OCP route hosts — no custom domain),
# copies it into the broker pod, and triggers a broker reload.
#
# No AWS, no custom domain, no ALB/HAProxy needed.
#
# Multi-cluster mode:
#   If clusters.csv exists, routes are discovered from all listed clusters.
#   Otherwise, falls back to single-cluster mode using the current oc context.
#
# Usage:
#   ./update-broker-ocp.sh                          # discover routes, keep existing audience code
#   ./update-broker-ocp.sh --audience-code abc12     # set a specific audience code
#   ./update-broker-ocp.sh --rotate-status-key       # also rotate the STATUS_KEY
#   ./update-broker-ocp.sh --namespace agentic-user3 # update a single route (fast path)
#   ./update-broker-ocp.sh --reset                   # wipe all assignments (new audience)
#
# Environment variables:
#   NAMESPACE_PREFIX    — namespace prefix (default: agentic-user)
#   BROKER_NS           — namespace where the broker is deployed (default: session-broker)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
BROKER_NS="${BROKER_NS:-session-broker}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"

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
FORCE_RESET=false
UPDATE_NAMESPACE=""

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
    --reset)
      FORCE_RESET=true
      shift
      ;;
    --namespace)
      UPDATE_NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--audience-code CODE] [--rotate-status-key] [--reset] [--namespace NS]"
      echo ""
      echo "  --audience-code CODE   Set the audience code"
      echo "  --rotate-status-key    Generate a new STATUS_KEY for the status board"
      echo "  --reset                Wipe all assignments (default: preserve with reload)"
      echo "  --namespace NS         Update only this namespace's route (fast path)"
      echo ""
      echo "Discovers audience routes from cluster(s), generates routes.csv with"
      echo "direct OCP route hosts, and injects into the broker pod on OpenShift."
      echo ""
      echo "Multi-cluster: create clusters.csv to discover routes from multiple clusters."
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'"
      exit 1
      ;;
  esac
done

# ── Preflight: broker must be running ──────────────────────────────
if ! oc get deployment session-broker -n "$BROKER_NS" &>/dev/null; then
  echo -e "${RED}Error: Broker not deployed. Run ./deploy-broker-ocp.sh first.${RESET}"
  exit 1
fi

BROKER_POD=$(oc get pods -n "$BROKER_NS" -l app=session-broker --no-headers 2>/dev/null \
  | grep Running | awk '{print $1}' | head -1)
if [[ -z "$BROKER_POD" ]]; then
  echo -e "${RED}Error: No running broker pod in ${BROKER_NS}.${RESET}"
  exit 1
fi

BROKER_HOST=$(oc get route session-broker -n "$BROKER_NS" -o jsonpath='{.spec.host}' 2>/dev/null)

# ── Build cluster list ──────────────────────────────────────────────
CLUSTER_ENTRIES=()
CLUSTER_GUIDS=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  echo -e "${BOLD}Multi-cluster mode:${RESET} reading ${CLUSTERS_CSV}"
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})"
      exit 1
    fi
    GUID=$(KUBECONFIG="$kubeconfig_path" oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
    if [[ -z "$GUID" ]]; then
      echo -e "  ${RED}✗${RESET} Cluster ${cluster_id}: could not extract GUID"
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

# ── Rotate STATUS_KEY if requested ──────────────────────────────────
if $ROTATE_STATUS_KEY; then
  STATUS_KEY=$(python3 -c "import secrets; print(secrets.token_hex(8))")
  echo "  Generated new STATUS_KEY"
fi

# ── Routes CSV output file ──────────────────────────────────────────
ROUTES_CSV="${SCRIPT_DIR}/routes-ocp.csv"

# ══════════════════════════════════════════════════════════════════════
# Single-namespace fast path
# ══════════════════════════════════════════════════════════════════════
if [[ -n "$UPDATE_NAMESPACE" ]]; then
  echo -e "${BOLD}=== Update Single Route: ${UPDATE_NAMESPACE} ===${RESET}"

  if [[ ! -f "$ROUTES_CSV" ]]; then
    echo -e "${RED}Error: ${ROUTES_CSV} not found. Run a full update first.${RESET}"
    exit 1
  fi

  FOUND_KUBECONFIG=""
  for entry in "${CLUSTER_ENTRIES[@]}"; do
    CID="${entry%% *}"
    CKUBE="${entry#* }"
    if KUBECONFIG="$CKUBE" oc get ns "$UPDATE_NAMESPACE" &>/dev/null; then
      FOUND_KUBECONFIG="$CKUBE"
      echo -e "  Cluster: ${CYAN}${CID}${RESET}"
      break
    fi
  done
  if [[ -z "$FOUND_KUBECONFIG" ]]; then
    echo -e "${RED}Error: namespace ${UPDATE_NAMESPACE} not found on any cluster.${RESET}"
    exit 1
  fi

  NEW_HOST=$(KUBECONFIG="$FOUND_KUBECONFIG" oc get route audience -n "$UPDATE_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$NEW_HOST" ]]; then
    echo -e "${RED}Error: no audience route in ${UPDATE_NAMESPACE}.${RESET}"
    exit 1
  fi

  STATUS_URL=$(KUBECONFIG="$FOUND_KUBECONFIG" oc get claw instance -n "$UPDATE_NAMESPACE" -o jsonpath='{.status.url}' 2>/dev/null || true)
  TOKEN_FRAG=$(echo "$STATUS_URL" | grep -o '#token=.*' || true)
  # OCP-direct: public_host = backend_host (the real OCP route)
  NEW_LINE="${NEW_HOST},${NEW_HOST},true,${UPDATE_NAMESPACE},${TOKEN_FRAG}"

  CLUSTER_APPS_DOMAIN=$(KUBECONFIG="$FOUND_KUBECONFIG" oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  OLD_LINE=$(grep ",${UPDATE_NAMESPACE}," "$ROUTES_CSV" | grep "${CLUSTER_APPS_DOMAIN}" || true)
  if [[ -n "$OLD_LINE" ]]; then
    TMPFILE=$(mktemp)
    REPLACED=false
    while IFS= read -r line; do
      if [[ "$REPLACED" == "false" ]] && echo "$line" | grep -q ",${UPDATE_NAMESPACE}," && echo "$line" | grep -q "${CLUSTER_APPS_DOMAIN}"; then
        echo "$NEW_LINE"
        REPLACED=true
      else
        echo "$line"
      fi
    done < "$ROUTES_CSV" > "$TMPFILE"
    mv "$TMPFILE" "$ROUTES_CSV"
    echo -e "  Old: ${DIM}${OLD_LINE}${RESET}"
    echo -e "  New: ${GREEN}${NEW_LINE}${RESET}"
  else
    echo "$NEW_LINE" >> "$ROUTES_CSV"
    echo -e "  Added: ${GREEN}${NEW_LINE}${RESET}"
  fi
  echo ""

  TOTAL_ROUTE_COUNT=$(grep -c -v '^#' "$ROUTES_CSV" || true)
  echo -e "  Routes: ${GREEN}${TOTAL_ROUTE_COUNT}${RESET} total (1 updated)"
  echo ""
fi

# ── Full discovery (skipped when --namespace is used) ─────────────────
if [[ -z "$UPDATE_NAMESPACE" ]]; then

echo -e "${BOLD}=== Update OCP Broker ===${RESET}"
echo -e "Broker:       ${CYAN}${BROKER_HOST}${RESET}"
echo -e "Clusters:     ${CYAN}${#CLUSTER_ENTRIES[@]}${RESET}"
echo ""

echo -e "${BOLD}--- Step 1: Discover routes from cluster(s) ---${RESET}"

echo "# public_host,openshift_route_host,enabled,namespace,token_fragment" > "$ROUTES_CSV"
TOTAL_ROUTE_COUNT=0
TOTAL_SKIP_COUNT=0

CLUSTER_ROUTE_COUNTS=()
ALL_CLUSTER_IDS=()
CLUSTER_NS_LISTS=()

DISCOVERY_TMPDIR=$(mktemp -d)
MAX_PARALLEL=10

for i in "${!CLUSTER_ENTRIES[@]}"; do
  entry="${CLUSTER_ENTRIES[$i]}"
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  ALL_CLUSTER_IDS+=("$CLUSTER_ID")

  APPS_DOMAIN=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  if [[ -z "$APPS_DOMAIN" ]]; then
    echo -e "  ${RED}✗${RESET} Cluster ${CLUSTER_ID}: could not detect APPS_DOMAIN"
    rm -rf "$DISCOVERY_TMPDIR"
    exit 1
  fi

  echo -e "  ${BOLD}${CLUSTER_ID}${RESET} (${APPS_DOMAIN})"

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

  JOB_COUNT=0
  for NS in "${NAMESPACES[@]}"; do
    (
      host=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get route audience -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
      if [[ -n "$host" ]]; then
        status_url=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get claw instance -n "$NS" -o jsonpath='{.status.url}' 2>/dev/null || true)
        token_fragment=$(echo "$status_url" | grep -o '#token=.*' || true)
        # OCP-direct: public_host = backend_host (the real OCP route)
        echo "${host},${host},true,${NS},${token_fragment}" > "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}"
      fi
    ) &
    JOB_COUNT=$((JOB_COUNT + 1))
    if (( JOB_COUNT >= MAX_PARALLEL )); then
      wait
      JOB_COUNT=0
    fi
  done
  wait

  CLUSTER_ROUTE_COUNT=0
  NS_LIST=""
  for NS in "${NAMESPACES[@]}"; do
    if [[ -f "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}" ]]; then
      cat "${DISCOVERY_TMPDIR}/${CLUSTER_ID}_${NS}" >> "$ROUTES_CSV"
      ((CLUSTER_ROUTE_COUNT++)) || true
      ((TOTAL_ROUTE_COUNT++)) || true
      NS_LIST+=" $NS"
    else
      echo -e "    ${YELLOW}⚠${RESET} No audience route in $NS — skipping"
      ((TOTAL_SKIP_COUNT++)) || true
    fi
  done

  CLUSTER_ROUTE_COUNTS+=("$CLUSTER_ROUTE_COUNT")
  CLUSTER_NS_LISTS+=("$NS_LIST")
  echo -e "    Found ${GREEN}${CLUSTER_ROUTE_COUNT}${RESET} routes across ${#NAMESPACES[@]} namespaces"
done

rm -rf "$DISCOVERY_TMPDIR"
echo ""

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

if [[ $TOTAL_ROUTE_COUNT -eq 0 ]]; then
  echo "Error: No audience routes found. Nothing to update."
  exit 1
fi

fi  # end of full discovery block

# ── Step 2: Inject routes.csv into broker pod ───────────────────────
echo -e "${BOLD}--- Step 2: Inject routes.csv into broker pod ---${RESET}"
oc cp "$ROUTES_CSV" "${BROKER_NS}/${BROKER_POD}:/var/lib/route-lb/routes.csv" 2>/dev/null
echo -e "  ${GREEN}✓${RESET} routes.csv copied to ${BROKER_POD}"
echo ""

# ── Step 3: Update STATUS_KEY and trigger broker reset ──────────────
echo -e "${BOLD}--- Step 3: Update broker ---${RESET}"

if [[ -n "$STATUS_KEY" ]]; then
  echo "  Setting STATUS_KEY on broker..."
  oc set env deployment/session-broker -n "$BROKER_NS" "STATUS_KEY=${STATUS_KEY}" 2>/dev/null
  echo "  Waiting for rollout..."
  oc rollout status deployment/session-broker -n "$BROKER_NS" --timeout=60s 2>&1 | tail -1 | sed 's/^/  /'

  # Re-discover pod after rollout
  BROKER_POD=$(oc get pods -n "$BROKER_NS" -l app=session-broker --no-headers 2>/dev/null \
    | grep Running | awk '{print $1}' | head -1)

  # Re-inject routes.csv (new pod from rollout)
  oc cp "$ROUTES_CSV" "${BROKER_NS}/${BROKER_POD}:/var/lib/route-lb/routes.csv" 2>/dev/null
  echo -e "  ${GREEN}✓${RESET} routes.csv re-injected after rollout"
fi

# Trigger broker reset or reload
if $FORCE_RESET; then
  echo "  Triggering broker reset (wiping all assignments)..."
  oc exec "$BROKER_POD" -n "$BROKER_NS" -- curl -s -X POST http://localhost:3000/admin/reset 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Routes: {d[\"total\"]} ({d[\"assigned\"]} assigned, {d[\"available\"]} available)')" 2>/dev/null \
    || echo -e "  ${YELLOW}⚠${RESET} Could not parse reset response"
else
  echo "  Triggering broker reload (preserving assignments)..."
  oc exec "$BROKER_POD" -n "$BROKER_NS" -- curl -s -X POST http://localhost:3000/admin/reload 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'  Routes: {d[\"total\"]} ({d[\"assigned\"]} assigned, {d[\"available\"]} available)')" 2>/dev/null \
    || echo -e "  ${YELLOW}⚠${RESET} Could not parse reload response"
fi
echo ""

# ── Save broker state ──────────────────────────────────────────────
if [[ -n "$AUDIENCE_CODE" || -n "$STATUS_KEY" ]]; then
  for GUID in "${CLUSTER_GUIDS[@]}"; do
    mkdir -p "${SCRIPT_DIR}/.state/${GUID}"
    cat > "${SCRIPT_DIR}/.state/${GUID}/broker.env" <<BRKEOF
AUDIENCE_CODE=${AUDIENCE_CODE}
STATUS_KEY=${STATUS_KEY}
BRKEOF
    chmod 600 "${SCRIPT_DIR}/.state/${GUID}/broker.env"
  done
fi

# ── Summary ─────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}=== Broker update complete ===${RESET}"
if [[ -n "$UPDATE_NAMESPACE" ]]; then
  TOTAL_ROUTE_COUNT=$(grep -c -v '^#' "$ROUTES_CSV" || true)
  echo -e "  Updated: ${GREEN}${UPDATE_NAMESPACE}${RESET} (${TOTAL_ROUTE_COUNT} total routes)"
elif [[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]]; then
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
  echo -e "  ${BOLD}Share this URL:${RESET}"
  echo ""
  SHARE_URL="https://${BROKER_HOST}/${AUDIENCE_CODE}"
  echo -e "    ${GREEN}${SHARE_URL}${RESET}"
  echo ""

  if [[ -z "$UPDATE_NAMESPACE" ]] && command -v qrencode &>/dev/null; then
    qrencode -t UTF8 "$SHARE_URL"
    QR_FILE="${SCRIPT_DIR}/qr-code-ocp.png"
    qrencode -t PNG -o "$QR_FILE" -s 10 "$SHARE_URL"
    echo ""
    echo -e "  ${DIM}QR code saved to: ${QR_FILE}${RESET}"
  fi
  echo ""
  echo -e "  ${DIM}Each visitor is auto-assigned an exclusive OpenClaw instance.${RESET}"
fi

if [[ -n "${STATUS_KEY:-}" ]]; then
  echo -e "  ${DIM}Status board: https://${BROKER_HOST}/status?key=${STATUS_KEY}${RESET}"
fi
echo ""
