#!/usr/bin/env bash
# deploy-rhoai-observability.sh — stand up RHOAI "Observe & monitor" end to end.
#
# Reconstructed from a four-hour debugging session on rosa-wv5l4 2026-11-18.
# Every step here exists because skipping it produced a green-looking cluster
# with a broken dashboard. Read HANDOFF.md for the full narrative.
#
# The seven things that each cost real time:
#
#  1. `monitoring.managementState: Managed` with `metrics: {}` reports
#     MonitoringReady=True and provisions NOTHING. redhat-ods-monitoring exists
#     with zero pods. The honest condition is MonitoringStackAvailable, which
#     reads False/MetricsNotConfigured. Never trust MonitoringReady.
#  2. Setting metrics without the prerequisite operators puts the DSCI into
#     Ready=False/MissingOperator, and *that* makes other things disappear from
#     the dashboard (we lost the models-as-a-service project this way).
#  3. The RHOAI operator caches API discovery. After installing the operators
#     it must be restarted or it never sees the new CRDs.
#  4. RHOAI's `perses-operator-access` NetworkPolicy allows port 8080 only from
#     namespace `openshift-cluster-observability-operator`. If COO was installed
#     cluster-wide the operator is in `openshift-operators` instead, that
#     namespace does not exist, and the policy can never match.
#  5. Perses CRs that failed before Perses existed are NEVER retried. They sit
#     at PersesBackendError forever. They must be poked — and that means the
#     DATASOURCES too, not just the dashboards. Miss the datasources and every
#     panel renders "No datasource found for 'data-science-prometheus-datasource'".
#  6. The rhods-dashboard pod registers its /perses proxy at boot. A pod older
#     than the Perses instance serves index.html for /perses/*, and the browser
#     reports: Unexpected token '<', "<!doctype "... is not valid JSON.
#  7. MaaS usage metrics need Kuadrant observability enabled AND the monitors
#     labelled monitoring.opendatahub.io/scrape=true — the OTel collector's
#     target allocator selects on that label across all namespaces.
#
# Usage:
#   ./deploy-rhoai-observability.sh            # full sequence
#   ./deploy-rhoai-observability.sh --check    # report, change nothing
#   ./deploy-rhoai-observability.sh --verify   # prove metrics actually flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MON_NS=redhat-ods-monitoring
APP_NS=redhat-ods-applications
MODE=deploy

case "${1:-}" in
  --check)  MODE=check ;;
  --verify) MODE=verify ;;
  "")       ;;
  *)        echo "Unknown flag: $1" >&2; exit 1 ;;
esac

for c in oc python3; do command -v "$c" >/dev/null || { echo "Missing $c" >&2; exit 1; }; done
oc whoami >/dev/null

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; RST=$'\033[0m'
ok()   { echo "  ${GREEN}✓${RST} $*"; }
bad()  { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YEL}!${RST} $*"; }

dsci_cond() {
  oc get dscinitialization -o jsonpath="{.items[0].status.conditions[?(@.type=='$1')].status}" 2>/dev/null
}

