#!/usr/bin/env bash
# deploy-traces-mlflow.sh
#
# Deploys MLflow on OpenShift with PostgreSQL backend for trace collection,
# feedback, and evals. Designed for OpenClaw OTLP integration.
#
# Usage: ./deploy-traces-mlflow.sh [namespace]
#
# Defaults:
#   namespace = mlflow
#
# Idempotent — safe to re-run on fresh clusters.
# Self-contained — downloads the Helm chart from GitHub (no git clone needed).
#
# Prerequisites:
#   - oc logged in to the target cluster
#   - helm v3 installed
#   - curl installed

set -euo pipefail

NAMESPACE="${1:-mlflow}"

# ─── Pinned versions ─────────────────────────────────────────────────────────
MLFLOW_VERSION="3.12.0"                          # app version
MLFLOW_IMAGE_TAG="v${MLFLOW_VERSION}-full"       # ghcr.io/mlflow/mlflow image
MLFLOW_CHART_SHA="336e57fc3f17183911b28deb51a18eb1a5316346"  # chart version 0.1.0, appVersion 3.12.0
PG_VERSION="15-el9"                              # OpenShift imagestream tag
# ──────────────────────────────────────────────────────────────────────────────

PG_USER="mlflow"
PG_PASSWORD="mlflow123"
PG_DATABASE="mlflow"
PG_VOLUME="5Gi"
EXPERIMENT_NAME="openclaw-traces"

# ─── 1. Pre-flight ─────────────────────────────────────────────────────────────

echo "=== Pre-flight checks ==="

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi
echo "Logged in as: $(oc whoami)"

if ! command -v helm &>/dev/null; then
  echo "Error: helm not found — install Helm v3 first" >&2
  exit 1
fi
echo "Helm: $(helm version --short)"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
echo "Cluster domain: ${CLUSTER_DOMAIN:-unknown}"

# ─── 2. Download Helm chart ──────────────────────────────────────────────────

echo ""
echo "=== Helm chart (mlflow @ ${MLFLOW_CHART_SHA:0:12}) ==="

CHART_TMPDIR=$(mktemp -d /tmp/mlflow-chart-XXXXXX)
trap 'rm -rf "$CHART_TMPDIR"' EXIT

TARBALL_URL="https://github.com/mlflow/mlflow/archive/${MLFLOW_CHART_SHA}.tar.gz"
echo "Downloading chart from GitHub..."
curl -sL "$TARBALL_URL" | tar xz -C "$CHART_TMPDIR" --strip-components=1 "mlflow-${MLFLOW_CHART_SHA}/charts"
MLFLOW_CHART_DIR="${CHART_TMPDIR}/charts"

if [[ ! -f "${MLFLOW_CHART_DIR}/Chart.yaml" ]]; then
  echo "Error: Chart.yaml not found after extracting — check MLFLOW_VERSION" >&2
  exit 1
fi
echo "Chart extracted to ${MLFLOW_CHART_DIR}"
echo "  chart version: $(grep '^version:' "${MLFLOW_CHART_DIR}/Chart.yaml" | awk '{print $2}')"
echo "  appVersion:    $(grep '^appVersion:' "${MLFLOW_CHART_DIR}/Chart.yaml" | awk '{print $2}')"

# ─── 3. Namespace ──────────────────────────────────────────────────────────────

echo ""
echo "=== Namespace (${NAMESPACE}) ==="

if oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace $NAMESPACE already exists"
else
  oc new-project "$NAMESPACE" --display-name="MLflow" || oc create namespace "$NAMESPACE"
  echo "Namespace $NAMESPACE created"
fi

# Ensure we're working in the right project
oc project "$NAMESPACE" &>/dev/null

# ─── 4. PostgreSQL ─────────────────────────────────────────────────────────────

echo ""
echo "=== PostgreSQL (${PG_VERSION}) ==="

if oc get dc/postgresql -n "$NAMESPACE" &>/dev/null; then
  echo "PostgreSQL DeploymentConfig already exists — skipping"
else
  oc new-app postgresql-persistent \
    --param POSTGRESQL_USER="$PG_USER" \
    --param POSTGRESQL_PASSWORD="$PG_PASSWORD" \
    --param POSTGRESQL_DATABASE="$PG_DATABASE" \
    --param VOLUME_CAPACITY="$PG_VOLUME" \
    --param POSTGRESQL_VERSION="$PG_VERSION" \
    -n "$NAMESPACE"
  echo "PostgreSQL deployed"
fi

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL pod..."
oc rollout status dc/postgresql -n "$NAMESPACE" --timeout=120s

# ─── 5. Database Secret ───────────────────────────────────────────────────────

echo ""
echo "=== Secret (mlflow-db-secret) ==="

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: mlflow-db-secret
  labels:
    app: mlflow
type: Opaque
stringData:
  uri: "postgresql+psycopg2://${PG_USER}:${PG_PASSWORD}@postgresql:5432/${PG_DATABASE}"
EOF
echo "Secret applied"

# ─── 6. Helm install/upgrade ──────────────────────────────────────────────────

echo ""
echo "=== MLflow (Helm) ==="

# Write values to a temp file (cleaned up by the same trap as CHART_TMPDIR)
VALUES_FILE="${CHART_TMPDIR}/openshift-values.yaml"

