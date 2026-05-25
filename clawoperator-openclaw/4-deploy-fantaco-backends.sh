#!/usr/bin/env bash
# 4-deploy-fantaco-backends.sh — Deploy FantaCo backends + MCP servers
#
# Renders templates from the fantaco-app and fantaco-mcp Helm charts
# and applies them via oc apply. Deploys per namespace:
#   - postgresql-customer (database) + fantaco-customer-main (REST API) + mcp-customer (MCP)
#   - postgresql-salesorder (database) + fantaco-sales-order-main (REST API) + mcp-sales-order (MCP)
#
# Usage:
#   ./4-deploy-fantaco-backends.sh              # deploy to current namespace (student mode)
#   ./4-deploy-fantaco-backends.sh 2 5          # deploy to agentic-user2 through agentic-user5
#   ./4-deploy-fantaco-backends.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX        — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/../helm"

# ── Customer templates to render ────────────────────────────────────
CUSTOMER_APP_TEMPLATES=(
  templates/postgres-customer-deployment.yaml
  templates/postgres-customer-service.yaml
  templates/customer-configmap.yaml
  templates/customer-secret.yaml
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
)

CUSTOMER_MCP_TEMPLATES=(
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
)

# ── Sales-order templates to render ─────────────────────────────────
SALESORDER_APP_TEMPLATES=(
  templates/postgres-salesorder-deployment.yaml
  templates/postgres-salesorder-service.yaml
  templates/salesorder-configmap.yaml
  templates/salesorder-secret.yaml
  templates/salesorder-deployment.yaml
  templates/salesorder-service.yaml
  templates/salesorder-route.yaml
)

SALESORDER_MCP_TEMPLATES=(
  templates/salesorder-deployment.yaml
  templates/salesorder-service.yaml
  templates/salesorder-route.yaml
)

# ── Product templates to render ────────────────────────────────────
PRODUCT_APP_TEMPLATES=(
  templates/postgres-product-deployment.yaml
  templates/postgres-product-service.yaml
  templates/product-configmap.yaml
  templates/product-secret.yaml
  templates/product-deployment.yaml
  templates/product-service.yaml
  templates/product-route.yaml
)

PRODUCT_MCP_TEMPLATES=(
  templates/product-deployment.yaml
  templates/product-service.yaml
  templates/product-route.yaml
)

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  # No args — use current namespace (student mode)
  CURRENT_NS=$(oc project -q 2>/dev/null) || { echo "Error: cannot detect current namespace. Run 'oc project <ns>' first."; exit 1; }
  NAMESPACES+=("$CURRENT_NS")
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo "Error: start ($START) must be <= end ($END)"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # deploy to current namespace"
  echo "       $0 <start> [end]  # deploy to agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify Helm charts exist ────────────────────────────────────────
if [[ ! -d "$HELM_DIR/fantaco-app" ]]; then
  echo "Error: Helm chart not found at $HELM_DIR/fantaco-app"
  exit 1
fi
if [[ ! -d "$HELM_DIR/fantaco-mcp" ]]; then
  echo "Error: Helm chart not found at $HELM_DIR/fantaco-mcp"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  Deploy FantaCo Backends"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo "Namespaces:   ${NAMESPACES[*]}"
echo "Components:   postgresql-customer, fantaco-customer-main, mcp-customer"
echo "              postgresql-product, fantaco-product-main, mcp-product"
echo "              postgresql-salesorder, fantaco-sales-order-main, mcp-sales-order"
echo ""

# ── Helper: render and apply templates ──────────────────────────────
apply_templates() {
  local chart_name=$1
  local chart_dir=$2
  local ns=$3
  shift 3
  local templates=("$@")

  local show_args=()
  for t in "${templates[@]}"; do
    show_args+=(-s "$t")
  done

  helm template "$chart_name" "$chart_dir" -n "$ns" "${show_args[@]}" \
    | oc apply -n "$ns" -f - 2>&1 | sed 's/^/    /'
}

# ── Helper: wait for pods matching a grep pattern ───────────────────
wait_for_pods() {
  local ns=$1
  local pattern=$2
  local expected=$3
  local label=$4

  SECONDS=0
  local ready=0
  while [[ $SECONDS -lt 120 ]]; do
    ready=$(oc get pods -n "$ns" --no-headers 2>/dev/null \
      | grep -E "$pattern" \
      | grep -c "Running" || true)
    if [[ $ready -ge $expected ]]; then
      break
    fi
    sleep 5
  done

  if [[ $ready -ge $expected ]]; then
    echo "  ✓ $label: $ready/$expected pods running"
  else
    echo "  ⚠ $label: only $ready/$expected pods running after 120s"
    echo "    Check: oc get pods -n $ns"
  fi
  return 0
}

SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Deploying to namespace: $NS ==="

  # ── Customer backend ──────────────────────────────────────────────
  echo "  Applying customer backend resources..."
  if ! apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${CUSTOMER_APP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-app customer apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  echo "  Waiting for customer backend pods (up to 120s)..."
  wait_for_pods "$NS" "(fantaco-customer-main|postgresql-customer)" 2 "customer backend"

  echo "  Applying customer MCP server resources..."
  if ! apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${CUSTOMER_MCP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-mcp customer apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # ── Sales-order backend ───────────────────────────────────────────
  echo "  Applying sales-order backend resources..."
  if ! apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${SALESORDER_APP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-app sales-order apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  echo "  Waiting for sales-order backend pods (up to 120s)..."
  wait_for_pods "$NS" "(fantaco-sales-order-main|postgresql-salesorder)" 2 "sales-order backend"

  echo "  Applying sales-order MCP server resources..."
  if ! apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${SALESORDER_MCP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-mcp sales-order apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # ── Product backend ────────────────────────────────────────────────
  echo "  Applying product backend resources..."
  if ! apply_templates fantaco-app "$HELM_DIR/fantaco-app" "$NS" "${PRODUCT_APP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-app product apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  echo "  Waiting for product backend pods (up to 120s)..."
  wait_for_pods "$NS" "(fantaco-product-main|postgresql-product)" 2 "product backend"

  echo "  Applying product MCP server resources..."
  if ! apply_templates fantaco-mcp "$HELM_DIR/fantaco-mcp" "$NS" "${PRODUCT_MCP_TEMPLATES[@]}"; then
    echo "  ⚠ fantaco-mcp product apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # ── Wait for all 9 pods ───────────────────────────────────────────
  echo "  Waiting for all pods (up to 120s)..."
  wait_for_pods "$NS" \
    "(fantaco-customer-main|postgresql-customer|mcp-customer|fantaco-product-main|postgresql-product|mcp-product|fantaco-sales-order-main|postgresql-salesorder|mcp-sales-order)" \
    9 "all backends"

  # ── Smoke tests ───────────────────────────────────────────────────
  echo "  Running smoke tests..."

  CUSTOMER_ROUTE=$(oc get route fantaco-customer-service -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$CUSTOMER_ROUTE" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${CUSTOMER_ROUTE}/actuator/health/liveness" 2>/dev/null || true)
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "    ✓ customer-service health: $HTTP_CODE"
    else
      echo "    ⚠ customer-service health: $HTTP_CODE"
    fi
  else
    echo "    ⚠ customer-service route not found"
  fi

  PRODUCT_ROUTE=$(oc get route fantaco-product-service -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$PRODUCT_ROUTE" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${PRODUCT_ROUTE}/actuator/health/liveness" 2>/dev/null || true)
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "    ✓ product-service health: $HTTP_CODE"
    else
      echo "    ⚠ product-service health: $HTTP_CODE"
    fi
  else
    echo "    ⚠ product-service route not found"
  fi

  SO_ROUTE=$(oc get route fantaco-sales-order-service -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$SO_ROUTE" ]]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://${SO_ROUTE}/actuator/health/liveness" 2>/dev/null || true)
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "    ✓ sales-order-service health: $HTTP_CODE"
    else
      echo "    ⚠ sales-order-service health: $HTTP_CODE"
    fi
  else
    echo "    ⚠ sales-order-service route not found"
  fi

  MCP_CUST_ROUTE=$(oc get route mcp-customer-route -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$MCP_CUST_ROUTE" ]]; then
    echo "    mcp-customer: https://${MCP_CUST_ROUTE}"
  fi

  MCP_PROD_ROUTE=$(oc get route mcp-product-route -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$MCP_PROD_ROUTE" ]]; then
    echo "    mcp-product: https://${MCP_PROD_ROUTE}"
  fi

  MCP_SO_ROUTE=$(oc get route mcp-sales-order-route -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$MCP_SO_ROUTE" ]]; then
    echo "    mcp-sales-order: https://${MCP_SO_ROUTE}"
  fi

  # ── Print routes ──────────────────────────────────────────────────
  echo "  Routes:"
  oc get routes -n "$NS" --no-headers 2>/dev/null \
    | grep -E "(fantaco-customer|mcp-customer|fantaco-product|mcp-product|fantaco-sales-order|mcp-sales-order)" \
    | awk '{printf "    %-45s https://%s\n", $1, $2}' || true

  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  echo ""
done

# ── Summary ─────────────────────────────────────────────────────────
echo "============================================"
echo "  Deployment Summary"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo ""