report() {
  echo "── RHOAI observability ─────────────────────────────"
  for c in MonitoringStackAvailable OpenTelemetryCollectorAvailable TempoAvailable PersesAvailable; do
    [[ "$(dsci_cond "$c")" == "True" ]] && ok "$c=True" || bad "$c=$(dsci_cond "$c")"
  done
  local pods
  pods=$(oc get pods -n "$MON_NS" --no-headers 2>/dev/null | grep -c Running || true)
  ok "$MON_NS Running pods: $pods"
  local d ds
  d=$(oc exec -n "$MON_NS" data-science-perses-0 -- sh -c \
      'curl -s http://localhost:8080/api/v1/dashboards' 2>/dev/null \
      | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  ds=$(oc exec -n "$MON_NS" data-science-perses-0 -- sh -c \
      'curl -s http://localhost:8080/api/v1/datasources' 2>/dev/null \
      | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  [[ "${d:-0}" -gt 0 ]] && ok "Perses dashboards loaded: $d" || bad "Perses dashboards loaded: 0"
  [[ "${ds:-0}" -gt 0 ]] && ok "Perses datasources loaded: $ds" || bad "Perses datasources loaded: 0"
  local k
  k=$(oc get kuadrant kuadrant -n kuadrant-system -o jsonpath='{.spec.observability.enable}' 2>/dev/null)
  [[ "$k" == "true" ]] && ok "Kuadrant observability enabled" || bad "Kuadrant observability: ${k:-unset}"
}

verify_metrics() {
  # Prometheus here speaks HTTPS. Querying it over http returns
  # "Client sent an HTTP request to an HTTPS server", which is not JSON and is
  # very easy to misread as "no data". Always use https and check `up` first.
  echo "── metric verification ─────────────────────────────"
  oc port-forward -n "$MON_NS" svc/data-science-monitoringstack-prometheus 19099:9090 >/dev/null 2>&1 &
  local pf=$!
  trap 'kill '"$pf"' 2>/dev/null || true' RETURN
  sleep 8
  local n
  n=$(curl -sk --max-time 25 "https://localhost:19099/api/v1/query?query=up" \
      | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0)
  if [[ "${n:-0}" -gt 0 ]]; then ok "positive control: 'up' returned $n series"
  else bad "positive control FAILED — query path broken, ignore results below"; return 1; fi
  for m in authorized_calls_total authorized_hits_total; do
    n=$(curl -sk --max-time 25 "https://localhost:19099/api/v1/query?query=$m" \
        | python3 -I -c 'import json,sys;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0)
    [[ "${n:-0}" -gt 0 ]] && ok "$m: $n series" \
      || warn "$m: no series (expected until some MaaS traffic has flowed)"
  done
}

case "$MODE" in
  check)  report; exit 0 ;;
  verify) verify_metrics; exit $? ;;
esac

echo "── 1. prerequisite operators ───────────────────────"
# Docs (RHOAI 3.5, Managing OpenShift AI ch.12) require all three. A stock
# ROSA/RHDP cluster usually ships only the Cluster Observability Operator.
#
# WHERE COO LIVES MATTERS — this is not cosmetic. Installed cluster-wide into
# `openshift-operators` it breaks two things at once, and both failures lie
# about their cause (measured on sv68v, 2026-11-19):
#
#  1. RHOAI's monitoring precondition never clears. The DSCI reports
#     Ready=False MissingOperator / "ClusterObservability operator must be
#     installed for metrics configuration" even with the CSV Succeeded, every
#     CRD registered, and observability-operator, perses-operator and
#     obo-prometheus-operator all Running. Restarting rhods-operator does NOT
#     clear it — the check is not discovery-based. Reinstalling into the
#     dedicated namespace cleared it in one reconcile.
#  2. The `perses-operator-access` NetworkPolicy admits port 8080 only from
#     namespace `openshift-cluster-observability-operator`. Install COO there
#     and it matches by construction — no patch, and nothing to re-apply after
#     an operator upgrade.
#
# So: if COO is absent, install it into its own namespace. If it is already
# installed somewhere else we cannot safely move it, so fall back to patching
# the NetworkPolicy (step 4 handles that and resolves the namespace itself).
COO_NS=openshift-cluster-observability-operator
COO_WHERE=$(oc get csv -A --no-headers 2>/dev/null \
            | grep -i 'cluster-observability-operator' | awk '{print $1}' | head -1)
if [[ -z "$COO_WHERE" ]]; then
  echo "  installing Cluster Observability Operator into $COO_NS"
  cat <<YAML | oc apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: $COO_NS
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: $COO_NS
  namespace: $COO_NS
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: $COO_NS
spec:
  channel: stable
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
YAML
elif [[ "$COO_WHERE" == "$COO_NS" ]]; then
  ok "COO already in $COO_NS (NetworkPolicy will match by construction)"
else
  warn "COO is in '$COO_WHERE', not $COO_NS."
  warn "RHOAI's precondition may not clear and the Perses NetworkPolicy will"
  warn "not match; step 4 patches around it. A fresh install should put COO in"
  warn "$COO_NS instead."
fi

need_op() { ! oc get csv -A --no-headers 2>/dev/null | grep -qi "$1"; }
# COO is NOT in this list — it is handled above, because it must go into its
# own namespace. A self-managed OCP sandbox (sv68v) ships none of the three,
# so do not assume a stock cluster "already has COO"; an unmet prerequisite is
# worse than a missing feature, because the resulting
# Ready=False/MissingOperator also makes unrelated pages vanish.
# otel and tempo are namespace-agnostic and go to openshift-operators.
for pkg in opentelemetry-product tempo-product; do
  short=${pkg%-product}
  if need_op "$short"; then
    cat <<YAML | oc apply -f - >/dev/null
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: $pkg
  namespace: openshift-operators
spec:
  channel: stable
  name: $pkg
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
YAML
    echo "  installing $pkg…"
  else
    ok "$pkg already installed"
  fi
done
for _ in $(seq 1 40); do
  O=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -i opentelemetry | awk '{print $NF}' | head -1)
  T=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -i tempo | awk '{print $NF}' | head -1)
  # COO may legitimately live in either namespace, so search cluster-wide.
  C=$(oc get csv -A --no-headers 2>/dev/null | grep -i cluster-observability | awk '{print $NF}' | head -1)
  # NOT `[[ ... ]] && break`: under `set -e` an AND-list whose test
  # fails returns 1 and kills the script, so the very first poll --
  # before any operator could possibly be Succeeded -- aborted the run.
  # On sv68v this exited 1 straight after "installing tempo-product".
  if [[ "$O" == "Succeeded" && "$T" == "Succeeded" && "$C" == "Succeeded" ]]; then break; fi
  sleep 15
