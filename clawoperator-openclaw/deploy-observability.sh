#!/usr/bin/env bash
# deploy-observability.sh — deploy the observability stack, in parallel.
#
# DEFAULT: Loki + Grafana + MLflow.  Langfuse is OPT-IN.
#
# Why Langfuse is not the default: it brings 11 pods — web, worker, postgres,
# 3x clickhouse, redis, s3/minio, 3x zookeeper — and the 3-node ClickHouse on a
# 3-node ZooKeeper quorum is the slowest, flappiest part of the stack. Its
# langfuse-tracer plugin injection is also what crashlooped 9 gateways on
# 2026-11-05 via a half-finished `oc cp`. MLflow carries the prompt-preview
# demo, so for a time-boxed build the second trace UI is not worth the risk.
#
# Skipping it is safe: both audience-reset.sh and post-restart-repatch.sh gate
# langfuse-tracer on .state/<guid>/langfuse.env AND the langfuse route existing,
# so seats simply come up with 9 plugins instead of 10.
#
# Usage:
#   ./deploy-observability.sh                  # Loki + Grafana + MLflow
#   ./deploy-observability.sh --with-langfuse  # ... plus Langfuse
#   ./deploy-observability.sh --skip-loki      # e.g. when ODF is not ready yet
#
# Loki needs NooBaa Ready first when LOKI_OBJECT_STORE=odf. Everything else is
# independent, so the jobs run concurrently and are reported per-job at the end
# rather than aborting the batch on the first failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WITH_LANGFUSE=false
SKIP_LOKI=false
for arg in "$@"; do
  case "$arg" in
    --with-langfuse) WITH_LANGFUSE=true ;;
    --skip-loki)     SKIP_LOKI=true ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

oc whoami >/dev/null 2>&1 || { echo "Not logged in to OpenShift." >&2; exit 1; }

CLUSTER_GUID=$(oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
LOGS="$SCRIPT_DIR/.state/${CLUSTER_GUID}/observability-logs"
mkdir -p "$LOGS"

BASH5="${BASH5:-/opt/homebrew/bin/bash}"
[ -x "$BASH5" ] || BASH5=bash

echo "=== observability deploy — cluster $CLUSTER_GUID ==="
echo "    Loki: $([ "$SKIP_LOKI" = true ] && echo skipped || echo yes) | Grafana: yes | MLflow: yes | Langfuse: $WITH_LANGFUSE"
echo "    logs: $LOGS"

pids=(); names=()
start() { "$BASH5" "./$1" > "$LOGS/${2}.log" 2>&1 & pids+=($!); names+=("$2"); }

[ "$SKIP_LOKI" = true ] || start deploy-logs-loki.sh         loki
start deploy-dashboards-grafana.sh                            grafana
start deploy-traces-mlflow.sh                                 mlflow
[ "$WITH_LANGFUSE" = true ] && start deploy-traces-langfuse.sh langfuse

fail=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then
    echo "  OK   ${names[$i]}"
  else
    echo "  FAIL ${names[$i]}  -> $LOGS/${names[$i]}.log"
    fail=1
  fi
done

# ── RHOAI dashboard: MaaS metrics ────────────────────────────────────────
# Observe & monitor → Usage renders but shows zeros, because the MaaS operator
# publishes its PodMonitors in the monitoring.coreos.com API group while the
# dashboard's MonitoringStack Prometheus watches monitoring.rhobs. Mirror them.
# Additive — the operator's originals are untouched.
if oc get crd podmonitors.monitoring.rhobs >/dev/null 2>&1; then
  if oc apply -f "${SCRIPT_DIR:-.}/operator-patches/maas-podmonitors-rhobs.yaml" >"$LOGS/maas-podmonitors.log" 2>&1; then
    echo "  OK   maas-podmonitors-rhobs"
  else
    echo "  WARN maas-podmonitors-rhobs -> $LOGS/maas-podmonitors.log (MaaS Usage page will read zero)"
  fi
else
  echo "  SKIP maas-podmonitors-rhobs (monitoring.rhobs CRD absent — RHOAI monitoring not installed)"
fi

echo "=== done (fail=$fail) ==="
[ "$WITH_LANGFUSE" = false ] && cat <<'NOTE'

Langfuse was not deployed. Seats will load 9 plugins instead of 10 and
langfuse-tracer injection will skip itself cleanly. To add it later:
  ./deploy-traces-langfuse.sh && ./post-restart-repatch.sh --site ocp 1 <N>
NOTE
exit $fail
