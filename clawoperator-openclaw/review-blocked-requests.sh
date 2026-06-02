#!/usr/bin/env bash
# review-blocked-requests.sh — Query Loki for blocked proxy requests across all namespaces
#
# Uses aggregated Loki logs (survives pod restarts, much faster than per-pod queries).
# Supports multi-cluster via clusters.csv (same format as update-broker.sh).
# Multi-site: use --site backup to target backup site clusters.
#
# Usage:
#   ./review-blocked-requests.sh              # all namespaces, last 1h (primary)
#   ./review-blocked-requests.sh --site backup 1h  # backup site
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Extract --site flag before positional args
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE_NAME="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--site NAME] [time_range] [user_filter]"
      echo ""
      echo "  --site NAME    Site config to use (default: primary)"
      echo "  time_range     Duration: 1h, 30m, 24h, 7d (default: 1h)"
      echo "  user_filter    Namespace filter: user2, agentic-user5, etc."
      exit 0
      ;;
    *) POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Load site config (sets CLUSTERS_CSV to per-site file if it exists)
source "${SCRIPT_DIR}/sites/resolve-site.sh"

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

# ── Build cluster list ──────────────────────────────────────────────
# Each entry: "cluster_id kubeconfig_path"
CLUSTER_ENTRIES=()

if [[ -f "$CLUSTERS_CSV" ]]; then
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if [[ ! -f "$kubeconfig_path" ]]; then
      echo -e "${RED}ERROR: Cluster ${cluster_id}: kubeconfig not found: ${kubeconfig_path}${RESET}"
      exit 1
    fi
    if ! KUBECONFIG="$kubeconfig_path" oc whoami &>/dev/null; then
      echo -e "${RED}ERROR: Cluster ${cluster_id}: not logged in (KUBECONFIG=${kubeconfig_path})${RESET}"
      exit 1
    fi
    CLUSTER_ENTRIES+=("${cluster_id} ${kubeconfig_path}")
  done < "$CLUSTERS_CSV"

  if [[ ${#CLUSTER_ENTRIES[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR: clusters.csv has no valid entries.${RESET}"
    exit 1
  fi
else
  # Single-cluster fallback — verify login, use current context
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged in to OpenShift. Run 'oc login' first.${RESET}"
    exit 1
  fi
  CLUSTER_ENTRIES+=("default ${KUBECONFIG:-$HOME/.kube/config}")
fi

MULTI_CLUSTER=false
[[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]] && MULTI_CLUSTER=true

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
if $MULTI_CLUSTER; then
  CLUSTER_IDS=()
  for entry in "${CLUSTER_ENTRIES[@]}"; do CLUSTER_IDS+=("${entry%% *}"); done
  echo -e "  Clusters: ${CYAN}$(IFS=', '; echo "${CLUSTER_IDS[*]}")${RESET}"
fi
echo -e "  Namespace: ${CYAN}${NS_FILTER:-all}${RESET}"
echo -e "  Time window: ${CYAN}${TIMERANGE}${RESET}"
echo ""

# ── Query Loki on each cluster ──────────────────────────────────────
ALL_RESPONSES=""

for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  TOKEN=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc whoami -t 2>/dev/null) || {
    echo -e "${RED}ERROR: Could not get token for cluster ${CLUSTER_ID}${RESET}"
    exit 1
  }

  LOKI_ROUTE=$(KUBECONFIG="$CLUSTER_KUBECONFIG" oc get route -n openshift-logging logging-loki -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$LOKI_ROUTE" ]]; then
    echo -e "${YELLOW}Warning: Loki not deployed on cluster ${CLUSTER_ID} — skipping${RESET}"
    continue
  fi
  LOKI_URL="https://${LOKI_ROUTE}"

  echo -e "${DIM}Querying Loki on ${CLUSTER_ID}...${RESET}"

  RESPONSE=$(curl -sk \
    -H "Authorization: Bearer $TOKEN" \
    "${LOKI_URL}/api/logs/v1/application/loki/api/v1/query_range" \
    --data-urlencode "query=${QUERY}" \
    --data-urlencode "limit=1000" \
    --data-urlencode "start=${START}" \
    --data-urlencode "end=${NOW}" 2>&1)

  ALL_RESPONSES+="===CLUSTER:${CLUSTER_ID}==="$'\n'"${RESPONSE}"$'\n'
done

if [[ -z "$ALL_RESPONSES" ]]; then
  echo -e "${RED}ERROR: Loki not deployed on any cluster.${RESET}"
  exit 1
fi

echo "$ALL_RESPONSES" | python3 -c "
import json, sys, re
from collections import Counter, defaultdict

raw = sys.stdin.read()
multi_cluster = $($MULTI_CLUSTER && echo 'True' || echo 'False')

# Split by cluster delimiter
chunks = re.split(r'===CLUSTER:([^=]+)===\n', raw)
# chunks = ['', cluster_id_1, json_1, cluster_id_2, json_2, ...]

domain_counts = Counter()
domain_namespaces = defaultdict(set)
domain_clusters = defaultdict(set)
domain_times = defaultdict(list)
total = 0
errors = []

i = 1
while i < len(chunks):
    cluster_id = chunks[i].strip()
    body = chunks[i+1].strip() if i+1 < len(chunks) else ''
    i += 2

    if not body:
        continue

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        errors.append(f'Failed to parse Loki response from {cluster_id}')
        continue

    status = data.get('status', '?')
    results = data.get('data', {}).get('result', [])

    if status != 'success':
        errors.append(f'Loki query failed on {cluster_id}: {status}')
        continue

    for stream in results:
        ns = stream.get('stream', {}).get('k8s_namespace_name', '?')
        for ts, line in stream.get('values', []):
            total += 1
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
                m = re.search(r'\"host\":\"([^\"]+)\"', line)
                if m:
                    domain = re.sub(r':\d+$', '', m.group(1))

            domain_counts[domain] += 1
            domain_namespaces[domain].add(ns)
            domain_clusters[domain].add(cluster_id)
            if timestamp and timestamp != '-':
                domain_times[domain].append(timestamp)

for err in errors:
    print(f'\033[1;33m{err}\033[0m')

if total == 0:
    print('\033[0;32mNo blocked requests found.\033[0m')
    sys.exit(0)

print(f'\033[1;31mFound {total} blocked request(s) across {len(domain_counts)} unique domain(s)\033[0m')
print()

if multi_cluster:
    print(f'\033[1m{\"Count\":>5}  {\"Domain\":<40}  {\"Clusters\":<17}  {\"Namespaces\":<35}  Last seen\033[0m')
    print(f'{\"-----\":>5}  {\"-\"*40}  {\"-\"*17}  {\"-\"*35}  ---------')
    for domain, count in domain_counts.most_common():
        ns_list = sorted(domain_namespaces[domain], key=lambda x: (len(x), x))
        cl_list = sorted(domain_clusters[domain])
        if len(ns_list) > 4:
            ns_str = ', '.join(ns_list[:4]) + f' (+{len(ns_list)-4} more)'
        else:
            ns_str = ', '.join(ns_list)
        cl_str = ', '.join(cl_list)
        last_seen = sorted(domain_times.get(domain, []))[-1] if domain_times.get(domain) else '-'
        print(f'{count:>5}  \033[1;33m{domain:<40}\033[0m  {cl_str:<17}  \033[0;36m{ns_str:<35}\033[0m  \033[2m{last_seen}\033[0m')
else:
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