done
ok "opentelemetry=${O:-?} tempo=${T:-?} cluster-observability=${C:-?}"

echo "── 2. DSCI monitoring ──────────────────────────────"
DSCI=$(oc get dscinitialization -o jsonpath='{.items[0].metadata.name}')
oc patch dscinitialization "$DSCI" --type=merge -p "$(python3 -I -c "
import json
print(json.dumps({'spec':{'monitoring':{
 'managementState':'Managed','namespace':'$MON_NS','alerting':{},
 'metrics':{'replicas':1,'storage':{'size':'20Gi','retention':'7d'}},
 'traces':{'sampleRatio':'0.1','storage':{'backend':'pv','retention':'168h'}}}}}))")" >/dev/null
ok "DSCI monitoring configured"

echo "── 3. restart rhods-operator (API discovery cache) ─"
# WAIT FOR THE OPERATOR PODS, NOT THE CSV PHASE. A CSV reports Succeeded
# before observability-operator and perses-operator are actually Running, so a
# restart triggered on the CSV re-caches discovery while the CRDs' controllers
# are still coming up — and the restart is then wasted. Measured on sv68v:
# this is why TWO restarts were needed. Waiting for the pods makes one enough.
echo "  waiting for the observability operator pods…"
for _ in $(seq 1 40); do
  RUNNING=$(oc get pods -A --no-headers 2>/dev/null \
            | grep -E 'observability-operator|perses-operator' \
            | grep -c 'Running' || true)
  if [[ "${RUNNING:-0}" -ge 2 ]]; then break; fi
  sleep 15
done
ok "observability operator pods Running: ${RUNNING:-0}"

oc rollout restart deploy/rhods-operator -n redhat-ods-operator >/dev/null 2>&1 || true
oc rollout status deploy/rhods-operator -n redhat-ods-operator --timeout=300s >/dev/null 2>&1 || true
for _ in $(seq 1 40); do
  # Same `set -e` trap as above.
  if [[ "$(dsci_cond MonitoringStackAvailable)" == "True" ]]; then break; fi
  sleep 15
done
# Second restart only if the first did not take. The precondition check is not
# discovery-based, so if COO is in the wrong namespace no number of restarts
# will clear it — see step 1.
if [[ "$(dsci_cond MonitoringStackAvailable)" != "True" ]]; then
  warn "not Available yet — restarting rhods-operator once more"
  oc rollout restart deploy/rhods-operator -n redhat-ods-operator >/dev/null 2>&1 || true
  oc rollout status deploy/rhods-operator -n redhat-ods-operator --timeout=300s >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    if [[ "$(dsci_cond MonitoringStackAvailable)" == "True" ]]; then break; fi
    sleep 15
  done
