#!/usr/bin/env bash
# deploy-dashboards-grafana.sh
#
# Deploys Grafana on OpenShift using the community Grafana Operator (v5),
# configured with Prometheus and Loki data sources for unified observability.
#
# Usage: ./deploy-dashboards-grafana.sh
#
# Idempotent — safe to re-run. Skips resources that already exist.
#
# Prerequisites:
#   - oc logged in as cluster-admin
#   - User Workload Monitoring enabled (Prometheus)
#   - Loki deployed (via deploy-logs-loki.sh) — optional, skipped if not present

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
NAMESPACE="grafana"
GRAFANA_CHANNEL="v5"
GRAFANA_CATALOG="community-operators"

# ─── 1. Pre-flight ───────────────────────────────────────────────────────────

echo "=== Pre-flight checks ==="

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi
echo "Logged in as: $(oc whoami)"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
echo "Cluster domain: ${CLUSTER_DOMAIN:-unknown}"

# Check for Prometheus
if oc get service thanos-querier -n openshift-monitoring &>/dev/null; then
  echo "Prometheus (Thanos Querier): found"
  HAS_PROMETHEUS=true
else
  echo "Warning: Thanos Querier not found — Prometheus data source will be skipped"
  HAS_PROMETHEUS=false
fi

# Check for Loki
if oc get lokistack logging-loki -n openshift-logging &>/dev/null; then
  echo "LokiStack: found"
  HAS_LOKI=true
else
  echo "Warning: LokiStack not found — Loki data source will be skipped"
  HAS_LOKI=false
fi

# ─── 2. Install Grafana Operator ─────────────────────────────────────────────

echo ""
echo "=== Grafana Operator (${GRAFANA_CHANNEL}) ==="

# Create namespace
if oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace ${NAMESPACE} already exists"
else
  oc create namespace "$NAMESPACE"
  echo "Namespace ${NAMESPACE} created"
fi

# OperatorGroup (single-namespace install)
if ! oc get operatorgroup -n "$NAMESPACE" 2>/dev/null | grep -q .; then
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
    - ${NAMESPACE}
EOF
  echo "OperatorGroup created"
fi

# Subscription
if oc get subscription grafana-operator -n "$NAMESPACE" &>/dev/null; then
  echo "Grafana Operator subscription already exists — skipping"
else
  echo "Creating Grafana Operator subscription..."
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: grafana-operator
  namespace: ${NAMESPACE}
spec:
  channel: "${GRAFANA_CHANNEL}"
  installPlanApproval: Automatic
  name: grafana-operator
  source: ${GRAFANA_CATALOG}
  sourceNamespace: openshift-marketplace
EOF
  echo "Subscription created"
fi

# ─── 3. Wait for Grafana Operator ────────────────────────────────────────────

echo ""
echo "=== Waiting for Grafana Operator CSV ==="

