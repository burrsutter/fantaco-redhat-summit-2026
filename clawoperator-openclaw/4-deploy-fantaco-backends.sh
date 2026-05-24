#!/usr/bin/env bash
# deploy-fantaco-backends.sh — Deploy FantaCo customer backend + MCP across namespaces
#
# Renders customer-only templates from the fantaco-app and fantaco-mcp Helm charts
# and applies them via oc apply. Deploys 3 pods per namespace:
#   - postgresql-customer (database)
#   - fantaco-customer-main (REST API)
#   - mcp-customer (MCP server)
#
# Usage:
#   ./deploy-fantaco-backends.sh              # deploy to current namespace (student mode)
#   ./deploy-fantaco-backends.sh 2 5          # deploy to agentic-user2 through agentic-user5
#   ./deploy-fantaco-backends.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX        — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/../helm"

# ── Customer templates to render ────────────────────────────────────
APP_TEMPLATES=(
  templates/postgres-customer-deployment.yaml
  templates/postgres-customer-service.yaml
  templates/customer-configmap.yaml
  templates/customer-secret.yaml
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
)

MCP_TEMPLATES=(
  templates/customer-deployment.yaml
  templates/customer-service.yaml
  templates/customer-route.yaml
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
echo "  Deploy FantaCo Customer Backend"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo "Namespaces:   ${NAMESPACES[*]}"
echo "Components:   postgresql-customer, fantaco-customer-main, mcp-customer"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Deploying to namespace: $NS ==="

  # ── Render and apply fantaco-app customer templates ──────────────
  echo "  Applying customer backend resources..."
  SHOW_ARGS=()
  for t in "${APP_TEMPLATES[@]}"; do
    SHOW_ARGS+=(-s "$t")
  done

  if ! helm template fantaco-app "$HELM_DIR/fantaco-app" -n "$NS" "${SHOW_ARGS[@]}" \
    | oc apply -n "$NS" -f - 2>&1 | sed 's/^/    /'; then
    echo "  ⚠ fantaco-app customer apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # ── Wait for customer backend pods (2 pods) ─────────────────────
  echo "  Waiting for customer backend pods (up to 120s)..."
  SECONDS=0
  while [[ $SECONDS -lt 120 ]]; do
    READY=$(oc get pods -n "$NS" --no-headers 2>/dev/null \
      | grep -E "(fantaco-customer-main|postgresql-customer)" \
      | grep -c "Running" || true)
    if [[ $READY -ge 2 ]]; then
      break
    fi
    sleep 5
  done

  if [[ $READY -ge 2 ]]; then
    echo "  ✓ customer backend: $READY/2 pods running"
  else
    echo "  ⚠ customer backend: only $READY/2 pods running after 120s"
    echo "    Check: oc get pods -n $NS"
  fi

  # ── Render and apply fantaco-mcp customer templates ──────────────
  echo "  Applying customer MCP server resources..."
  SHOW_ARGS=()
  for t in "${MCP_TEMPLATES[@]}"; do
    SHOW_ARGS+=(-s "$t")
  done

  if ! helm template fantaco-mcp "$HELM_DIR/fantaco-mcp" -n "$NS" "${SHOW_ARGS[@]}" \
    | oc apply -n "$NS" -f - 2>&1 | sed 's/^/    /'; then
    echo "  ⚠ fantaco-mcp customer apply failed for $NS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # ── Wait for all 3 pods ─────────────────────────────────────────
  echo "  Waiting for all pods (up to 120s)..."
  SECONDS=0
  while [[ $SECONDS -lt 120 ]]; do
    TOTAL_READY=$(oc get pods -n "$NS" --no-headers 2>/dev/null \
      | grep -E "(fantaco-customer-main|postgresql-customer|mcp-customer)" \
      | grep -c "Running" || true)
    if [[ $TOTAL_READY -ge 3 ]]; then
      break
    fi
    sleep 5
  done

  if [[ $TOTAL_READY -ge 3 ]]; then
    echo "  ✓ All $TOTAL_READY/3 pods running"
  else
    echo "  ⚠ Only $TOTAL_READY/3 pods running after 120s"
    echo "    Check: oc get pods -n $NS"
  fi

  # ── Smoke tests ──────────────────────────────────────────────────
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

  MCP_ROUTE=$(oc get route mcp-customer-route -n "$NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$MCP_ROUTE" ]]; then
    echo "    mcp-customer: https://${MCP_ROUTE}"
  fi

  # ── Print routes ─────────────────────────────────────────────────
  echo "  Routes:"
  oc get routes -n "$NS" --no-headers 2>/dev/null \
    | grep -E "(fantaco-customer|mcp-customer)" \
    | awk '{printf "    %-45s https://%s\n", $1, $2}' || true

  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  echo ""
done

# ── Summary ────────────────────────────────────────────────────────
echo "============================================"
echo "  Deployment Summary"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo ""
