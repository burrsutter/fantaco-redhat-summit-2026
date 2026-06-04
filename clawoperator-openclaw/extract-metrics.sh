#!/usr/bin/env bash
# extract-metrics.sh — Extract Grafana dashboard metrics from both primary clusters
#
# Queries Thanos Querier on each cluster via the Prometheus HTTP API,
# aggregates cross-cluster totals, and outputs metrics-snapshot.md.
#
# Usage:
#   ./extract-metrics.sh                  # query both primary clusters
#   ./extract-metrics.sh --site backup    # query backup cluster(s)
#
# Prerequisites:
#   - oc login active on at least one cluster
#   - kubeconfigs at ~/.kube/config-cluster-{id}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/metrics-snapshot.md"
ENV_FILE="${SCRIPT_DIR}/../.env"

# ── Source .env and select provider-aware pricing ─────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

LLM_PROVIDER="${LLM_PROVIDER:-openrouter}"

case "$LLM_PROVIDER" in
  gcp)
    INPUT_COST_PER_TOKEN="${GEMINI_INPUT_COST_PER_TOKEN:-0.00000125}"
    OUTPUT_COST_PER_TOKEN="${GEMINI_OUTPUT_COST_PER_TOKEN:-0.000010}"
    PROVIDER_NAME="Gemini 2.5 Pro"
    ;;
  openrouter|litellm)
    INPUT_COST_PER_TOKEN="${KIMI_INPUT_COST_PER_TOKEN:-0.00000073}"
    OUTPUT_COST_PER_TOKEN="${KIMI_OUTPUT_COST_PER_TOKEN:-0.00000349}"
    PROVIDER_NAME="Kimi K2.6"
    ;;
  anthropic)
    INPUT_COST_PER_TOKEN="${ANTHROPIC_INPUT_COST_PER_TOKEN:-0.000003}"
    OUTPUT_COST_PER_TOKEN="${ANTHROPIC_OUTPUT_COST_PER_TOKEN:-0.000015}"
    PROVIDER_NAME="Claude Sonnet 3.5"
    ;;
  *)
    INPUT_COST_PER_TOKEN="${KIMI_INPUT_COST_PER_TOKEN:-0.00000073}"
    OUTPUT_COST_PER_TOKEN="${KIMI_OUTPUT_COST_PER_TOKEN:-0.00000349}"
    PROVIDER_NAME="Kimi K2.6 (default)"
    ;;
esac

# ── Site / cluster config ─────────────────────────────────────────
SITE="primary"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ "$SITE" == "primary" ]]; then
  CLUSTER_IDS=("ql7rg" "w6hwm")
elif [[ "$SITE" == "backup" ]]; then
  CLUSTER_IDS=("pcpwx")
else
  echo "Error: unknown site '$SITE' (use primary or backup)"
  exit 1
fi

echo "============================================"
echo "  Extract Grafana Dashboard Metrics"
echo "============================================"
echo ""
echo "Site:     $SITE"
echo "Clusters: ${CLUSTER_IDS[*]}"
echo "Provider: $PROVIDER_NAME"
echo "Pricing:  input=\$${INPUT_COST_PER_TOKEN}/token, output=\$${OUTPUT_COST_PER_TOKEN}/token"
echo ""

# ── Temp directory for raw results ────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Helper: query Prometheus on a cluster ─────────────────────────
query_prom() {
  local cluster_id="$1"
  local query="$2"
  local kubeconfig="$HOME/.kube/config-cluster-${cluster_id}"

  if [[ ! -f "$kubeconfig" ]]; then
    echo "WARN: kubeconfig not found: $kubeconfig" >&2
    echo '{"status":"error","error":"kubeconfig not found"}'
    return
  fi

  # Get Thanos Querier route
  local thanos_host
  thanos_host=$(KUBECONFIG="$kubeconfig" oc get route thanos-querier \
    -n openshift-monitoring \
    -o jsonpath='{.spec.host}' 2>/dev/null) || true

  if [[ -z "$thanos_host" ]]; then
    echo "WARN: Cannot get Thanos route on cluster $cluster_id" >&2
    echo '{"status":"error","error":"no thanos route"}'
    return
  fi

  # Get auth token
  local token
  token=$(KUBECONFIG="$kubeconfig" oc whoami -t 2>/dev/null) || true

  if [[ -z "$token" ]]; then
    echo "WARN: Cannot get token for cluster $cluster_id" >&2
    echo '{"status":"error","error":"no token"}'
    return
  fi

  # Query Prometheus API
  curl -sk --max-time 30 \
    -H "Authorization: Bearer $token" \
    "https://${thanos_host}/api/v1/query" \
    --data-urlencode "query=${query}" 2>/dev/null
}

