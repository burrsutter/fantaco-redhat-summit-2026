#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the broker running locally
# Usage: ./test/smoke.sh [port]

PORT="${1:-3001}"
BASE="http://localhost:${PORT}"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Smoke Test (port $PORT) ==="

# Clean up any existing routes CSV to ensure we start fresh
rm -f "${ROUTES_CSV_PATH:-./routes.csv}"

# 1. Status API — empty
echo ""
echo "--- Status API (empty) ---"
STATUS=$(curl -s "$BASE/status/api")
check "empty stats" '"total":0' "$STATUS"

# 2. Load test routes via admin reset
echo ""
echo "--- Load routes via CSV ---"
CSV_FILE=$(mktemp)
cat > "$CSV_FILE" <<EOF
# public_host,openshift_route_host,enabled
claw-test1-aaa.yougetaclaw.com,claw-test1-aaa.apps.ocp.example.com,true
claw-test1-bbb.yougetaclaw.com,claw-test1-bbb.apps.ocp.example.com,true
claw-test1-ccc.yougetaclaw.com,claw-test1-ccc.apps.ocp.example.com,true
EOF

# Copy to where the broker expects it
cp "$CSV_FILE" "${ROUTES_CSV_PATH:-./routes.csv}"
RESET=$(curl -s -X POST "$BASE/admin/reset")
check "reset loads 3 routes" '"total":3' "$RESET"
check "audience id extracted" '"audience_id":"test1"' "$RESET"

# 3. New user gets redirected
echo ""
echo "--- Session Assignment ---"
RESP=$(curl -s -i "$BASE/" 2>&1)
HTTP_CODE=$(echo "$RESP" | grep "HTTP/" | head -1 | awk '{print $2}')
REDIRECT_URL=$(echo "$RESP" | grep -i "location:" | head -1 | awk '{print $2}' | tr -d '\r')
COOKIE_VALUE=$(echo "$RESP" | grep -i "set-cookie" | sed -n 's/.*rlb_session=\([^;]*\).*/\1/p' | head -1)

check "new user gets 302" "302" "$HTTP_CODE"
check "redirect to claw-test1" "claw-test1" "$REDIRECT_URL"

# 4. Returning user gets same redirect
if [ -n "$COOKIE_VALUE" ]; then
  RESP2=$(curl -s -i -H "Cookie: rlb_session=$COOKIE_VALUE" "$BASE/" 2>&1)
  REDIRECT_URL2=$(echo "$RESP2" | grep -i "location:" | head -1 | awk '{print $2}' | tr -d '\r')
  check "returning user same URL" "$REDIRECT_URL" "$REDIRECT_URL2"
else
  echo "  SKIP: returning user test (could not extract cookie)"
fi

# 5. Fill all slots
curl -s -o /dev/null "$BASE/"
curl -s -o /dev/null "$BASE/"

# 6. Next user gets 503
RESP_FULL=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/")
check "full house returns 503" "503" "$RESP_FULL"

# 7. Status shows 3 assigned
STATUS2=$(curl -s "$BASE/status/api")
check "3 assigned" '"assigned":3' "$STATUS2"
check "0 available" '"available":0' "$STATUS2"

# 8. Release one slot
ROUTE_ID=$(echo "$STATUS2" | python3 -c "import sys,json; print(json.load(sys.stdin)['routes'][0]['id'])")
RELEASE=$(curl -s -X POST "$BASE/admin/release/$ROUTE_ID")
check "release succeeds" '"ok":true' "$RELEASE"

# 9. Status shows 2 assigned
STATUS3=$(curl -s "$BASE/status/api")
check "2 assigned after release" '"assigned":2' "$STATUS3"

# 10. Status HTML page loads
STATUS_HTML=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/status")
check "status page returns 200" "200" "$STATUS_HTML"

# Cleanup
rm -f "$CSV_FILE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
