#!/usr/bin/env bash
# extract-user-traces-by-cluster.sh — Extract traces for a specific user across all clusters
#
# Creates separate JSON files per cluster to preserve instance identity.
# Only uses the most recent trace file per cluster.
# 
# Usage:
#   ./extract-user-traces-by-cluster.sh 1
#   ./extract-user-traces-by-cluster.sh 31

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <user_number>"
  echo "Example: $0 1"
  echo "         $0 31"
  exit 1
fi

USER_NUM=$1
USER_ID="agentic-user${USER_NUM}"
TRACES_DIR="traces"
OUTPUT_DIR="traces/by-user"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%S)

mkdir -p "$OUTPUT_DIR"

echo "============================================"
echo "  Extract User Traces (Multi-Cluster)"
echo "============================================"
echo ""
echo "User: $USER_ID"
echo ""

# Find unique clusters and their most recent trace files
CLUSTERS=()
for trace_file in "${TRACES_DIR}"/*-2026-*.json; do
  [[ -f "$trace_file" ]] || continue
  [[ "$trace_file" == *"/by-user/"* ]] && continue
  [[ "$trace_file" == *"redteam"* ]] && continue
  [[ "$trace_file" == *"user"[0-9]* ]] && [[ "$trace_file" != *"agentic-user"* ]] && continue
  
  # Extract cluster ID from filename
  CLUSTER_ID=$(basename "$trace_file" | sed -E 's/^([a-z0-9]+)-.*/\1/')
  
  # Check if we've seen this cluster
  if ! printf '%s\n' "${CLUSTERS[@]+"${CLUSTERS[@]}"}" | grep -q "^${CLUSTER_ID}$"; then
    CLUSTERS+=("$CLUSTER_ID")
  fi
done

if [[ ${#CLUSTERS[@]} -eq 0 ]]; then
  echo "Error: No cluster trace files found in ${TRACES_DIR}/"
  exit 1
fi

echo "Found ${#CLUSTERS[@]} unique cluster(s)"
echo ""

TOTAL_TRACES=0
ACTIVE_CLUSTERS=()

for CLUSTER_ID in "${CLUSTERS[@]}"; do
  # Find most recent trace file for this cluster
  TRACE_FILE=$(ls -1t "${TRACES_DIR}/${CLUSTER_ID}"-2026-*.json 2>/dev/null | head -1 || true)
  
  if [[ -z "$TRACE_FILE" ]]; then
    echo "  - $CLUSTER_ID: no trace file"
    continue
  fi
  
  echo "Checking cluster: $CLUSTER_ID ($(basename "$TRACE_FILE"))"
  
  # Extract traces for this user using Python
  RESULT=$(python3 << PYEOF
import json
import sys

try:
    with open('$TRACE_FILE') as f:
        all_traces = json.load(f)
    
    user_traces = [t for t in all_traces if t.get('userId') == '$USER_ID']
    user_traces.sort(key=lambda x: x['timestamp'])
    
    if user_traces:
        first_ts = user_traces[0]['timestamp']
        last_ts = user_traces[-1]['timestamp']
        print(f"{len(user_traces)}|{first_ts}|{last_ts}")
        print(json.dumps(user_traces, indent=2))
    else:
        print("0||")
        print("[]")
except Exception as e:
    print("0||", file=sys.stderr)
    print("[]")
    sys.exit(0)
PYEOF
)
  
  TRACE_COUNT=$(echo "$RESULT" | head -1 | cut -d'|' -f1)
  FIRST_TS=$(echo "$RESULT" | head -1 | cut -d'|' -f2)
  LAST_TS=$(echo "$RESULT" | head -1 | cut -d'|' -f3)
  USER_TRACES=$(echo "$RESULT" | tail -n +2)
  
  if [[ "$TRACE_COUNT" -gt 0 ]]; then
    OUTPUT_FILE="${OUTPUT_DIR}/${USER_ID}-${CLUSTER_ID}-${RUN_TS}.json"
    
    cat > "$OUTPUT_FILE" << JSONEOF
{
  "metadata": {
    "extraction_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "userId": "$USER_ID",
    "cluster": "$CLUSTER_ID",
    "trace_count": $TRACE_COUNT,
    "time_span": "$FIRST_TS to $LAST_TS",
    "note": "Instance-specific traces. User $USER_ID on cluster $CLUSTER_ID is separate from same user on other clusters.",
    "source_file": "$(basename "$TRACE_FILE")"
  },
  "traces": $USER_TRACES
}
JSONEOF
    
    SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
    SIZE_KB=$((SIZE / 1024))
    echo "  ✓ $CLUSTER_ID: $TRACE_COUNT traces → ${OUTPUT_FILE##*/} (${SIZE_KB}K)"
    
    TOTAL_TRACES=$((TOTAL_TRACES + TRACE_COUNT))
    ACTIVE_CLUSTERS+=("$CLUSTER_ID")
  else
    echo "  - $CLUSTER_ID: 0 traces (instance exists but no activity)"
  fi
done

echo ""
echo "============================================"
echo "  Summary"
echo "============================================"
echo ""
echo "User: $USER_ID"
echo "Clusters with activity: ${#ACTIVE_CLUSTERS[@]}"
echo "Total traces across all clusters: $TOTAL_TRACES"
echo ""

if [[ ${#ACTIVE_CLUSTERS[@]} -gt 0 ]]; then
  echo "Active clusters (each is a separate OpenClaw instance):"
  for cluster in $(printf '%s\n' "${ACTIVE_CLUSTERS[@]}" | sort -u); do
    echo "  - $cluster"
  done
  echo ""
  echo "Output files:"
  ls -lh "$OUTPUT_DIR/${USER_ID}"-*-"${RUN_TS}.json" 2>/dev/null | awk '{printf "  %-55s %6s\n", $9, $5}'
else
  echo "No traces found for $USER_ID on any cluster"
fi

echo ""