TIMEOUT=300
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CSV_PHASE=$(oc get csv -n "$NAMESPACE" -l operators.coreos.com/grafana-operator.${NAMESPACE}="" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$CSV_PHASE" == "Succeeded" ]]; then
    CSV_NAME=$(oc get csv -n "$NAMESPACE" -l operators.coreos.com/grafana-operator.${NAMESPACE}="" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "Grafana Operator ready: ${CSV_NAME}"
    break
  fi
  echo "  Waiting... (${ELAPSED}s, phase: ${CSV_PHASE:-pending})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Error: Grafana Operator did not reach Succeeded in ${TIMEOUT}s" >&2
  echo "Check: oc get csv -n ${NAMESPACE}" >&2
  exit 1
fi

# ─── 4. Create ServiceAccount + RBAC for data source access ─────────────────

echo ""
echo "=== ServiceAccount (grafana-sa) ==="

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-sa
  namespace: ${NAMESPACE}
EOF

# Grant cluster-monitoring-view so Grafana can query Thanos/Prometheus
if ! oc get clusterrolebinding grafana-cluster-monitoring-view &>/dev/null 2>&1; then
  oc create clusterrolebinding grafana-cluster-monitoring-view \
    --clusterrole=cluster-monitoring-view \
    --serviceaccount=${NAMESPACE}:grafana-sa
  echo "Bound cluster-monitoring-view to grafana-sa"
else
  echo "ClusterRoleBinding grafana-cluster-monitoring-view already exists"
fi

# Grant Loki log access (application + infrastructure tenants)
for ROLE in cluster-logging-application-view cluster-logging-infrastructure-view; do
  if oc get clusterrole "$ROLE" &>/dev/null 2>&1; then
    if ! oc get clusterrolebinding "grafana-${ROLE}" &>/dev/null 2>&1; then
      oc create clusterrolebinding "grafana-${ROLE}" \
        --clusterrole="${ROLE}" \
        --serviceaccount=${NAMESPACE}:grafana-sa
      echo "Bound ${ROLE} to grafana-sa"
    else
      echo "ClusterRoleBinding grafana-${ROLE} already exists"
    fi
  fi
done

echo "ServiceAccount and RBAC applied"

# Get a long-lived token for the SA
SA_TOKEN=$(oc create token grafana-sa -n "$NAMESPACE" --duration=8760h 2>/dev/null || echo "")
if [[ -z "$SA_TOKEN" ]]; then
  echo "Warning: could not create SA token — data sources may not authenticate"
fi

# ─── 5. Create Grafana instance ──────────────────────────────────────────────

echo ""
echo "=== Grafana instance ==="

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: grafana.integreatly.org/v1beta1
kind: Grafana
metadata:
  name: grafana
  namespace: ${NAMESPACE}
  labels:
    dashboards: grafana
spec:
  config:
    log:
      mode: console
    security:
      admin_user: admin
      admin_password: admin
    auth.anonymous:
      enabled: "true"
  route:
    spec:
      tls:
        termination: edge
        insecureEdgeTerminationPolicy: Redirect
EOF
echo "Grafana CR applied"

# Wait for Grafana deployment
echo "Waiting for Grafana rollout..."
TIMEOUT=180
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  READY=$(oc get deployment grafana-deployment -n "$NAMESPACE" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [[ "${READY:-0}" -ge 1 ]]; then
    echo "Grafana pod is ready"
    break
  fi
  echo "  Waiting... (${ELAPSED}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: Grafana deployment not ready in ${TIMEOUT}s"
  echo "Check: oc get pods -n ${NAMESPACE}"
fi

# ─── 6. Prometheus data source ───────────────────────────────────────────────

if [[ "$HAS_PROMETHEUS" == "true" && -n "$SA_TOKEN" ]]; then
  echo ""
  echo "=== Data source: Prometheus ==="

  oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Prometheus
    type: prometheus
    access: proxy
    url: https://thanos-querier.openshift-monitoring.svc.cluster.local:9091
    isDefault: true
    jsonData:
      httpHeaderName1: Authorization
      timeInterval: 5s
      tlsSkipVerify: true
    secureJsonData:
      httpHeaderValue1: "Bearer ${SA_TOKEN}"
EOF
  echo "Prometheus data source created"
fi

# ─── 7. Loki data source ────────────────────────────────────────────────────

if [[ "$HAS_LOKI" == "true" && -n "$SA_TOKEN" ]]; then
  echo ""
  echo "=== Data source: Loki ==="

  oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDatasource
metadata:
  name: loki
  namespace: ${NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  datasource:
    name: Loki
    type: loki
    access: proxy
    url: https://logging-loki-gateway-http.openshift-logging.svc.cluster.local:8080/api/logs/v1/application
    jsonData:
      httpHeaderName1: Authorization
      tlsSkipVerify: true
    secureJsonData:
      httpHeaderValue1: "Bearer ${SA_TOKEN}"
EOF
  echo "Loki data source created"
fi

# ─── 8. OpenClaw Admin Dashboard ────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_JSON="${SCRIPT_DIR}/../dashboards/openclaw-admin-overview.json"

if [[ "$HAS_PROMETHEUS" == "true" ]]; then
  echo ""
  echo "=== Dashboard: OpenClaw Admin Overview ==="

  if [[ ! -f "$DASHBOARD_JSON" ]]; then
    echo "Error: dashboard file not found: ${DASHBOARD_JSON}" >&2
    exit 1
  fi

  # Build GrafanaDashboard CR with the JSON file contents indented for YAML block scalar
  DASHBOARD_CR=$(mktemp)
  cat > "$DASHBOARD_CR" <<ENDCR
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: openclaw-admin-overview
  namespace: ${NAMESPACE}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  json: |
$(sed 's/^/    /' "$DASHBOARD_JSON")
ENDCR

  oc apply -f "$DASHBOARD_CR"
  rm -f "$DASHBOARD_CR"
  echo "Dashboard 'OpenClaw Admin Overview' applied"
fi

# ─── 9. Health check ─────────────────────────────────────────────────────────

echo ""
echo "=== Health check ==="

# Get the route
GRAFANA_HOST=$(oc get route grafana-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -z "$GRAFANA_HOST" ]]; then
  echo "Warning: Grafana route not found — the operator may still be creating it"
else
  GRAFANA_URL="https://${GRAFANA_HOST}"

  sleep 3
  HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "${GRAFANA_URL}/api/health" || echo "000")
  echo "GET /api/health => ${HTTP_STATUS}"

  if [[ "$HTTP_STATUS" != "200" ]]; then
    echo "Warning: health check returned ${HTTP_STATUS} — pod may still be starting"
  fi
fi

# Pod status
GRAFANA_PODS=$(oc get pods -n "$NAMESPACE" -l app=grafana --no-headers 2>/dev/null)
echo "Grafana pods:"
echo "$GRAFANA_PODS"

# ─── 10. Summary ─────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo "  Grafana deployed to ${NAMESPACE}"
echo "============================================="
echo ""
echo "  Operator:  grafana-operator (${GRAFANA_CHANNEL}, ${GRAFANA_CATALOG})"
echo "  Namespace: ${NAMESPACE}"
if [[ -n "$GRAFANA_HOST" ]]; then
echo "  URL:       ${GRAFANA_URL}"
fi
echo "  Login:     admin / admin"
echo ""
echo "  Data sources:"
if [[ "$HAS_PROMETHEUS" == "true" ]]; then
echo "    - Prometheus (Thanos Querier, default)"
fi
if [[ "$HAS_LOKI" == "true" ]]; then
echo "    - Loki (application logs)"
fi
echo ""
if [[ "$HAS_PROMETHEUS" == "true" ]]; then
echo "  Dashboards:"
echo "    - OpenClaw Admin Overview (cost, tokens, latency, tools, per-user table)"
echo ""
fi
echo "  ── Useful queries ──"
echo "  Prometheus:"
echo "    openclaw_model_call_total"
echo "    sum by (model) (increase(openclaw_model_cost_usd_total[1h]))"
echo ""
echo "  Loki:"
echo "    {kubernetes_namespace_name=\"agentic-user1\"}"
echo "    {kubernetes_namespace_name=~\"agentic-user.*\"} |= \"error\""
echo ""
echo "  ── Verify ──"
echo "    oc get pods -n ${NAMESPACE}"
echo "    oc get grafana -n ${NAMESPACE}"
echo "    oc get grafanadatasource -n ${NAMESPACE}"
echo "    oc get grafanadashboard -n ${NAMESPACE}"
echo "============================================="
