#!/usr/bin/env bash
# extract-langfuse-traces.sh — Extract user chat interactions from Langfuse traces
#
# Queries the Langfuse API for openclaw-turn traces across all clusters,
# showing what users are actually asking the OpenClaw agents.
#
# Multi-cluster mode:
#   If clusters.csv exists, traces are collected from all listed clusters.
#   Otherwise, uses the current oc context.
#
# Usage:
#   ./extract-langfuse-traces.sh                  # all traces, all clusters
#   ./extract-langfuse-traces.sh --limit 20       # last 20 traces per cluster
#   ./extract-langfuse-traces.sh --user user5     # filter by userId containing "user5"
#   ./extract-langfuse-traces.sh --json           # output as JSON instead of table
#   ./extract-langfuse-traces.sh --limit 10 --user user3 --json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"
TRACES_DIR="${SCRIPT_DIR}/traces"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%S)

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ──────────────────────────────────────────────────
LIMIT=100
USER_FILTER=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --user)
      USER_FILTER="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--limit N] [--user FILTER] [--json]"
      echo ""
      echo "  --limit N      Max traces per cluster (default: 100)"
      echo "  --user FILTER  Filter by userId containing FILTER (e.g. 'user5')"
      echo "  --json         Output as JSON instead of table"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      echo "Usage: $0 [--limit N] [--user FILTER] [--json]"
      exit 1
      ;;
  esac
done

# ── Build cluster list ────────────────────────────────────────────────
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
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}ERROR: Not logged in to OpenShift. Run 'oc login' first.${RESET}"
    exit 1
  fi
  # Extract cluster GUID from current context
  CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
  CLUSTER_ENTRIES+=("${CLUSTER_GUID:-default} ${KUBECONFIG:-$HOME/.kube/config}")
fi

