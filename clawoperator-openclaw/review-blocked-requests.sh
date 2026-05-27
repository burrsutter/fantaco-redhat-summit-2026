#!/usr/bin/env bash
# review-blocked-requests.sh — Query Loki for blocked proxy requests across all namespaces
#
# Uses aggregated Loki logs (survives pod restarts, much faster than per-pod queries).
#
# Usage:
#   ./review-blocked-requests.sh              # all namespaces, last 1h
#   ./review-blocked-requests.sh 24h          # last 24 hours
#   ./review-blocked-requests.sh 30m user2    # last 30 min, only agentic-user2
#   ./review-blocked-requests.sh 7d user5     # last 7 days, only agentic-user5

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

TIMERANGE="${1:-1h}"
NS_FILTER="${2:-}"

# Parse time range to seconds
parse_duration() {
  local val="${1%[smhd]}"
  local unit="${1: -1}"
  case "$unit" in
    s) echo "$val" ;;
    m) echo $((val * 60)) ;;
    h) echo $((val * 3600)) ;;
    d) echo $((val * 86400)) ;;
    *) echo $((val * 3600)) ;;
  esac
}

SECONDS_AGO=$(parse_duration "$TIMERANGE")
NOW=$(date +%s)
START=$((NOW - SECONDS_AGO))

# Verify oc login
TOKEN=$(oc whoami -t 2>/dev/null) || { echo -e "${RED}ERROR: Not logged in to OpenShift. Run 'oc login' first.${RESET}"; exit 1; }

# Find Loki route
LOKI_ROUTE=$(oc get route -n openshift-logging logging-loki -o jsonpath='{.spec.host}' 2>/dev/null) || { echo -e "${RED}ERROR: Loki route not found. Is logging deployed?${RESET}"; exit 1; }
LOKI_URL="https://${LOKI_ROUTE}"

# Build LogQL query
if [[ -n "$NS_FILTER" ]]; then
  # Support shorthand: "user2" → "agentic-user2"
  [[ "$NS_FILTER" != agentic-* ]] && NS_FILTER="agentic-${NS_FILTER}"
  QUERY="{k8s_container_name=\"proxy\", k8s_namespace_name=\"${NS_FILTER}\"} |~ \"blocked\""
else
  QUERY='{k8s_container_name="proxy"} |~ "blocked"'
fi

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Blocked Request Scanner (Loki)${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""
echo -e "  Namespace: ${CYAN}${NS_FILTER:-all}${RESET}"
echo -e "  Time window: ${CYAN}${TIMERANGE}${RESET}"
echo ""
echo -e "${DIM}Querying Loki...${RESET}"

RESPONSE=$(curl -sk \
  -H "Authorization: Bearer $TOKEN" \
  "${LOKI_URL}/api/logs/v1/application/loki/api/v1/query_range" \
  --data-urlencode "query=${QUERY}" \
  --data-urlencode "limit=1000" \
  --data-urlencode "start=${START}" \
  --data-urlencode "end=${NOW}" 2>&1)

echo "$RESPONSE" | python3 -c "
import json, sys, re
from collections import Counter, defaultdict

data = json.load(sys.stdin)
status = data.get('status', '?')
results = data.get('data', {}).get('result', [])

if status != 'success':
    print(f'Loki query failed: {status}')
    sys.exit(1)

domain_counts = Counter()
domain_namespaces = defaultdict(set)
domain_times = defaultdict(list)
total = 0

for stream in results:
    ns = stream.get('stream', {}).get('k8s_namespace_name', '?')
    for ts, line in stream.get('values', []):
        total += 1
        # Loki wraps the original log in a JSON envelope with a 'message' field
        domain = '(unknown)'
        timestamp = '-'
        try:
            outer = json.loads(line)
            msg = outer.get('message', line)
            inner = json.loads(msg) if isinstance(msg, str) else msg
            raw_host = inner.get('host', '')
            if raw_host:
                domain = re.sub(r':\d+$', '', raw_host)
            timestamp = inner.get('time', outer.get('@timestamp', ''))[:19]
        except (json.JSONDecodeError, TypeError):
            # Fallback: regex on raw line
            m = re.search(r'\"host\":\"([^\"]+)\"', line)
            if m:
                domain = re.sub(r':\d+$', '', m.group(1))

        domain_counts[domain] += 1
        domain_namespaces[domain].add(ns)
        if timestamp and timestamp != '-':
            domain_times[domain].append(timestamp)

if total == 0:
    print('\033[0;32mNo blocked requests found.\033[0m')
    sys.exit(0)

print(f'\033[1;31mFound {total} blocked request(s) across {len(domain_counts)} unique domain(s)\033[0m')
print()

print(f'\033[1m{\"Count\":>5}  {\"Domain\":<45}  {\"Namespaces\":<40}  Last seen\033[0m')
print(f'{\"-----\":>5}  {\"-\"*45}  {\"-\"*40}  ---------')
for domain, count in domain_counts.most_common():
    ns_list = sorted(domain_namespaces[domain], key=lambda x: (len(x), x))
    if len(ns_list) > 4:
        ns_str = ', '.join(ns_list[:4]) + f' (+{len(ns_list)-4} more)'
    else:
        ns_str = ', '.join(ns_list)
    last_seen = sorted(domain_times.get(domain, []))[-1] if domain_times.get(domain) else '-'
    print(f'{count:>5}  \033[1;33m{domain:<45}\033[0m  \033[0;36m{ns_str:<40}\033[0m  \033[2m{last_seen}\033[0m')

print()
print('\033[2mTip: Use ./manage-proxy-allowlist.sh allow <domain> [user#] to approve a domain\033[0m')
print()
"