# ── Define all queries (parallel arrays for bash 3 compat) ────────
# Note: Cost is calculated from token metrics using .env pricing, not queried from gateway
QUERY_KEYS=(
  model_calls
  agent_runs
  tool_executions
  input_tokens
  output_tokens
  cache_read_tokens
  model_latency_p50
  model_latency_p95
  calls_by_outcome
  run_duration_p50
  run_duration_p95
  tools_by_name
  tool_latency_p95
  user_model_calls
  user_input_tokens
  user_output_tokens
  user_tool_calls
)

QUERY_EXPRS=(
  'sum(openclaw_model_call_total)'
  'sum(openclaw_run_completed_total)'
  'sum(openclaw_tool_execution_total)'
  'sum(openclaw_model_tokens_total{token_type="input"})'
  'sum(openclaw_model_tokens_total{token_type="output"})'
  'sum(openclaw_model_tokens_total{token_type="cache_read"})'
  'histogram_quantile(0.50, sum by (le) (rate(openclaw_model_call_duration_seconds_bucket[1h])))'
  'histogram_quantile(0.95, sum by (le) (rate(openclaw_model_call_duration_seconds_bucket[1h])))'
  'sum by (outcome) (openclaw_model_call_total)'
  'histogram_quantile(0.50, sum by (le) (rate(openclaw_run_duration_seconds_bucket{trigger="user"}[1h])))'
  'histogram_quantile(0.95, sum by (le) (rate(openclaw_run_duration_seconds_bucket{trigger="user"}[1h])))'
  'sum by (tool) (openclaw_tool_execution_total)'
  'histogram_quantile(0.95, sum by (le, tool) (rate(openclaw_tool_execution_duration_seconds_bucket[1h])))'
  'sum by (namespace) (openclaw_model_call_total)'
  'sum by (namespace) (openclaw_model_tokens_total{token_type="input"})'
  'sum by (namespace) (openclaw_model_tokens_total{token_type="output"})'
  'sum by (namespace) (openclaw_tool_execution_total)'
)

