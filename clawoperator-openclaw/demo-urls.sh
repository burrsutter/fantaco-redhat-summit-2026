#!/usr/bin/env bash
# demo-urls.sh — Display stage-ready URLs, QR code, and provider info
#
# Shows all the links you need for a demo: observability dashboards,
# FantaCo UIs, broker audience/status URLs, QR code, and model provider info.
#
# Multi-cluster mode:
#   If clusters.csv exists, shows URLs for all listed clusters.
#   Otherwise, uses the current oc context.
#
# Usage:
#   ./demo-urls.sh              # show URLs (auto-detect namespaces)
#   ./demo-urls.sh 1 5          # use agentic-user1 for FantaCo UIs
#   ./demo-urls.sh 3            # use agentic-user3 for FantaCo UIs

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"
ENV_FILE="${SCRIPT_DIR}/../.env"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Source .env ──────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
LLM_PROVIDER="${LLM_PROVIDER:-}"

# ── Argument parsing ────────────────────────────────────────────────
DISCOVER_ALL=false
FIRST_NS=""

if [[ $# -eq 0 ]]; then
  DISCOVER_ALL=true
elif [[ $# -le 2 ]]; then
  START=$1
  FIRST_NS="${NAMESPACE_PREFIX}${START}"
else
  echo "Usage: $0 [start] [end]"
  echo "  $0          → auto-detect first namespace for FantaCo UIs"
  echo "  $0 1 5      → use ${NAMESPACE_PREFIX}1 for FantaCo UIs"
  echo "  $0 3        → use ${NAMESPACE_PREFIX}3 for FantaCo UIs"
  exit 1
fi

# ── Build cluster list ──────────────────────────────────────────────
CLUSTER_IDS=()
CLUSTER_KUBECONFIGS=()
CLUSTER_GUIDS_LIST=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}✗${RESET} Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})"
      exit 1
    fi
    GUID=$(KUBECONFIG="$kubeconfig_path" oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
    CLUSTER_IDS+=("$cluster_id")
    CLUSTER_KUBECONFIGS+=("$kubeconfig_path")
    CLUSTER_GUIDS_LIST+=("$GUID")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_IDS[@]} -eq 0 ]]; then
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
  CLUSTER_IDS+=("default")
  CLUSTER_KUBECONFIGS+=("${KUBECONFIG:-$HOME/.kube/config}")
  CLUSTER_GUIDS_LIST+=("$GUID")
fi

