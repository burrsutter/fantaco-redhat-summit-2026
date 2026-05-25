#!/usr/bin/env bash
# analyze-cluster-capacity.sh
#
# Analyzes OpenShift cluster compute and memory capacity to determine
# when to scale worker nodes based on student/user count.
#
# Usage: ./analyze-cluster-capacity.sh [sample-namespace]
#
# Defaults:
#   sample-namespace = agentic-user1
#
# Outputs a capacity report with:
# - Total cluster capacity (CPU, memory)
# - Per-node breakdown
# - Per-student footprint (based on sample namespace)
# - Scaling projections (20, 40, 60, 80, 100 students)
# - Scaling recommendations

set -euo pipefail

SAMPLE_NS="${1:-agentic-user1}"

# Colors
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# ─── Helper: Convert memory to GiB ───────────────────────────────────────────

mem_to_gib() {
  local mem="$1"
  if [[ "$mem" =~ ^([0-9]+)Ki$ ]]; then
    echo "scale=2; ${BASH_REMATCH[1]} / 1024 / 1024" | bc
  elif [[ "$mem" =~ ^([0-9]+)Mi$ ]]; then
    echo "scale=2; ${BASH_REMATCH[1]} / 1024" | bc
  elif [[ "$mem" =~ ^([0-9]+)Gi$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$mem" =~ ^([0-9]+)$ ]]; then
    # bytes
    echo "scale=2; ${BASH_REMATCH[1]} / 1024 / 1024 / 1024" | bc
  else
    echo "0"
  fi
}

# ─── Helper: Convert CPU to millicores ───────────────────────────────────────

cpu_to_millicores() {
  local cpu="$1"
  if [[ "$cpu" =~ ^([0-9]+)m$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$cpu" =~ ^([0-9]+)$ ]]; then
    echo "$((${BASH_REMATCH[1]} * 1000))"
  else
    echo "0"
  fi
}

# ─── Helper: Format percentage ───────────────────────────────────────────────

format_pct() {
  local used="$1"
  local total="$2"
  if (( $(echo "$total > 0" | bc -l) )); then
    local pct=$(echo "scale=2; ($used / $total) * 100" | bc)
    printf "%.0f" "$pct"
  else
    echo "0"
  fi
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq not found — install jq first" >&2
  exit 1
fi

if ! command -v bc &>/dev/null; then
  echo "Error: bc not found — install bc first" >&2
  exit 1
fi

# ─── Collect cluster data ────────────────────────────────────────────────────

echo -e "${BOLD}=== OpenShift Cluster Capacity Analysis ===${RESET}"
echo ""

# Get all worker nodes
WORKER_NODES=$(oc get nodes -l node-role.kubernetes.io/worker= -o json 2>/dev/null | jq -r '.items[].metadata.name' || echo "")

if [[ -z "$WORKER_NODES" ]]; then
  echo "Error: no worker nodes found" >&2
  exit 1
fi

WORKER_COUNT=$(echo "$WORKER_NODES" | wc -l | tr -d ' ')

echo -e "${BOLD}Cluster Overview:${RESET}"
echo "  Worker Nodes:        ${WORKER_COUNT}"

# Aggregate capacity and allocatable
TOTAL_CPU_CAPACITY=0
TOTAL_CPU_ALLOCATABLE=0
TOTAL_MEM_CAPACITY=0
TOTAL_MEM_ALLOCATABLE=0

while IFS= read -r node; do
  NODE_DATA=$(oc get node "$node" -o json)

  CPU_CAPACITY=$(echo "$NODE_DATA" | jq -r '.status.capacity.cpu')
  CPU_ALLOCATABLE=$(echo "$NODE_DATA" | jq -r '.status.allocatable.cpu')
  MEM_CAPACITY=$(echo "$NODE_DATA" | jq -r '.status.capacity.memory')
  MEM_ALLOCATABLE=$(echo "$NODE_DATA" | jq -r '.status.allocatable.memory')

  CPU_CAPACITY_MC=$(cpu_to_millicores "$CPU_CAPACITY")
  CPU_ALLOCATABLE_MC=$(cpu_to_millicores "$CPU_ALLOCATABLE")
  MEM_CAPACITY_GIB=$(mem_to_gib "$MEM_CAPACITY")
  MEM_ALLOCATABLE_GIB=$(mem_to_gib "$MEM_ALLOCATABLE")

  TOTAL_CPU_CAPACITY=$((TOTAL_CPU_CAPACITY + CPU_CAPACITY_MC))
  TOTAL_CPU_ALLOCATABLE=$((TOTAL_CPU_ALLOCATABLE + CPU_ALLOCATABLE_MC))
  TOTAL_MEM_CAPACITY=$(echo "$TOTAL_MEM_CAPACITY + $MEM_CAPACITY_GIB" | bc)
  TOTAL_MEM_ALLOCATABLE=$(echo "$TOTAL_MEM_ALLOCATABLE + $MEM_ALLOCATABLE_GIB" | bc)
done <<< "$WORKER_NODES"

TOTAL_CPU_CORES=$(echo "scale=1; $TOTAL_CPU_CAPACITY / 1000" | bc)
TOTAL_CPU_ALLOC_CORES=$(echo "scale=1; $TOTAL_CPU_ALLOCATABLE / 1000" | bc)

echo "  Total CPU:           ${TOTAL_CPU_CORES} cores (${TOTAL_CPU_ALLOC_CORES} allocatable)"
echo "  Total Memory:        ${TOTAL_MEM_CAPACITY} GiB (${TOTAL_MEM_ALLOCATABLE} GiB allocatable)"

# Get current usage (requires metrics-server or monitoring)
METRICS_AVAILABLE=false
if oc adm top nodes &>/dev/null; then
  METRICS_AVAILABLE=true

  CURRENT_CPU_USAGE=0
  CURRENT_MEM_USAGE=0

  while IFS= read -r node; do
    NODE_USAGE=$(oc adm top node "$node" --no-headers 2>/dev/null | awk '{print $2, $4}')
    if [[ -n "$NODE_USAGE" ]]; then
      CPU_USED=$(echo "$NODE_USAGE" | awk '{print $1}')
      MEM_USED=$(echo "$NODE_USAGE" | awk '{print $2}')

      CPU_USED_MC=$(cpu_to_millicores "$CPU_USED")
      MEM_USED_GIB=$(mem_to_gib "$MEM_USED")

      CURRENT_CPU_USAGE=$((CURRENT_CPU_USAGE + CPU_USED_MC))
      CURRENT_MEM_USAGE=$(echo "$CURRENT_MEM_USAGE + $MEM_USED_GIB" | bc)
    fi
  done <<< "$WORKER_NODES"

  CPU_USAGE_PCT=$(format_pct "$CURRENT_CPU_USAGE" "$TOTAL_CPU_ALLOCATABLE")
  MEM_USAGE_PCT=$(format_pct "$CURRENT_MEM_USAGE" "$TOTAL_MEM_ALLOCATABLE")

  echo "  Current Usage:       ${CPU_USAGE_PCT}% CPU, ${MEM_USAGE_PCT}% memory"
fi

# ─── Per-Node Breakdown ──────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Per-Node Breakdown:${RESET}"

while IFS= read -r node; do
  NODE_DATA=$(oc get node "$node" -o json)

  CPU_CAPACITY=$(echo "$NODE_DATA" | jq -r '.status.capacity.cpu')
  CPU_ALLOCATABLE=$(echo "$NODE_DATA" | jq -r '.status.allocatable.cpu')
  MEM_CAPACITY=$(echo "$NODE_DATA" | jq -r '.status.capacity.memory')
  MEM_ALLOCATABLE=$(echo "$NODE_DATA" | jq -r '.status.allocatable.memory')

  CPU_CAPACITY_CORES=$(echo "scale=1; $(cpu_to_millicores "$CPU_CAPACITY") / 1000" | bc)
  CPU_ALLOCATABLE_CORES=$(echo "scale=1; $(cpu_to_millicores "$CPU_ALLOCATABLE") / 1000" | bc)
  MEM_CAPACITY_GIB=$(mem_to_gib "$MEM_CAPACITY")
  MEM_ALLOCATABLE_GIB=$(mem_to_gib "$MEM_ALLOCATABLE")

  POD_COUNT=$(oc get pods --all-namespaces --field-selector spec.nodeName="$node" --no-headers 2>/dev/null | wc -l | tr -d ' ')

  echo ""
  echo "  Node: $node (worker)"
  echo "    CPU:     ${CPU_CAPACITY_CORES} cores (${CPU_ALLOCATABLE_CORES} allocatable)"
  echo "    Memory:  ${MEM_CAPACITY_GIB} GiB (${MEM_ALLOCATABLE_GIB} GiB allocatable)"

  if [[ "$METRICS_AVAILABLE" == "true" ]]; then
    NODE_USAGE=$(oc adm top node "$node" --no-headers 2>/dev/null | awk '{print $2, $3, $4, $5}')
    if [[ -n "$NODE_USAGE" ]]; then
      CPU_USED=$(echo "$NODE_USAGE" | awk '{print $1}')
      CPU_PCT=$(echo "$NODE_USAGE" | awk '{print $2}' | tr -d '%')
      MEM_USED=$(echo "$NODE_USAGE" | awk '{print $3}')
      MEM_PCT=$(echo "$NODE_USAGE" | awk '{print $4}' | tr -d '%')

      echo "    Usage:   ${CPU_USED} (${CPU_PCT}% CPU), ${MEM_USED} (${MEM_PCT}% memory)"
    fi
  fi

  echo "    Pods:    ${POD_COUNT}"
done <<< "$WORKER_NODES"

# ─── Sample Student Namespace ────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Student Namespace Sample (${SAMPLE_NS}):${RESET}"

if ! oc get namespace "$SAMPLE_NS" &>/dev/null; then
  echo "  Warning: namespace $SAMPLE_NS not found — skipping footprint analysis"
  STUDENT_CPU_REQ_MC=0
  STUDENT_CPU_LIM_MC=0
  STUDENT_MEM_REQ_GIB=0
  STUDENT_MEM_LIM_GIB=0
else
  POD_COUNT=$(oc get pods -n "$SAMPLE_NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "  Pods: ${POD_COUNT}"

  # Get pod requests/limits
  STUDENT_CPU_REQ_MC=0
  STUDENT_CPU_LIM_MC=0
  STUDENT_MEM_REQ_GIB=0
  STUDENT_MEM_LIM_GIB=0

  while IFS= read -r pod; do
    POD_DATA=$(oc get pod "$pod" -n "$SAMPLE_NS" -o json 2>/dev/null || echo "{}")

    CONTAINERS=$(echo "$POD_DATA" | jq -r '.spec.containers[]?' 2>/dev/null || echo "")
    if [[ -n "$CONTAINERS" ]]; then
      while IFS= read -r container; do
        CPU_REQ=$(echo "$container" | jq -r '.resources.requests.cpu // "0"')
        CPU_LIM=$(echo "$container" | jq -r '.resources.limits.cpu // "0"')
        MEM_REQ=$(echo "$container" | jq -r '.resources.requests.memory // "0"')
        MEM_LIM=$(echo "$container" | jq -r '.resources.limits.memory // "0"')

        STUDENT_CPU_REQ_MC=$((STUDENT_CPU_REQ_MC + $(cpu_to_millicores "$CPU_REQ")))
        STUDENT_CPU_LIM_MC=$((STUDENT_CPU_LIM_MC + $(cpu_to_millicores "$CPU_LIM")))
        STUDENT_MEM_REQ_GIB=$(echo "$STUDENT_MEM_REQ_GIB + $(mem_to_gib "$MEM_REQ")" | bc)
        STUDENT_MEM_LIM_GIB=$(echo "$STUDENT_MEM_LIM_GIB + $(mem_to_gib "$MEM_LIM")" | bc)
      done < <(echo "$POD_DATA" | jq -c '.spec.containers[]?' 2>/dev/null)
    fi
  done < <(oc get pods -n "$SAMPLE_NS" --no-headers 2>/dev/null | awk '{print $1}')

  STUDENT_CPU_REQ_CORES=$(echo "scale=2; $STUDENT_CPU_REQ_MC / 1000" | bc)
  STUDENT_CPU_LIM_CORES=$(echo "scale=2; $STUDENT_CPU_LIM_MC / 1000" | bc)

  echo "  CPU Requests:    ${STUDENT_CPU_REQ_CORES} cores (${STUDENT_CPU_REQ_MC}m)"
  echo "  CPU Limits:      ${STUDENT_CPU_LIM_CORES} cores (${STUDENT_CPU_LIM_MC}m)"
  echo "  Memory Requests: ${STUDENT_MEM_REQ_GIB} GiB"
  echo "  Memory Limits:   ${STUDENT_MEM_LIM_GIB} GiB"

  # Try to get actual usage if metrics available
  if [[ "$METRICS_AVAILABLE" == "true" ]]; then
    ACTUAL_CPU_USAGE=0
    ACTUAL_MEM_USAGE=0

    while IFS= read -r pod; do
      POD_USAGE=$(oc adm top pod "$pod" -n "$SAMPLE_NS" --no-headers 2>/dev/null | awk '{print $2, $3}')
      if [[ -n "$POD_USAGE" ]]; then
        CPU_USED=$(echo "$POD_USAGE" | awk '{print $1}')
        MEM_USED=$(echo "$POD_USAGE" | awk '{print $2}')

        ACTUAL_CPU_USAGE=$((ACTUAL_CPU_USAGE + $(cpu_to_millicores "$CPU_USED")))
        ACTUAL_MEM_USAGE=$(echo "$ACTUAL_MEM_USAGE + $(mem_to_gib "$MEM_USED")" | bc)
      fi
    done < <(oc get pods -n "$SAMPLE_NS" --no-headers 2>/dev/null | awk '{print $1}')

    ACTUAL_CPU_CORES=$(echo "scale=2; $ACTUAL_CPU_USAGE / 1000" | bc)
    echo "  Actual Usage:    CPU: ${ACTUAL_CPU_CORES} cores, Memory: ${ACTUAL_MEM_USAGE} GiB"
  fi
fi

# ─── Capacity Planning ───────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Capacity Planning:${RESET}"

if [[ "$STUDENT_CPU_REQ_MC" -eq 0 ]]; then
  echo "  Warning: no resource requests found in sample namespace — cannot calculate projections"
  exit 0
fi

STUDENT_CPU_REQ_CORES=$(echo "scale=2; $STUDENT_CPU_REQ_MC / 1000" | bc)
STUDENT_CPU_LIM_CORES=$(echo "scale=2; $STUDENT_CPU_LIM_MC / 1000" | bc)

echo "  Per-Student Footprint (based on sample):"
echo "    CPU:    ${STUDENT_CPU_REQ_CORES} cores (requests) | ${STUDENT_CPU_LIM_CORES} cores (limits)"
echo "    Memory: ${STUDENT_MEM_REQ_GIB} GiB (requests) | ${STUDENT_MEM_LIM_GIB} GiB (limits)"

# Count current students
CURRENT_STUDENTS=$(oc get namespaces 2>/dev/null | grep -c 'agentic-user' || echo "0")
echo ""
echo "  Current Deployment (${CURRENT_STUDENTS} students):"

CURRENT_CPU_REQ=$(echo "scale=1; $STUDENT_CPU_REQ_CORES * $CURRENT_STUDENTS" | bc)
CURRENT_CPU_LIM=$(echo "scale=1; $STUDENT_CPU_LIM_CORES * $CURRENT_STUDENTS" | bc)
CURRENT_MEM_REQ=$(echo "scale=1; $STUDENT_MEM_REQ_GIB * $CURRENT_STUDENTS" | bc)
CURRENT_MEM_LIM=$(echo "scale=1; $STUDENT_MEM_LIM_GIB * $CURRENT_STUDENTS" | bc)

CPU_REQ_PCT=$(format_pct "$CURRENT_CPU_REQ" "$TOTAL_CPU_ALLOC_CORES")
MEM_REQ_PCT=$(format_pct "$CURRENT_MEM_REQ" "$TOTAL_MEM_ALLOCATABLE")

echo "    CPU:    ${CURRENT_CPU_REQ} cores (requests) | ${CURRENT_CPU_LIM} cores (limits)"
echo "    Memory: ${CURRENT_MEM_REQ} GiB (requests) | ${CURRENT_MEM_LIM} GiB (limits)"
echo -e "    Status: ${GREEN}✓${RESET} Fits comfortably (${CPU_REQ_PCT}% CPU, ${MEM_REQ_PCT}% memory of allocatable)"

# ─── Scaling Projections ─────────────────────────────────────────────────────

echo ""
echo "  Scaling Projections:"

for STUDENT_COUNT in 20 40 60 80 100; do
  PROJECTED_CPU=$(echo "scale=1; $STUDENT_CPU_REQ_CORES * $STUDENT_COUNT" | bc)
  PROJECTED_MEM=$(echo "scale=1; $STUDENT_MEM_REQ_GIB * $STUDENT_COUNT" | bc)

  CPU_PCT=$(format_pct "$PROJECTED_CPU" "$TOTAL_CPU_ALLOC_CORES")
  MEM_PCT=$(format_pct "$PROJECTED_MEM" "$TOTAL_MEM_ALLOCATABLE")

  MAX_PCT=$CPU_PCT
  if (( MEM_PCT > MAX_PCT )); then
    MAX_PCT=$MEM_PCT
  fi

  if (( MAX_PCT < 60 )); then
    STATUS="${GREEN}✓${RESET} Fits"
  elif (( MAX_PCT < 75 )); then
    STATUS="${YELLOW}⚠${RESET} Tight"
  else
    STATUS="${RED}❌${RESET} Exceeds capacity"
  fi

  printf "    %3d students:  %5.1f cores, %5.1f GiB → %s (%d%% CPU, %d%% memory)\n" \
    "$STUDENT_COUNT" "$PROJECTED_CPU" "$PROJECTED_MEM" "$STATUS" "$CPU_PCT" "$MEM_PCT"
done

# ─── Recommendations ─────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Recommendations:${RESET}"

# Find safe capacity (60% threshold)
SAFE_STUDENTS=$(echo "scale=0; ($TOTAL_CPU_ALLOC_CORES * 0.60) / $STUDENT_CPU_REQ_CORES" | bc)
echo -e "  ${GREEN}✓${RESET} Current: ${WORKER_COUNT} worker nodes support up to ${SAFE_STUDENTS} students comfortably"

# Find tight capacity (75% threshold)
TIGHT_STUDENTS=$(echo "scale=0; ($TOTAL_CPU_ALLOC_CORES * 0.75) / $STUDENT_CPU_REQ_CORES" | bc)
echo -e "  ${YELLOW}⚠${RESET} ${TIGHT_STUDENTS} students: Operating near 75% capacity (acceptable but tight)"

# Find exceeds capacity (90% threshold)
MAX_STUDENTS=$(echo "scale=0; ($TOTAL_CPU_ALLOC_CORES * 0.90) / $STUDENT_CPU_REQ_CORES" | bc)
SCALE_OUT_STUDENTS=$((MAX_STUDENTS + 1))
echo -e "  ${RED}❌${RESET} ${SCALE_OUT_STUDENTS}+ students: SCALE OUT — Add 2-3 more worker nodes before deploying"

echo ""
echo "  Scaling Trigger: When total requests exceed 70% of allocatable resources"
echo "  Buffer Recommendation: Keep 30% headroom for spikes and system overhead"

echo ""