TOTAL_QUERIES=${#QUERY_KEYS[@]}

# ── Run queries across all clusters ───────────────────────────────
for cluster_id in "${CLUSTER_IDS[@]}"; do
  echo "--- Querying cluster: $cluster_id ---"
  CLUSTER_DIR="${TMPDIR}/${cluster_id}"
  mkdir -p "$CLUSTER_DIR"

  for i in $(seq 0 $((TOTAL_QUERIES - 1))); do
    key="${QUERY_KEYS[$i]}"
    expr="${QUERY_EXPRS[$i]}"
    echo "  [$((i+1))/$TOTAL_QUERIES] $key"
    result=$(query_prom "$cluster_id" "$expr")
    echo "$result" > "${CLUSTER_DIR}/${key}.json"
  done
  echo ""
done

# ── Aggregate with Python ─────────────────────────────────────────
echo "--- Aggregating results ---"

python3 - "$TMPDIR" "$OUTPUT_FILE" "$SITE" "$PROVIDER_NAME" "$INPUT_COST_PER_TOKEN" "$OUTPUT_COST_PER_TOKEN" "${CLUSTER_IDS[@]}" <<'PYEOF'
import json
import os
import sys
from datetime import datetime, timezone

tmpdir = sys.argv[1]
output_file = sys.argv[2]
site = sys.argv[3]
provider_name = sys.argv[4]
input_cost_per_token = float(sys.argv[5])
output_cost_per_token = float(sys.argv[6])
cluster_ids = sys.argv[7:]

def load_result(cluster_id, key):
    """Load a query result JSON file."""
    path = os.path.join(tmpdir, cluster_id, f"{key}.json")
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get("status") == "success":
            return data.get("data", {}).get("result", [])
        return []
    except (json.JSONDecodeError, FileNotFoundError):
        return []

def scalar_value(results):
    """Extract scalar value from a single-result query."""
    if not results:
        return 0.0
    # Handle both vector and scalar result types
    for r in results:
        val = r.get("value", [None, "0"])[1]
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0
    return 0.0

def aggregate_scalar(key):
    """Sum scalar values across clusters."""
    total = 0.0
    for cid in cluster_ids:
        total += scalar_value(load_result(cid, key))
    return total

def aggregate_by_label(key, label):
    """Merge by-label results across clusters."""
    merged = {}
    for cid in cluster_ids:
        results = load_result(cid, key)
        for r in results:
            lbl = r.get("metric", {}).get(label, "unknown")
            val = float(r.get("value", [None, "0"])[1])
            if lbl in merged:
                merged[lbl] += val
            else:
                merged[lbl] = val
    return merged

def best_latency(key):
    """For histogram_quantile, take the max across clusters (they're rates, not sums)."""
    vals = []
    for cid in cluster_ids:
        v = scalar_value(load_result(cid, key))
        if v > 0 and v != float('inf') and v == v:  # skip 0, inf, NaN
            vals.append(v)
    return max(vals) if vals else 0.0

def avg_latency(key):
    """For histogram_quantile, average across clusters."""
    vals = []
    for cid in cluster_ids:
        v = scalar_value(load_result(cid, key))
        if v > 0 and v != float('inf') and v == v:
            vals.append(v)
    return sum(vals) / len(vals) if vals else 0.0

def latency_by_tool(key):
    """Get per-tool latency p95 (take max across clusters)."""
    merged = {}
    for cid in cluster_ids:
        results = load_result(cid, key)
        for r in results:
            tool = r.get("metric", {}).get("tool", "unknown")
            val = float(r.get("value", [None, "0"])[1])
            if val != float('inf') and val == val and val > 0:
                if tool not in merged or val > merged[tool]:
                    merged[tool] = val
    return merged

def fmt_num(n):
    """Format number with commas."""
    if n == 0:
        return "0"
    # If it's a whole number (even if float), format without decimals
    if isinstance(n, float) and n == int(n):
        n = int(n)
    if isinstance(n, int):
        return f"{n:,}"
    if n < 1:
        return f"{n:.4f}"
    return f"{n:,.2f}"

def fmt_duration(seconds):
    """Format seconds as human readable."""
    if seconds <= 0:
        return "N/A"
    if seconds < 1:
        return f"{seconds*1000:.0f}ms"
    if seconds < 60:
        return f"{seconds:.1f}s"
    return f"{seconds/60:.1f}m"

def fmt_cost(usd):
    """Format as USD."""
    if usd <= 0:
        return "$0.00"
    return f"${usd:.4f}"

# ── Gather data ───────────────────────────────────────────────────
now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

model_calls = aggregate_scalar("model_calls")
agent_runs = aggregate_scalar("agent_runs")
tool_execs = aggregate_scalar("tool_executions")
input_tokens = aggregate_scalar("input_tokens")
output_tokens = aggregate_scalar("output_tokens")
cache_tokens = aggregate_scalar("cache_read_tokens")

# Calculate cost from tokens using provider-specific pricing
total_cost = (input_tokens * input_cost_per_token) + (output_tokens * output_cost_per_token)

latency_p50 = avg_latency("model_latency_p50")
latency_p95 = avg_latency("model_latency_p95")
calls_by_outcome = aggregate_by_label("calls_by_outcome", "outcome")

run_p50 = avg_latency("run_duration_p50")
run_p95 = avg_latency("run_duration_p95")

tools_by_name = aggregate_by_label("tools_by_name", "tool")
tool_lat_p95 = latency_by_tool("tool_latency_p95")

# Per-user data
user_calls = aggregate_by_label("user_model_calls", "namespace")
user_in_tok = aggregate_by_label("user_input_tokens", "namespace")
user_out_tok = aggregate_by_label("user_output_tokens", "namespace")
user_tools = aggregate_by_label("user_tool_calls", "namespace")

# Calculate per-user cost from tokens
user_cost = {}
for user in set(list(user_in_tok.keys()) + list(user_out_tok.keys())):
    in_tokens = user_in_tok.get(user, 0)
    out_tokens = user_out_tok.get(user, 0)
    user_cost[user] = (in_tokens * input_cost_per_token) + (out_tokens * output_cost_per_token)

# ── Build Markdown ────────────────────────────────────────────────
lines = []
lines.append(f"# OpenClaw Metrics Snapshot")
lines.append(f"")
lines.append(f"**Generated:** {now}")
lines.append(f"**Site:** {site}")
lines.append(f"**Clusters:** {', '.join(cluster_ids)}")
lines.append(f"**Provider:** {provider_name}")
lines.append(f"**Pricing:** input=${input_cost_per_token:.8f}/token, output=${output_cost_per_token:.8f}/token")
lines.append(f"")

# Overview stats
lines.append(f"## Overview")
lines.append(f"")
lines.append(f"| Metric | Value |")
lines.append(f"|--------|------:|")
lines.append(f"| Model Calls | {fmt_num(model_calls)} |")
lines.append(f"| Agent Runs | {fmt_num(agent_runs)} |")
lines.append(f"| Tool Executions | {fmt_num(tool_execs)} |")
lines.append(f"| Input Tokens | {fmt_num(input_tokens)} |")
lines.append(f"| Output Tokens | {fmt_num(output_tokens)} |")
lines.append(f"| Cache Read Tokens | {fmt_num(cache_tokens)} |")
lines.append(f"| Total Cost (USD) | {fmt_cost(total_cost)} |")
lines.append(f"")

# Model performance
lines.append(f"## Model Performance")
lines.append(f"")
lines.append(f"| Metric | Value |")
lines.append(f"|--------|------:|")
lines.append(f"| Latency p50 | {fmt_duration(latency_p50)} |")
lines.append(f"| Latency p95 | {fmt_duration(latency_p95)} |")
lines.append(f"")

if calls_by_outcome:
    lines.append(f"### Calls by Outcome")
    lines.append(f"")
    lines.append(f"| Outcome | Count |")
    lines.append(f"|---------|------:|")
    for outcome in sorted(calls_by_outcome, key=lambda k: calls_by_outcome[k], reverse=True):
        lines.append(f"| {outcome} | {fmt_num(calls_by_outcome[outcome])} |")
    lines.append(f"")

# Agent run duration
lines.append(f"## Agent Run Duration (user-triggered)")
lines.append(f"")
lines.append(f"| Metric | Value |")
lines.append(f"|--------|------:|")
lines.append(f"| Duration p50 | {fmt_duration(run_p50)} |")
lines.append(f"| Duration p95 | {fmt_duration(run_p95)} |")
lines.append(f"")

# Tool usage
if tools_by_name:
    lines.append(f"## Tool Usage")
    lines.append(f"")
    lines.append(f"| Tool | Calls | Latency p95 |")
    lines.append(f"|------|------:|------------:|")
    for tool in sorted(tools_by_name, key=lambda k: tools_by_name[k], reverse=True):
        count = fmt_num(tools_by_name[tool])
        lat = fmt_duration(tool_lat_p95.get(tool, 0))
        lines.append(f"| {tool} | {count} | {lat} |")
    lines.append(f"")

# Per-user table
all_users = sorted(set(list(user_calls.keys()) + list(user_cost.keys())))
if all_users:
    # Sort by cost descending
    user_rows = []
    for u in all_users:
        user_rows.append({
            "namespace": u,
            "calls": user_calls.get(u, 0),
            "input_tokens": user_in_tok.get(u, 0),
            "output_tokens": user_out_tok.get(u, 0),
            "cost": user_cost.get(u, 0),
            "tools": user_tools.get(u, 0),
        })
    user_rows.sort(key=lambda r: r["cost"], reverse=True)

    lines.append(f"## Per-User Breakdown (top 20 by cost)")
    lines.append(f"")
    lines.append(f"| User | Model Calls | Input Tokens | Output Tokens | Cost (USD) | Tool Calls |")
    lines.append(f"|------|------------:|-------------:|--------------:|-----------:|-----------:|")
    for row in user_rows[:20]:
        ns = row["namespace"].replace("agentic-", "")
        lines.append(
            f"| {ns} | {fmt_num(row['calls'])} | {fmt_num(row['input_tokens'])} "
            f"| {fmt_num(row['output_tokens'])} | {fmt_cost(row['cost'])} "
            f"| {fmt_num(row['tools'])} |"
        )
    if len(user_rows) > 20:
        lines.append(f"| ... | ({len(user_rows) - 20} more users) | | | | |")
    lines.append(f"")

# Per-cluster breakdown
lines.append(f"## Per-Cluster Totals")
lines.append(f"")
lines.append(f"| Cluster | Model Calls | Tokens (in+out) | Cost (USD) |")
lines.append(f"|---------|------------:|----------------:|-----------:|")
for cid in cluster_ids:
    c_calls = scalar_value(load_result(cid, "model_calls"))
    c_in = scalar_value(load_result(cid, "input_tokens"))
    c_out = scalar_value(load_result(cid, "output_tokens"))
    # Calculate cost from tokens using provider-specific pricing
    c_cost = (c_in * input_cost_per_token) + (c_out * output_cost_per_token)
    lines.append(f"| {cid} | {fmt_num(c_calls)} | {fmt_num(c_in + c_out)} | {fmt_cost(c_cost)} |")
lines.append(f"")

# Write file
with open(output_file, "w") as f:
    f.write("\n".join(lines))

print(f"Written to {output_file}")
print(f"  Clusters: {', '.join(cluster_ids)}")
print(f"  Model calls: {fmt_num(model_calls)}")
print(f"  Total cost: {fmt_cost(total_cost)}")
print(f"  Active users: {len(all_users)}")
PYEOF

echo ""
echo "============================================"
echo "  Done! Metrics saved to:"
echo "  ${OUTPUT_FILE}"
echo "============================================"