cat > "$VALUES_FILE" <<EOF
image:
  repository: ghcr.io/mlflow/mlflow
  tag: "${MLFLOW_IMAGE_TAG}"

replicaCount: 1

server:
  value_options:
    host: "0.0.0.0"
    port: 5000
    workers: 2
    allowed_hosts: "*"

mlflow:
  backendStoreUriFrom:
    secretKeyRef:
      name: mlflow-db-secret
      key: uri
  defaultArtifactRoot: "/mlflow/artifacts"

storage:
  enabled: true
  size: 5Gi
  accessMode: ReadWriteOnce
  storageClassName: ""

podSecurityContext:
  runAsNonRoot: true
  runAsUser: null
  fsGroup: null
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL

service:
  type: ClusterIP

ingress:
  enabled: false

resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
EOF

if helm status mlflow -n "$NAMESPACE" &>/dev/null; then
  echo "Upgrading existing MLflow release..."
  helm upgrade mlflow "$MLFLOW_CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE"
else
  echo "Installing MLflow..."
  helm install mlflow "$MLFLOW_CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$VALUES_FILE"
fi
echo "Helm release applied"

# ─── 7. Wait for MLflow pod ───────────────────────────────────────────────────

echo ""
echo "=== Waiting for MLflow rollout ==="
oc rollout status deployment/mlflow-mlflow -n "$NAMESPACE" --timeout=180s

# ─── 8. Route ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Route (mlflow) ==="

if oc get route mlflow -n "$NAMESPACE" &>/dev/null; then
  echo "Route already exists"
else
  oc create route edge mlflow \
    --service=mlflow-mlflow \
    --port=5000 \
    -n "$NAMESPACE"
  echo "Route created"
fi

ROUTE_HOST=$(oc get route mlflow -n "$NAMESPACE" -o jsonpath='{.spec.host}')
MLFLOW_URL="https://${ROUTE_HOST}"
echo "Route host: ${ROUTE_HOST}"

# ─── 9. Health check ──────────────────────────────────────────────────────────

echo ""
echo "=== Health check ==="

# Give the route a moment to propagate
sleep 3

HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "${MLFLOW_URL}/health" || echo "000")
echo "GET /health => ${HTTP_STATUS}"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Warning: health check returned ${HTTP_STATUS} — pod may still be starting"
  echo "Check logs: oc logs deployment/mlflow-mlflow -n ${NAMESPACE} --tail=30"
fi

# ─── 10. Create experiment ─────────────────────────────────────────────────────

echo ""
echo "=== Experiment (${EXPERIMENT_NAME}) ==="

EXPERIMENT_RESPONSE=$(curl -sk -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/create" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${EXPERIMENT_NAME}\"}" 2>/dev/null || echo '{"error":"request failed"}')

if echo "$EXPERIMENT_RESPONSE" | grep -q "experiment_id"; then
  EXPERIMENT_ID=$(echo "$EXPERIMENT_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment_id'])" 2>/dev/null || echo "unknown")
  echo "Created experiment '${EXPERIMENT_NAME}' with ID: ${EXPERIMENT_ID}"
elif echo "$EXPERIMENT_RESPONSE" | grep -q "RESOURCE_ALREADY_EXISTS"; then
  # Experiment exists — look up its ID
  EXPERIMENT_ID=$(curl -sk "${MLFLOW_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=${EXPERIMENT_NAME}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment']['experiment_id'])" 2>/dev/null || echo "unknown")
  echo "Experiment '${EXPERIMENT_NAME}' already exists with ID: ${EXPERIMENT_ID}"
else
  EXPERIMENT_ID="0"
  echo "Warning: could not create experiment — using Default (ID=0)"
  echo "Response: ${EXPERIMENT_RESPONSE}"
fi

# ─── 11. Summary ──────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo "  MLflow deployed to ${NAMESPACE}"
echo "============================================="
echo ""
echo "  Versions:"
echo "    MLflow:     ${MLFLOW_IMAGE_TAG}"
echo "    Chart:      ${MLFLOW_CHART_SHA:0:12}"
echo "    PostgreSQL: ${PG_VERSION}"
echo ""
echo "  UI:     ${MLFLOW_URL}"
echo "  Health: ${MLFLOW_URL}/health"
echo "  OTLP:   ${MLFLOW_URL}/v1/traces"
echo ""
echo "  Experiment: ${EXPERIMENT_NAME} (ID: ${EXPERIMENT_ID})"
echo ""
echo "  ── OpenClaw OTEL config ──"
echo "  Set these env vars on the OpenClaw instance:"
echo ""
echo "    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=${MLFLOW_URL}/v1/traces"
echo "    OTEL_EXPORTER_OTLP_TRACES_HEADERS=x-mlflow-experiment-id=${EXPERIMENT_ID}"
echo ""
echo "  ── Python client ──"
echo "    import mlflow"
echo "    mlflow.set_tracking_uri(\"${MLFLOW_URL}\")"
echo ""
echo "  ── Verify ──"
echo "    oc get pods -n ${NAMESPACE}"
echo "    curl -sk ${MLFLOW_URL}/health"
echo "============================================="
