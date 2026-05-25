---
name: analyze-cluster-capacity
description: Analyze OpenShift cluster compute/memory capacity and recommend when to scale worker nodes based on student count
---

# Cluster Capacity Analysis

This skill analyzes the OpenShift cluster's compute and memory capacity to help determine when to scale worker nodes based on student/user count.

## What This Skill Does

1. **Collects cluster-wide metrics:**
   - Total worker nodes
   - Total CPU/memory capacity and allocatable resources
   - Current cluster utilization (if metrics-server available)

2. **Analyzes per-node capacity:**
   - CPU and memory (capacity vs allocatable)
   - Current usage and pod count per node

3. **Samples a student namespace** (default: `agentic-user1`):
   - Pod count
   - CPU/memory requests and limits
   - Actual usage (if metrics available)
   - Calculates per-student footprint

4. **Projects scaling requirements:**
   - Shows capacity for 20, 40, 60, 80, 100 students
   - Color-coded status (✓ Fits, ⚠ Tight, ❌ Exceeds)
   - Identifies when to add worker nodes

5. **Provides scaling recommendations:**
   - Safe capacity (60% utilization)
   - Tight capacity (75% utilization)
   - Scale-out trigger point (70%+ utilization)

## Usage

Run the underlying script directly or let Claude invoke it for you.

**Direct invocation:**
```bash
cd clawoperator-openclaw
./analyze-cluster-capacity.sh [sample-namespace]
```

**Via this skill:**
```
/fantaco:analyze-cluster-capacity
```

Claude will:
1. Run the capacity analysis script
2. Interpret the results
3. Answer questions about scaling decisions
4. Provide context-specific recommendations

## Example Output

```
=== OpenShift Cluster Capacity Analysis ===

Cluster Overview:
  Worker Nodes:        10
  Total CPU:           160.0 cores (155.0 allocatable)
  Total Memory:        616 GiB (605 GiB allocatable)
  Current Usage:       7% CPU, 18% memory

Per-Node Breakdown:
  [... details per node ...]

Student Namespace Sample (agentic-user1):
  Pods: 12
  CPU Requests:    2.15 cores
  Memory Requests: 2.98 GiB
  Actual Usage:    0.35 cores, 1.8 GiB

Scaling Projections:
   20 students:  43.0 cores,  59.6 GiB → ✓ Fits (28% CPU, 10% memory)
   40 students:  86.0 cores, 119.2 GiB → ✓ Fits (55% CPU, 20% memory)
   60 students: 129.0 cores, 178.8 GiB → ⚠ Tight (83% CPU, 30% memory)
   80 students: 172.0 cores, 238.4 GiB → ❌ Exceeds capacity

Recommendations:
  ✓ Current: 10 worker nodes support up to 43 students comfortably
  ⚠ 54 students: Operating near 75% capacity (acceptable but tight)
  ❌ 65+ students: SCALE OUT — Add 2-3 more worker nodes
```

## When to Use This Skill

- **Pre-demo planning:** "Can this cluster handle 80 students?"
- **Scaling decisions:** "When do I need to add more worker nodes?"
- **Capacity verification:** "How much headroom do we have?"
- **Resource planning:** "What's the per-student resource footprint?"
- **Troubleshooting:** "Are we hitting capacity limits?"

## Instructions for Claude

When this skill is invoked:

1. **Run the analysis script:**
   ```bash
   cd /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw
   ./analyze-cluster-capacity.sh
   ```

2. **Interpret the results:**
   - Identify current cluster capacity (worker nodes, CPU, memory)
   - Show per-student footprint from the sample namespace
   - Highlight scaling projections for different student counts
   - Note any nodes with high utilization

3. **Answer user questions:**
   - "Can we run X students?" → Check scaling projections
   - "When should we scale?" → Show recommendations section
   - "What's the per-student cost?" → Show footprint analysis
   - "Which node is most loaded?" → Compare per-node breakdown

4. **Provide actionable recommendations:**
   - If under 60% utilization: "You have plenty of headroom"
   - If 60-75% utilization: "Operating at recommended capacity"
   - If 75%+ utilization: "Consider scaling out soon"
   - If 90%+ utilization: "Scale out immediately before next demo"

5. **Offer follow-up actions:**
   - Re-run with different sample namespace if needed
   - Suggest when to re-check capacity (e.g., after adding nodes)
   - Recommend reviewing pod resource requests if they seem too high

## Sample Namespace

The script samples `agentic-user1` by default. You can specify a different namespace:

```bash
./analyze-cluster-capacity.sh agentic-user3
```

This is useful if:
- `agentic-user1` doesn't exist yet
- You want to sample a different configuration
- You suspect certain users have different resource patterns

## Prerequisites

- OpenShift CLI (`oc`) logged in
- `jq` installed (JSON parsing)
- `bc` installed (floating-point math)
- Metrics-server or monitoring enabled (optional, for actual usage stats)

## Edge Cases

- **No metrics-server:** Script falls back to requests/limits only
- **Sample namespace not found:** Script warns and skips footprint analysis
- **Zero resource requests:** Cannot calculate projections
- **Heterogeneous nodes:** Assumes uniform node sizing

## Related Files

- **Script:** `clawoperator-openclaw/analyze-cluster-capacity.sh`
- **Documentation:** `clawoperator-openclaw/README.md`
- **Task:** Task #2 in task list

## Future Enhancements

- Historical capacity trending
- Auto-alerting at 70% utilization
- Cost estimation per student
- Integration with audience-reset.sh (pre-flight check)
- Support for heterogeneous node types