TOTAL_CLUSTER_COUNT=${#CLUSTER_IDS[@]}
MULTI_CLUSTER=$([[ $TOTAL_CLUSTER_COUNT -gt 1 ]] && echo true || echo false)

# ── Collect broker state (use first cluster with a broker.env) ──────
BROKER_AUDIENCE_ID=""
BROKER_STATUS_KEY=""
for GUID in "${CLUSTER_GUIDS_LIST[@]}"; do
  BROKER_STATE_FILE="${SCRIPT_DIR}/.state/${GUID}/broker.env"
  if [[ -f "$BROKER_STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BROKER_STATE_FILE"
    BROKER_AUDIENCE_ID="${AUDIENCE_CODE:-}"
    BROKER_STATUS_KEY="${STATUS_KEY:-}"
    break
  fi
done

# ══════════════════════════════════════════════════════════════════════
# Per-cluster URLs
# ══════════════════════════════════════════════════════════════════════

for ci in "${!CLUSTER_IDS[@]}"; do
  CID="${CLUSTER_IDS[$ci]}"
  CKUBE="${CLUSTER_KUBECONFIGS[$ci]}"
  export KUBECONFIG="$CKUBE"

  APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  [[ -z "$APPS_DOMAIN" ]] && continue

  # Determine which namespace to use for FantaCo UIs
  NS_FOR_UI="$FIRST_NS"
  if [[ -z "$NS_FOR_UI" ]]; then
    NS_FOR_UI=$(oc get ns --no-headers 2>/dev/null | awk '{print $1}' | grep "^${NAMESPACE_PREFIX}" | sort -V | head -1 || true)
  fi

  echo ""
  echo -e "${BOLD}════════════════════════════════════════════${RESET}"
  if $MULTI_CLUSTER; then
    echo -e "${BOLD}  Stage-Ready URLs — ${CID}${RESET}"
  else
    echo -e "${BOLD}  Stage-Ready URLs${RESET}"
  fi
  echo -e "${BOLD}════════════════════════════════════════════${RESET}"

  # OpenShift Console
  echo ""
  echo -e "  ${BOLD}OpenShift Console:${RESET}"
  echo -e "    Observe > Logs:   ${DIM}https://console-openshift-console.${APPS_DOMAIN}/monitoring/logs${RESET}"

  # Observability
  echo ""
  echo -e "  ${BOLD}Observability:${RESET}"

  GRAFANA_HOST=$(oc get route grafana-route -n grafana -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$GRAFANA_HOST" ]]; then
    echo -e "    Grafana:          ${DIM}https://${GRAFANA_HOST}${RESET}"
  else
    echo -e "    Grafana:          ${YELLOW}route not found${RESET}"
  fi

  MLFLOW_HOST=$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$MLFLOW_HOST" ]]; then
    echo -e "    MLflow Traces:    ${DIM}https://${MLFLOW_HOST}/#/experiments/1/traces${RESET}"
  else
    echo -e "    MLflow Traces:    ${YELLOW}route not found${RESET}"
  fi

  LANGFUSE_HOST=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$LANGFUSE_HOST" ]]; then
    echo -e "    Langfuse Traces:  ${DIM}https://${LANGFUSE_HOST}/project/openclaw-traces/traces${RESET}"
  else
    echo -e "    Langfuse Traces:  ${YELLOW}route not found${RESET}"
  fi

  # FantaCo UIs
  if [[ -n "$NS_FOR_UI" ]]; then
    echo ""
    echo -e "  ${BOLD}FantaCo UIs (${NS_FOR_UI}):${RESET}"

    CUSTOMER_HOST=$(oc get route fantaco-customer-service -n "$NS_FOR_UI" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$CUSTOMER_HOST" ]]; then
      echo -e "    Customers:        ${DIM}https://${CUSTOMER_HOST}/customers/index.html${RESET}"
    else
      echo -e "    Customers:        ${YELLOW}route not found${RESET}"
    fi

    PRODUCT_HOST=$(oc get route fantaco-product-service -n "$NS_FOR_UI" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$PRODUCT_HOST" ]]; then
      echo -e "    Products:         ${DIM}https://${PRODUCT_HOST}/catalog/index.html${RESET}"
    else
      echo -e "    Products:         ${YELLOW}route not found${RESET}"
    fi

    ORDERS_HOST=$(oc get route fantaco-sales-order-service -n "$NS_FOR_UI" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$ORDERS_HOST" ]]; then
      echo -e "    Orders:           ${DIM}https://${ORDERS_HOST}/orders/index.html${RESET}"
    else
      echo -e "    Orders:           ${YELLOW}route not found${RESET}"
    fi
  fi

  echo ""
  echo -e "${BOLD}════════════════════════════════════════════${RESET}"
done

# ── Session Broker (once, not per-cluster) ──────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Session Broker${RESET}"
echo -e "${BOLD}════════════════════════════════════════════${RESET}"

if [[ -n "$BROKER_AUDIENCE_ID" ]]; then
  echo -e "    Audience URL:     ${DIM}https://yougetaclaw.com/${BROKER_AUDIENCE_ID}${RESET}"
else
  echo -e "    Audience URL:     ${YELLOW}not found (run audience-reset.sh first)${RESET}"
fi

if [[ -n "$BROKER_STATUS_KEY" ]]; then
  echo -e "    Status board:     ${DIM}https://yougetaclaw.com/status?key=${BROKER_STATUS_KEY}${RESET}"
else
  echo -e "    Status board:     ${YELLOW}STATUS_KEY not found${RESET}"
fi

# QR Code
echo ""
echo -e "  ${BOLD}QR Code:${RESET}"

if [[ -n "$BROKER_AUDIENCE_ID" ]]; then
  QR_URL="https://yougetaclaw.com/${BROKER_AUDIENCE_ID}"
  QR_PNG="${SCRIPT_DIR}/qr-code.png"
  QR_ID_FILE="${SCRIPT_DIR}/qr-code.id"

  NEEDS_REGEN=false
  if [[ ! -f "$QR_PNG" ]]; then
    NEEDS_REGEN=true
  elif [[ ! -f "$QR_ID_FILE" ]] || [[ "$(cat "$QR_ID_FILE" 2>/dev/null)" != "$BROKER_AUDIENCE_ID" ]]; then
    NEEDS_REGEN=true
  fi

  if $NEEDS_REGEN; then
    if command -v qrencode &>/dev/null; then
      echo ""
      qrencode -t ANSIUTF8 "$QR_URL" 2>/dev/null || true
      echo ""
      qrencode -o "$QR_PNG" -s 10 "$QR_URL" 2>/dev/null && \
        echo "$BROKER_AUDIENCE_ID" > "$QR_ID_FILE" && \
        echo -e "    QR code generated: ${DIM}${QR_PNG}${RESET}" || true
    else
      echo -e "    ${YELLOW}qrencode not installed (brew install qrencode)${RESET}"
    fi
  else
    echo -e "    QR code up-to-date: ${DIM}${QR_PNG}${RESET}"
    echo ""
    qrencode -t ANSIUTF8 "$QR_URL" 2>/dev/null || true
    echo ""
  fi
else
  echo -e "    ${YELLOW}Skipped — audience-id not yet configured${RESET}"
fi

# Model Provider / OpenRouter balance
echo ""
echo -e "  ${BOLD}Model Provider:${RESET}"

if [[ "$LLM_PROVIDER" == "openrouter" ]]; then
  echo -e "    Provider:         ${DIM}openrouter (${OPENROUTER_MODEL:-unknown})${RESET}"
  if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    OR_RESP=$(curl -sf --connect-timeout 5 "https://openrouter.ai/api/v1/auth/key" \
      -H "Authorization: Bearer ${OPENROUTER_API_KEY}" 2>/dev/null || true)
    if [[ -n "$OR_RESP" ]]; then
      OR_USAGE=$(echo "$OR_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(f\"{d['data']['usage']:.2f}\")
except: print('unknown')
" 2>/dev/null || echo "unknown")
      echo -e "    OpenRouter spend: ${DIM}\$${OR_USAGE}${RESET}"
    else
      echo -e "    OpenRouter spend: ${YELLOW}API unreachable${RESET}"
    fi
  else
    echo -e "    OpenRouter spend: ${YELLOW}OPENROUTER_API_KEY not set${RESET}"
  fi
elif [[ "$LLM_PROVIDER" == "gcp" ]]; then
  echo -e "    Provider:         ${DIM}gcp (${GEMINI_MODEL:-unknown})${RESET}"
elif [[ "$LLM_PROVIDER" == "litellm" ]]; then
  echo -e "    Provider:         ${DIM}litellm (${LLM_MODEL_NAME:-unknown})${RESET}"
else
  echo -e "    Provider:         ${DIM}${LLM_PROVIDER:-not set}${RESET}"
fi

echo ""
echo -e "${BOLD}════════════════════════════════════════════${RESET}"
echo ""