fi
[[ "$(dsci_cond MonitoringStackAvailable)" == "True" ]] \
  && ok "MonitoringStackAvailable=True" || bad "MonitoringStack did not come up"

echo "── 4. Perses NetworkPolicy (COO namespace mismatch) ─"
PERSES_OP_NS=$(oc get pods -A -l app.kubernetes.io/name=perses-operator \
  --no-headers 2>/dev/null | awk '{print $1}' | head -1)
if [[ -n "$PERSES_OP_NS" ]]; then
  ok "perses-operator runs in: $PERSES_OP_NS"
  python3 -I - "$PERSES_OP_NS" "$MON_NS" <<'PY' | oc apply -f - >/dev/null
import json, sys
ns, mon = sys.argv[1], sys.argv[2]
print(json.dumps({
 "apiVersion":"networking.k8s.io/v1","kind":"NetworkPolicy",
 "metadata":{"name":"perses-operator-access-"+ns,"namespace":mon},
 "spec":{"podSelector":{"matchLabels":{"app.kubernetes.io/managed-by":"perses-operator"}},
   "policyTypes":["Ingress"],
   "ingress":[{"from":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":ns}},
     "podSelector":{"matchLabels":{"app.kubernetes.io/name":"perses-operator"}}}],
     "ports":[{"protocol":"TCP","port":8080}]}]}}))
PY
  ok "NetworkPolicy allowing $PERSES_OP_NS -> Perses:8080 applied"
else
  warn "perses-operator pod not found; skipping NetworkPolicy"
fi

echo "── 5. re-trigger stale Perses CRs (dashboards AND datasources) ─"
TS=$(date +%s)
for kind in persesdashboard persesdatasource; do
  for r in $(oc get "$kind" -n "$MON_NS" -o name 2>/dev/null); do
    oc annotate -n "$MON_NS" "$r" "reconcile.opendatahub.io/trigger=$TS" --overwrite >/dev/null 2>&1 || true
  done
done
ok "annotated all PersesDashboard and PersesDatasource resources"

echo "── 6. restart rhods-dashboard (registers /perses proxy) ─"
oc rollout restart deploy/rhods-dashboard -n "$APP_NS" >/dev/null 2>&1 || true
oc rollout status deploy/rhods-dashboard -n "$APP_NS" --timeout=300s >/dev/null 2>&1 || true
ok "dashboard restarted"

echo "── 7. MaaS usage metrics ───────────────────────────"
oc patch kuadrant kuadrant -n kuadrant-system --type merge \
  -p '{"spec":{"observability":{"enable":true}}}' >/dev/null 2>&1 \
  && ok "Kuadrant observability enabled" || warn "could not patch Kuadrant"
# captureUser only becomes meaningful once seats have their own identities —
# see create-seat-users.sh. Until then every key is owned by whoever minted it.
oc patch maastenantconfig default-tenant -n models-as-a-service --type merge \
  -p '{"spec":{"telemetry":{"enabled":true,"metrics":{"captureOrganization":true,"captureUser":true,"captureGroup":false,"captureModelUsage":true}}}}' \
  >/dev/null 2>&1 && ok "MaaS telemetry enabled" || warn "could not patch MaasTenantConfig"
# The OTel collector's target allocator selects monitors by THIS label across
# all namespaces. Kuadrant/Istio do not set it themselves.
label_mon() {
  oc label "$1" "$2" -n "$3" monitoring.opendatahub.io/scrape=true --overwrite >/dev/null 2>&1 \
    && echo "      labelled $3/$2"
}
label_mon podmonitor      kuadrant-limitador-monitor  kuadrant-system
label_mon podmonitor      istio-pod-monitor           openshift-ingress
label_mon servicemonitor  kuadrant-authorino-monitor  kuadrant-system
ok "scrape labels applied"

echo
report
echo
echo "Run './deploy-rhoai-observability.sh --verify' after some MaaS traffic."
