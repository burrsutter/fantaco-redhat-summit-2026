#!/usr/bin/env bash

# Smoke test for all FantaCo MCP servers
# Sends JSON-RPC initialize and tools/list requests via HTTP streamable transport
#
# Usage:
#   ./smoke-test-mcp-servers.sh            # test via OpenShift routes
#   ./smoke-test-mcp-servers.sh --local     # test via localhost ports

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

# Parse arguments
MODE="openshift"
for arg in "$@"; do
  case "$arg" in
    --local|-l) MODE="local" ;;
    --help|-h)
      echo "Usage: $0 [--local]"
      echo ""
      echo "  --local, -l   Test MCP servers on localhost (ports 9001-9006)"
      echo "  (default)     Test MCP servers via OpenShift routes"
      exit 0
      ;;
  esac
done

FAILURES=0

# MCP server definitions: route_name|label|local_port
MCP_SERVERS=(
  "mcp-customer-route|Customer MCP|9001"
  "mcp-finance-route|Finance MCP|9002"
  "mcp-product-route|Product MCP|9003"
  "mcp-sales-order-route|Sales Order MCP|9004"
  "mcp-hr-recruiting-route|HR Recruiting MCP|9005"
  "mcp-sales-policy-search-route|Sales Policy Search MCP|9006"
)

# JSON-RPC payloads
INIT_PAYLOAD='{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {},
    "clientInfo": { "name": "SmokeTest", "version": "1.0" }
  }
}'

TOOLS_PAYLOAD='{
  "jsonrpc": "2.0",
  "id": "2",
  "method": "tools/list"
}'

# Results for summary table
declare -a RESULTS

echo ""
echo -e "${BOLD}FantaCo MCP Server Smoke Tests${NC}"
if [ "$MODE" = "local" ]; then
  echo -e "  Mode: ${BOLD}localhost${NC}"
else
  echo -e "  Mode: ${BOLD}OpenShift routes${NC}"
fi
echo "==============================="
echo ""

for entry in "${MCP_SERVERS[@]}"; do
  IFS='|' read -r route_name label local_port <<< "$entry"

  # Determine the MCP URL based on mode
  if [ "$MODE" = "local" ]; then
    # Localhost mode — no TLS, use -s only (not -k)
    mcp_url="http://localhost:${local_port}/mcp"
    curl_tls_flags="-s"

    # Quick check if port is listening
    if ! curl -s --max-time 2 -o /dev/null "http://localhost:${local_port}" 2>/dev/null; then
      echo -e "  ${YELLOW}SKIP${NC}  $label — localhost:${local_port} not reachable"
      echo ""
      RESULTS+=("$label|SKIP|SKIP")
      continue
    fi
  else
    # OpenShift mode — get route host
    host=$(kubectl get route "$route_name" -o jsonpath='{.spec.host}' 2>/dev/null)

    if [ -z "$host" ]; then
      echo -e "  ${YELLOW}SKIP${NC}  $label — route $route_name not found"
      echo ""
      RESULTS+=("$label|SKIP|SKIP")
      continue
    fi

    mcp_url="https://${host}/mcp"
    curl_tls_flags="-sk"
  fi

  # Initialize request — capture headers, body, and status code
  response=$(curl $curl_tls_flags -D - -o - \
    -X POST "$mcp_url" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT_PAYLOAD" \
    --max-time 15 2>/dev/null)

  # Split headers and body (separated by blank line)
  headers=$(echo "$response" | sed '/^\r$/q')
  body=$(echo "$response" | sed '1,/^\r$/d')

  # Extract HTTP status code from first header line
  init_code=$(echo "$headers" | head -1 | grep -oE '[0-9]{3}' | head -1)

  if [ "$init_code" = "200" ] && echo "$body" | grep -q '"serverInfo"'; then
    init_result="PASS"
    init_display="$PASS"
  else
    init_result="FAIL"
    init_display="$FAIL (HTTP ${init_code:-000})"
    FAILURES=$((FAILURES + 1))
  fi

  # Extract Mcp-Session-Id from response headers
  session_id=$(echo "$headers" | grep -i 'mcp-session-id' | sed 's/.*: *//;s/\r//')

  # tools/list request
  if [ -n "$session_id" ] && [ "$init_result" = "PASS" ]; then
    tools_response=$(curl $curl_tls_flags \
      -X POST "$mcp_url" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -H "Mcp-Session-Id: $session_id" \
      -d "$TOOLS_PAYLOAD" \
      -w "\n%{http_code}" \
      --max-time 15 2>/dev/null)

    tools_code=$(echo "$tools_response" | tail -1)
    tools_body=$(echo "$tools_response" | sed '$d')

    if [ "$tools_code" = "200" ] && echo "$tools_body" | grep -q '"tools"'; then
      tools_result="PASS"
      tools_display="$PASS"
    else
      tools_result="FAIL"
      tools_display="$FAIL (HTTP ${tools_code:-000})"
      FAILURES=$((FAILURES + 1))
    fi
  elif [ "$init_result" = "PASS" ]; then
    # Initialize passed but no session ID returned — try without it
    tools_response=$(curl $curl_tls_flags \
      -X POST "$mcp_url" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d "$TOOLS_PAYLOAD" \
      -w "\n%{http_code}" \
      --max-time 15 2>/dev/null)

    tools_code=$(echo "$tools_response" | tail -1)
    tools_body=$(echo "$tools_response" | sed '$d')

    if [ "$tools_code" = "200" ] && echo "$tools_body" | grep -q '"tools"'; then
      tools_result="PASS"
      tools_display="$PASS"
    else
      tools_result="FAIL"
      tools_display="$FAIL (HTTP ${tools_code:-000})"
      FAILURES=$((FAILURES + 1))
    fi
  else
    tools_result="SKIP"
    tools_display="$SKIP"
  fi

  echo -e "  $label"
  echo -e "    Initialize:  $init_display"
  echo -e "    Tools List:  $tools_display"
  echo ""

  RESULTS+=("$label|$init_result|$tools_result")
done

# Summary table
echo -e "${BOLD}Summary${NC}"
echo "---------------------------------------------------"
printf "  %-18s  %-12s  %-12s\n" "Service" "Initialize" "Tools List"
echo "---------------------------------------------------"
for r in "${RESULTS[@]}"; do
  IFS='|' read -r label init tools <<< "$r"
  case "$init" in
    PASS) i="${GREEN}PASS${NC}" ;;
    FAIL) i="${RED}FAIL${NC}" ;;
    *)    i="${YELLOW}SKIP${NC}" ;;
  esac
  case "$tools" in
    PASS) t="${GREEN}PASS${NC}" ;;
    FAIL) t="${RED}FAIL${NC}" ;;
    *)    t="${YELLOW}SKIP${NC}" ;;
  esac
  printf "  %-18s  %-21b  %-21b\n" "$label" "$i" "$t"
done
echo "---------------------------------------------------"
echo ""

if [ "$FAILURES" -gt 0 ]; then
  echo -e "${RED}${FAILURES} check(s) failed.${NC}"
  exit 1
else
  echo -e "${GREEN}All checks passed.${NC}"
  exit 0
fi