MULTI_CLUSTER=false
[[ ${#CLUSTER_ENTRIES[@]} -gt 1 ]] && MULTI_CLUSTER=true

# When --json is used, send status/progress to stderr so stdout is clean JSON
info() { if $JSON_OUTPUT; then echo -e "$@" >&2; else echo -e "$@"; fi; }

# ── Header ────────────────────────────────────────────────────────────
info ""
info "${BOLD}============================================${RESET}"
info "${BOLD}  Langfuse Trace Extractor${RESET}"
info "${BOLD}============================================${RESET}"
info ""
if $MULTI_CLUSTER; then
  CLUSTER_IDS=()
  for entry in "${CLUSTER_ENTRIES[@]}"; do CLUSTER_IDS+=("${entry%% *}"); done
  info "  Clusters: ${CYAN}$(IFS=', '; echo "${CLUSTER_IDS[*]}")${RESET}"
fi
info "  Limit: ${CYAN}${LIMIT}${RESET} traces per cluster"
[[ -n "$USER_FILTER" ]] && info "  User filter: ${CYAN}${USER_FILTER}${RESET}"
info "  Output: ${CYAN}$($JSON_OUTPUT && echo "JSON" || echo "table")${RESET}"
info ""

# ── Collect traces from all clusters ──────────────────────────────────
mkdir -p "$TRACES_DIR"
ALL_JSON="[]"
SAVED_FILES=()

for entry in "${CLUSTER_ENTRIES[@]}"; do
  CLUSTER_ID="${entry%% *}"
  CLUSTER_KUBECONFIG="${entry#* }"

  export KUBECONFIG="$CLUSTER_KUBECONFIG"

  # Load Langfuse credentials
  LANGFUSE_ENV="${SCRIPT_DIR}/.state/${CLUSTER_ID}/langfuse.env"
  if [[ ! -f "$LANGFUSE_ENV" ]]; then
    info "  ${YELLOW}⚠ Cluster ${CLUSTER_ID}: no langfuse.env found at ${LANGFUSE_ENV} — skipping${RESET}"
    continue
  fi

  # shellcheck disable=SC1090
  source "$LANGFUSE_ENV"

  if [[ -z "${INIT_PUBLIC_KEY:-}" || -z "${INIT_SECRET_KEY:-}" ]]; then
    info "  ${YELLOW}⚠ Cluster ${CLUSTER_ID}: INIT_PUBLIC_KEY or INIT_SECRET_KEY not set — skipping${RESET}"
    continue
  fi

  # Discover Langfuse route
  LANGFUSE_HOST=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$LANGFUSE_HOST" ]]; then
    info "  ${YELLOW}⚠ Cluster ${CLUSTER_ID}: no Langfuse route found — skipping${RESET}"
    continue
  fi

  LANGFUSE_URL="https://${LANGFUSE_HOST}"
  info "  ${DIM}Querying ${CLUSTER_ID} (${LANGFUSE_HOST})...${RESET}"

  # Build user filter query param
  USER_PARAM=""
  if [[ -n "$USER_FILTER" ]]; then
    # Support shorthand: "user5" → "agentic-user5"
    FILTER_VAL="$USER_FILTER"
    [[ "$FILTER_VAL" != agentic-* ]] && FILTER_VAL="agentic-${FILTER_VAL}"
    USER_PARAM="&userId=${FILTER_VAL}"
  fi

  # Paginate through traces
  PAGE=1
  TRACES_COLLECTED=0
  CLUSTER_TRACES="[]"

  while true; do
    RESPONSE=$(curl -sk -u "${INIT_PUBLIC_KEY}:${INIT_SECRET_KEY}" \
      "${LANGFUSE_URL}/api/public/traces?name=openclaw-turn&limit=100&page=${PAGE}${USER_PARAM}" 2>/dev/null) || {
      info "  ${RED}✗ Cluster ${CLUSTER_ID}: API request failed${RESET}"
      break
    }

    # Extract traces and pagination info, merge with cluster ID
    RESULT=$(python3 -c "
import sys, json

try:
    data = json.loads(sys.stdin.read())
except:
    print(json.dumps({'traces': [], 'done': True}))
    sys.exit(0)

traces = data.get('data', [])
meta = data.get('meta', {})
total_pages = meta.get('totalPages', 1)
current_page = meta.get('page', 1)

# Filter out traces with empty input
filtered = []
for t in traces:
    inp = t.get('input')
    if inp is None or inp == '' or inp == {} or inp == []:
        continue
    filtered.append({
        'cluster': '${CLUSTER_ID}',
        'timestamp': t.get('timestamp', ''),
        'userId': t.get('userId', ''),
        'input': inp if isinstance(inp, str) else json.dumps(inp),
        'output': t.get('output', '') if isinstance(t.get('output', ''), str) else json.dumps(t.get('output', '')),
        'latency': t.get('latency', 0),
    })

print(json.dumps({'traces': filtered, 'done': current_page >= total_pages}))
" <<< "$RESPONSE") || {
      info "  ${RED}✗ Cluster ${CLUSTER_ID}: failed to parse response${RESET}"
      break
    }

    # Merge page traces into cluster collection
    CLUSTER_TRACES=$(python3 -c "
import sys, json
existing = json.loads(sys.argv[1])
page_data = json.loads(sys.stdin.read())
existing.extend(page_data['traces'])
print(json.dumps(existing))
" "$CLUSTER_TRACES" <<< "$RESULT")

    DONE=$(python3 -c "import sys,json; print(json.loads(sys.stdin.read())['done'])" <<< "$RESULT")
    PAGE_COUNT=$(python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())['traces']))" <<< "$RESULT")
    TRACES_COLLECTED=$((TRACES_COLLECTED + PAGE_COUNT))

    if [[ "$DONE" == "True" ]] || [[ $TRACES_COLLECTED -ge $LIMIT ]]; then
      break
    fi

    PAGE=$((PAGE + 1))
  done

  # Trim to requested limit
  CLUSTER_TRACES=$(python3 -c "
import sys, json
traces = json.loads(sys.stdin.read())
limit = int(sys.argv[1])
print(json.dumps(traces[:limit]))
" "$LIMIT" <<< "$CLUSTER_TRACES")

  COUNT=$(python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))" <<< "$CLUSTER_TRACES")

  # Save per-cluster JSON file
  if [[ "$COUNT" -gt 0 ]]; then
    USER_TAG=""
    [[ -n "$USER_FILTER" ]] && USER_TAG="-${USER_FILTER}"
    OUTFILE="${TRACES_DIR}/${CLUSTER_ID}${USER_TAG}-${RUN_TS}.json"
    python3 -c "
import sys, json
traces = json.loads(sys.stdin.read())
traces.sort(key=lambda t: t['timestamp'], reverse=True)
print(json.dumps(traces, indent=2))
" <<< "$CLUSTER_TRACES" > "$OUTFILE"
    SAVED_FILES+=("$OUTFILE")
    info "  ${GREEN}✓${RESET} ${CLUSTER_ID}: ${COUNT} traces → ${CYAN}${OUTFILE##*/}${RESET}"
  else
    info "  ${GREEN}✓${RESET} ${CLUSTER_ID}: 0 traces (no file written)"
  fi

  # Merge into global collection
  ALL_JSON=$(python3 -c "
import sys, json
existing = json.loads(sys.argv[1])
new = json.loads(sys.stdin.read())
existing.extend(new)
print(json.dumps(existing))
" "$ALL_JSON" <<< "$CLUSTER_TRACES")
done

info ""

# ── Output ────────────────────────────────────────────────────────────
TOTAL=$(python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))" <<< "$ALL_JSON")

if [[ "$TOTAL" -eq 0 ]]; then
  info "${YELLOW}No traces found.${RESET}"
  exit 0
fi

if $JSON_OUTPUT; then
  # Pretty-print JSON, sorted by timestamp descending
  python3 -c "
import sys, json

traces = json.loads(sys.stdin.read())
traces.sort(key=lambda t: t['timestamp'], reverse=True)
print(json.dumps(traces, indent=2))
" <<< "$ALL_JSON"
else
  # Table output
  python3 -c "
import sys, json

traces = json.loads(sys.stdin.read())
multi = '$MULTI_CLUSTER' == 'true'

# Sort by timestamp descending (most recent first)
traces.sort(key=lambda t: t['timestamp'], reverse=True)

def trunc(s, n):
    s = str(s).replace('\n', ' ').replace('\r', '')
    return (s[:n-3] + '...') if len(s) > n else s

def fmt_ts(ts):
    # '2026-05-29T13:27:16.123Z' → '2026-05-29 13:27:16'
    return ts[:19].replace('T', ' ') if ts else '-'

def fmt_latency(lat):
    if lat is None or lat == 0:
        return '-'
    return f'{lat:.1f}s'

def fmt_user(uid):
    # 'agentic-user20' → 'user20'
    if uid and uid.startswith('agentic-'):
        return uid[8:]
    return uid or '-'

# Print header
if multi:
    print(f'\033[1m{\"Cluster\":<8} {\"Timestamp\":<20} {\"User\":<10} {\"Latency\":>8}  {\"Input\":<45} {\"Output\":<45}\033[0m')
    print(f'{\"-\"*8} {\"-\"*20} {\"-\"*10} {\"-\"*8}  {\"-\"*45} {\"-\"*45}')
else:
    print(f'\033[1m{\"Timestamp\":<20} {\"User\":<10} {\"Latency\":>8}  {\"Input\":<45} {\"Output\":<45}\033[0m')
    print(f'{\"-\"*20} {\"-\"*10} {\"-\"*8}  {\"-\"*45} {\"-\"*45}')

for t in traces:
    ts = fmt_ts(t['timestamp'])
    user = fmt_user(t['userId'])
    latency = fmt_latency(t['latency'])
    inp = trunc(t['input'], 45)
    out = trunc(t['output'], 45)

    if multi:
        print(f'\033[0;36m{t[\"cluster\"]:<8}\033[0m {ts:<20} \033[1;33m{user:<10}\033[0m {latency:>8}  {inp:<45} \033[2m{out:<45}\033[0m')
    else:
        print(f'{ts:<20} \033[1;33m{user:<10}\033[0m {latency:>8}  {inp:<45} \033[2m{out:<45}\033[0m')

print()
print(f'\033[1mTotal: {len(traces)} trace(s)\033[0m')
" <<< "$ALL_JSON"
fi

# ── Report saved files ────────────────────────────────────────────────
if [[ ${#SAVED_FILES[@]} -gt 0 ]]; then
  info ""
  info "${BOLD}Saved files:${RESET}"
  for f in "${SAVED_FILES[@]}"; do
    SIZE=$(wc -c < "$f" | xargs)
    info "  ${CYAN}${f}${RESET} ${DIM}(${SIZE} bytes)${RESET}"
  done
fi
