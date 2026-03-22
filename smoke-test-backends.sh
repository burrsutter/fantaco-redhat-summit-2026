#!/usr/bin/env bash

# Smoke test for all FantaCo backend services on OpenShift
# Checks health and data endpoints via their routes

# Colors (disabled for non-TTY)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' RED='' YELLOW='' BOLD='' NC=''
fi

PASS="${GREEN}PASS${NC}"
FAIL="${RED}FAIL${NC}"
SKIP="${YELLOW}SKIP${NC}"

FAILURES=0

# Service definitions: route_name|label|health_path|data_path
SERVICES=(
  "fantaco-customer-route|Customer|/actuator/health/liveness|/api/customers"
  "fantaco-finance-route|Finance|/actuator/health/liveness|/api/finance/invoices"
  "fantaco-product-route|Product|/actuator/health/liveness|/api/products"
  "fantaco-sales-order-route|Sales Order|/actuator/health/liveness|/api/sales-orders"
  "fantaco-hr-recruiting-route|HR Recruiting|/actuator/health/liveness|/api/jobs"
)

# Results for summary table
declare -a RESULTS

echo ""
echo -e "${BOLD}FantaCo Backend Smoke Tests${NC}"
echo "==========================="
echo ""

for entry in "${SERVICES[@]}"; do
  IFS='|' read -r route_name label health_path data_path <<< "$entry"

  # Get route host
  host=$(kubectl get route "$route_name" -o jsonpath='{.spec.host}' 2>/dev/null)

  if [ -z "$host" ]; then
    echo -e "  ${YELLOW}SKIP${NC}  $label — route $route_name not found"
    RESULTS+=("$label|SKIP|SKIP")
    continue
  fi

  base_url="https://${host}"

  # Health check
  health_code=$(curl -sk -o /dev/null -w "%{http_code}" "${base_url}${health_path}" --max-time 10)
  if [ "$health_code" = "200" ]; then
    health_result="PASS"
    health_display="$PASS"
  else
    health_result="FAIL"
    health_display="$FAIL (HTTP $health_code)"
    FAILURES=$((FAILURES + 1))
  fi

  # Data check
  data_code=$(curl -sk -o /dev/null -w "%{http_code}" "${base_url}${data_path}" --max-time 10)
  if [ "$data_code" = "200" ]; then
    data_result="PASS"
    data_display="$PASS"
  else
    data_result="FAIL"
    data_display="$FAIL (HTTP $data_code)"
    FAILURES=$((FAILURES + 1))
  fi

  echo -e "  $label"
  echo -e "    Health:  $health_display"
  echo -e "    Data:    $data_display"
  echo ""

  RESULTS+=("$label|$health_result|$data_result")
done

# Summary table
echo -e "${BOLD}Summary${NC}"
echo "-------------------------------------------"
printf "  %-16s  %-8s  %-8s\n" "Service" "Health" "Data"
echo "-------------------------------------------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r label health data <<< "$r"
  # Colorize summary
  case "$health" in
    PASS) h="${GREEN}PASS${NC}" ;;
    FAIL) h="${RED}FAIL${NC}" ;;
    *)    h="${YELLOW}SKIP${NC}" ;;
  esac
  case "$data" in
    PASS) d="${GREEN}PASS${NC}" ;;
    FAIL) d="${RED}FAIL${NC}" ;;
    *)    d="${YELLOW}SKIP${NC}" ;;
  esac
  printf "  %-16s  %-17b  %-17b\n" "$label" "$h" "$d"
done
echo "-------------------------------------------"
echo ""

if [ "$FAILURES" -gt 0 ]; then
  echo -e "${RED}${FAILURES} check(s) failed.${NC}"
  exit 1
else
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
fi
