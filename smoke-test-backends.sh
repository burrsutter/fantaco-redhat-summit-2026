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
  "fantaco-customer-service|Customer|/actuator/health/liveness|/api/customers"
  "fantaco-finance-service|Finance|/actuator/health/liveness|/api/finance/invoices"
  "fantaco-product-service|Product|/actuator/health/liveness|/api/products"
  "fantaco-sales-order-service|Sales Order|/actuator/health/liveness|/api/sales-orders"
  "fantaco-hr-recruiting-service|HR Recruiting|/actuator/health/liveness|/api/jobs"
  "fantaco-sales-policy-search-route|Sales Policy|/health|/api/sales-policy/documents"
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

# =====================================================
# Customer CRM Smoke Tests (contacts & notes)
# =====================================================
echo -e "${BOLD}Customer CRM Smoke Tests${NC}"
echo "-------------------------------------------"
echo ""

CRM_RESULT="SKIP"
customer_host=$(kubectl get route "fantaco-customer-service" -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$customer_host" ]; then
  echo -e "  ${YELLOW}SKIP${NC}  CRM tests — customer route not found"
  echo ""
else
  customer_url="https://${customer_host}"
  CRM_RESULT="PASS"

  # --- Test: Create a contact for CUST001 ---
  echo -e "  Creating contact for CUST001..."
  create_contact_body='{"firstName":"Test","lastName":"Smokecheck","email":"test.smoke@example.com","title":"QA","phone":"(555) 000-0001","notes":"Created by smoke test"}'
  create_contact_response=$(curl -sk -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$create_contact_body" \
    "${customer_url}/api/customers/CUST001/contacts" --max-time 10)
  create_contact_code=$(echo "$create_contact_response" | tail -1)
  create_contact_json=$(echo "$create_contact_response" | sed '$d')

  if [ "$create_contact_code" = "201" ]; then
    echo -e "    Create Contact:  $PASS"
    # Extract contact ID for update and cleanup
    contact_id=$(echo "$create_contact_json" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  else
    echo -e "    Create Contact:  $FAIL (HTTP $create_contact_code)"
    CRM_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
    contact_id=""
  fi

  # --- Test: Update the contact ---
  if [ -n "$contact_id" ]; then
    echo -e "  Updating contact $contact_id..."
    update_contact_body='{"firstName":"Test","lastName":"Smokecheck-Updated","email":"test.smoke.updated@example.com","title":"QA Lead","phone":"(555) 000-0002","notes":"Updated by smoke test"}'
    update_contact_code=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      -d "$update_contact_body" \
      "${customer_url}/api/customers/CUST001/contacts/${contact_id}" --max-time 10)

    if [ "$update_contact_code" = "200" ]; then
      echo -e "    Update Contact:  $PASS"
    else
      echo -e "    Update Contact:  $FAIL (HTTP $update_contact_code)"
      CRM_RESULT="FAIL"
      FAILURES=$((FAILURES + 1))
    fi

    # --- Test: Read the updated contact back ---
    echo -e "  Reading contact $contact_id..."
    read_contact_code=$(curl -sk -o /dev/null -w "%{http_code}" \
      "${customer_url}/api/customers/CUST001/contacts/${contact_id}" --max-time 10)

    if [ "$read_contact_code" = "200" ]; then
      echo -e "    Read Contact:    $PASS"
    else
      echo -e "    Read Contact:    $FAIL (HTTP $read_contact_code)"
      CRM_RESULT="FAIL"
      FAILURES=$((FAILURES + 1))
    fi

    # --- Cleanup: Delete the contact ---
    echo -e "  Cleaning up contact $contact_id..."
    delete_contact_code=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE \
      "${customer_url}/api/customers/CUST001/contacts/${contact_id}" --max-time 10)

    if [ "$delete_contact_code" = "204" ]; then
      echo -e "    Delete Contact:  $PASS"
    else
      echo -e "    Delete Contact:  $FAIL (HTTP $delete_contact_code)"
      CRM_RESULT="FAIL"
      FAILURES=$((FAILURES + 1))
    fi
  fi

  echo ""

  # --- Test: Create a note for CUST001 ---
  echo -e "  Creating note for CUST001..."
  create_note_body='{"noteText":"Smoke test note - verifying CRM note functionality"}'
  create_note_response=$(curl -sk -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$create_note_body" \
    "${customer_url}/api/customers/CUST001/notes" --max-time 10)
  create_note_code=$(echo "$create_note_response" | tail -1)
  create_note_json=$(echo "$create_note_response" | sed '$d')

  if [ "$create_note_code" = "201" ]; then
    echo -e "    Create Note:     $PASS"
    note_id=$(echo "$create_note_json" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  else
    echo -e "    Create Note:     $FAIL (HTTP $create_note_code)"
    CRM_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
    note_id=""
  fi

  # --- Test: Read notes for CUST001 ---
  echo -e "  Listing notes for CUST001..."
  list_notes_code=$(curl -sk -o /dev/null -w "%{http_code}" \
    "${customer_url}/api/customers/CUST001/notes" --max-time 10)

  if [ "$list_notes_code" = "200" ]; then
    echo -e "    List Notes:      $PASS"
  else
    echo -e "    List Notes:      $FAIL (HTTP $list_notes_code)"
    CRM_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
  fi

  # --- Cleanup: Delete the note ---
  if [ -n "$note_id" ]; then
    echo -e "  Cleaning up note $note_id..."
    delete_note_code=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE \
      "${customer_url}/api/customers/CUST001/notes/${note_id}" --max-time 10)

    if [ "$delete_note_code" = "204" ]; then
      echo -e "    Delete Note:     $PASS"
    else
      echo -e "    Delete Note:     $FAIL (HTTP $delete_note_code)"
      CRM_RESULT="FAIL"
      FAILURES=$((FAILURES + 1))
    fi
  fi

  echo ""

  # --- Test: Get customer detail (aggregate endpoint) ---
  echo -e "  Getting customer detail for CUST001..."
  detail_code=$(curl -sk -o /dev/null -w "%{http_code}" \
    "${customer_url}/api/customers/CUST001/detail" --max-time 10)

  if [ "$detail_code" = "200" ]; then
    echo -e "    Customer Detail: $PASS"
  else
    echo -e "    Customer Detail: $FAIL (HTTP $detail_code)"
    CRM_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
  fi

  echo ""
fi

# =====================================================
# Sales Policy RAG Search Smoke Test
# =====================================================
echo -e "${BOLD}Sales Policy RAG Search Smoke Test${NC}"
echo "-------------------------------------------"
echo ""

RAG_RESULT="SKIP"
rag_host=$(kubectl get route "fantaco-sales-policy-search-route" -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$rag_host" ]; then
  echo -e "  ${YELLOW}SKIP${NC}  RAG search test — route not found"
  echo ""
else
  rag_url="https://${rag_host}"
  RAG_RESULT="PASS"

  # --- Test: RAG search query ---
  echo -e "  Searching: \"What is the return policy for defective products?\"..."
  search_body='{"query":"What is the return policy for defective products?","top_k":3}'
  search_response=$(curl -sk -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$search_body" \
    "${rag_url}/api/sales-policy/search" --max-time 60)
  search_code=$(echo "$search_response" | tail -1)
  search_json=$(echo "$search_response" | sed '$d')

  if [ "$search_code" = "200" ] && echo "$search_json" | grep -q '"success":true'; then
    echo -e "    RAG Search:  $PASS"
    # Show a snippet of the answer
    answer_preview=$(echo "$search_json" | grep -o '"answer":"[^"]*' | head -1 | cut -c11-110)
    if [ -n "$answer_preview" ]; then
      echo -e "    Answer:      ${answer_preview}..."
    fi
  else
    echo -e "    RAG Search:  $FAIL (HTTP $search_code)"
    RAG_RESULT="FAIL"
    FAILURES=$((FAILURES + 1))
  fi

  echo ""
fi

# Summary table
echo -e "${BOLD}Summary${NC}"
echo "---------------------------------------------------------------"
printf "  %-16s  %-8s  %-8s  %-8s  %-8s\n" "Service" "Health" "Data" "CRM" "RAG"
echo "---------------------------------------------------------------"
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
  # CRM column only applies to Customer service
  if [ "$label" = "Customer" ]; then
    case "$CRM_RESULT" in
      PASS) c="${GREEN}PASS${NC}" ;;
      FAIL) c="${RED}FAIL${NC}" ;;
      *)    c="${YELLOW}SKIP${NC}" ;;
    esac
  else
    c="—"
  fi
  # RAG column only applies to Sales Policy service
  if [ "$label" = "Sales Policy" ]; then
    case "$RAG_RESULT" in
      PASS) rg="${GREEN}PASS${NC}" ;;
      FAIL) rg="${RED}FAIL${NC}" ;;
      *)    rg="${YELLOW}SKIP${NC}" ;;
    esac
  else
    rg="—"
  fi
  printf "  %-16s  %-17b  %-17b  %-17b  %-17b\n" "$label" "$h" "$d" "$c" "$rg"
done
echo "---------------------------------------------------------------"
echo ""

if [ "$FAILURES" -gt 0 ]; then
  echo -e "${RED}${FAILURES} check(s) failed.${NC}"
  exit 1
else
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
fi
