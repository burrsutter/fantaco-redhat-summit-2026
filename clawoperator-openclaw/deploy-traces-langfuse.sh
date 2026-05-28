#!/usr/bin/env bash
# deploy-traces-langfuse.sh
#
# Deploys Langfuse on OpenShift for LLM trace collection, evaluation, and
# feedback. Designed for multi-user OpenClaw integration.
#
# Usage: ./deploy-traces-langfuse.sh [namespace]
#
# Defaults:
#   namespace = langfuse
#
# Idempotent — safe to re-run on fresh clusters.
# Consolidates: create-secrets.sh, create-langfuse-url.sh, helm install
#
# Prerequisites:
#   - oc logged in to the target cluster
#   - helm v3 installed
#
# Produces 11 pods:
#   web, worker, postgres, 3x clickhouse, redis, s3/minio, 3x zookeeper

set -euo pipefail

NAMESPACE="${1:-langfuse}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
if [[ -z "$CLUSTER_GUID" ]]; then
  echo "Error: could not extract cluster GUID from 'oc cluster-info'" >&2
  exit 1
fi
STATE_DIR="${SCRIPT_DIR}/.state/${CLUSTER_GUID}"
STATE_FILE="${STATE_DIR}/langfuse.env"
VALUES_FILE="${SCRIPT_DIR}/langfuse-values.yaml"

HELM_REPO_NAME="langfuse"
HELM_REPO_URL="https://langfuse.github.io/langfuse-k8s"
HELM_RELEASE="langfuse"

# Auto-provisioned admin account
INIT_USER_EMAIL="admin@openclaw.local"
INIT_USER_NAME="Admin"
INIT_ORG_NAME="openclaw"
INIT_PROJECT_NAME="openclaw-traces"

# ─── 1. Pre-flight ──────────────────────────────────────────────────────────

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

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: values file not found at $VALUES_FILE" >&2
  exit 1
fi
echo "Values: $VALUES_FILE"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
if [[ -z "$CLUSTER_DOMAIN" ]]; then
  echo "Error: could not determine cluster domain" >&2
  exit 1
fi
echo "Cluster domain: ${CLUSTER_DOMAIN}"

# ─── 2. Namespace ────────────────────────────────────────────────────────────

echo ""
echo "=== Namespace (${NAMESPACE}) ==="

if oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "Namespace $NAMESPACE already exists"
else
  oc new-project "$NAMESPACE" --display-name="Langfuse" || oc create namespace "$NAMESPACE"
  echo "Namespace $NAMESPACE created"
fi

oc project "$NAMESPACE" &>/dev/null

# ─── 3. Secrets ──────────────────────────────────────────────────────────────

echo ""
echo "=== Secrets ==="

mkdir -p "$STATE_DIR"

# Load existing state if available (idempotent re-run)
if [[ -f "$STATE_FILE" ]]; then
  echo "Loading existing secrets from $STATE_FILE"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
else
  echo "Generating new secrets..."
  LF_SALT="$(openssl rand -hex 16)"
  LF_NEXTAUTH_SECRET="$(openssl rand -hex 32)"
  PG_PASS="$(openssl rand -hex 16)"
  CH_PASS="$(openssl rand -hex 16)"
  REDIS_PASS="$(openssl rand -hex 16)"
  S3_ROOT_PASS="$(openssl rand -hex 16)"
  INIT_USER_PASSWORD="$(openssl rand -hex 12)"
  INIT_PUBLIC_KEY="pk-lf-$(openssl rand -hex 16)"
  INIT_SECRET_KEY="sk-lf-$(openssl rand -hex 24)"

  cat > "$STATE_FILE" <<EOF
# Langfuse secrets — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT commit this file
LF_SALT="${LF_SALT}"
LF_NEXTAUTH_SECRET="${LF_NEXTAUTH_SECRET}"
PG_PASS="${PG_PASS}"
CH_PASS="${CH_PASS}"
REDIS_PASS="${REDIS_PASS}"
S3_ROOT_PASS="${S3_ROOT_PASS}"
INIT_USER_PASSWORD="${INIT_USER_PASSWORD}"
INIT_PUBLIC_KEY="${INIT_PUBLIC_KEY}"
INIT_SECRET_KEY="${INIT_SECRET_KEY}"
EOF
  chmod 600 "$STATE_FILE"
  echo "Secrets saved to $STATE_FILE"
fi

# Create Kubernetes secrets (idempotent via apply)
echo "Applying Kubernetes secrets..."

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-general
type: Opaque
stringData:
  salt: "${LF_SALT}"
EOF

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-nextauth-secret
type: Opaque
stringData:
  nextauth-secret: "${LF_NEXTAUTH_SECRET}"
EOF

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-postgresql-auth
type: Opaque
stringData:
  password: "${PG_PASS}"
  postgres-password: "${PG_PASS}"
EOF

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-clickhouse-auth
type: Opaque
stringData:
  password: "${CH_PASS}"
EOF

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-redis-auth
type: Opaque
stringData:
  password: "${REDIS_PASS}"
EOF

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-s3-auth
type: Opaque
stringData:
  rootUser: "root"
  rootPassword: "${S3_ROOT_PASS}"
EOF

echo "Secrets applied"

# ─── 4. Helm repo ────────────────────────────────────────────────────────────

echo ""
echo "=== Helm repo ==="

if helm repo list 2>/dev/null | grep -q "^${HELM_REPO_NAME}"; then
  echo "Helm repo '${HELM_REPO_NAME}' already added — updating..."
  helm repo update "$HELM_REPO_NAME"
else
  echo "Adding Helm repo '${HELM_REPO_NAME}'..."
  helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
  helm repo update "$HELM_REPO_NAME"
fi

# ─── 5. Patch values with NextAuth URL ───────────────────────────────────────

echo ""
echo "=== Preparing values ==="

ROUTE_HOSTNAME="langfuse-${NAMESPACE}.${CLUSTER_DOMAIN}"
LANGFUSE_URL="https://${ROUTE_HOSTNAME}"

# Create a temp values file with the real NextAuth URL
TMPDIR=$(mktemp -d /tmp/langfuse-deploy-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PATCHED_VALUES="${TMPDIR}/values.yaml"
sed "s|PLACEHOLDER_URL|${LANGFUSE_URL}|" "$VALUES_FILE" > "$PATCHED_VALUES"
echo "NextAuth URL set to: ${LANGFUSE_URL}"

# ─── 6. Helm install/upgrade ─────────────────────────────────────────────────

echo ""
echo "=== Langfuse (Helm) ==="

if helm status "$HELM_RELEASE" -n "$NAMESPACE" &>/dev/null; then
  echo "Upgrading existing Langfuse release..."
  helm upgrade "$HELM_RELEASE" "${HELM_REPO_NAME}/langfuse" \
    --namespace "$NAMESPACE" \
    -f "$PATCHED_VALUES"
else
  echo "Installing Langfuse..."
  helm install "$HELM_RELEASE" "${HELM_REPO_NAME}/langfuse" \
    --namespace "$NAMESPACE" \
    -f "$PATCHED_VALUES"
fi
echo "Helm release applied"

# ─── 7. Wait for pods ────────────────────────────────────────────────────────

echo ""
echo "=== Waiting for pods ==="

# Wait for key deployments/statefulsets
echo "Waiting for PostgreSQL..."
oc rollout status statefulset/langfuse-postgresql -n "$NAMESPACE" --timeout=180s

echo "Waiting for ClickHouse..."
oc rollout status statefulset/langfuse-clickhouse-shard0 -n "$NAMESPACE" --timeout=300s

echo "Waiting for Redis..."
oc rollout status statefulset/langfuse-redis-primary -n "$NAMESPACE" --timeout=120s

echo "Verifying PostgreSQL is accepting connections..."
for i in {1..30}; do
  if oc exec -n "$NAMESPACE" statefulset/langfuse-postgresql -- pg_isready -U langfuse &>/dev/null; then
    echo "PostgreSQL is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "Warning: PostgreSQL connection check timed out"
  fi
  sleep 2
done

echo "Waiting for langfuse-web..."
oc rollout status deployment/langfuse-web -n "$NAMESPACE" --timeout=300s

echo "Waiting for langfuse-worker..."
oc rollout status deployment/langfuse-worker -n "$NAMESPACE" --timeout=300s

echo ""
echo "Pod status:"
oc get pods -n "$NAMESPACE" --no-headers | while read -r line; do
  echo "  $line"
done

# ─── 8. Routes ────────────────────────────────────────────────────────────────

echo ""
echo "=== Routes ==="

S3_ROUTE_HOSTNAME="langfuse-s3-${NAMESPACE}.${CLUSTER_DOMAIN}"
S3_EXTERNAL_URL="https://${S3_ROUTE_HOSTNAME}"

# Langfuse web UI route
echo "Creating Langfuse Route (${ROUTE_HOSTNAME})..."
oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: langfuse
spec:
  host: ${ROUTE_HOSTNAME}
  port:
    targetPort: 3000
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  to:
    kind: Service
    name: langfuse-web
    weight: 100
EOF

# S3/MinIO route (for presigned URL downloads)
echo "Creating S3 Route (${S3_ROUTE_HOSTNAME})..."
oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: langfuse-s3
spec:
  host: ${S3_ROUTE_HOSTNAME}
  port:
    targetPort: minio-api
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  to:
    kind: Service
    name: langfuse-s3
    weight: 100
EOF

echo "Routes created"

# ─── 9. Patch S3 external endpoints ──────────────────────────────────────────

echo ""
echo "=== S3 external endpoint config ==="

echo "Patching langfuse-web with external S3 endpoint + experimental features..."
oc set env deployment/langfuse-web -n "$NAMESPACE" \
  LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT="$S3_EXTERNAL_URL" \
  LANGFUSE_S3_BATCH_EXPORT_ENDPOINT="$S3_EXTERNAL_URL" \
  LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT="$S3_EXTERNAL_URL" \
  ENABLE_EXPERIMENTAL_FEATURES=true

echo "Patching langfuse-worker with external S3 endpoint + experimental features..."
oc set env deployment/langfuse-worker -n "$NAMESPACE" \
  LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT="$S3_EXTERNAL_URL" \
  LANGFUSE_S3_BATCH_EXPORT_ENDPOINT="$S3_EXTERNAL_URL" \
  LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT="$S3_EXTERNAL_URL" \
  ENABLE_EXPERIMENTAL_FEATURES=true

echo "S3 endpoints configured"

# ─── 10. Auto-provision org/project/keys ──────────────────────────────────────

echo ""
echo "=== Auto-provisioning (LANGFUSE_INIT_*) ==="

echo "Patching langfuse-web with auto-provision env vars..."
oc set env deployment/langfuse-web -n "$NAMESPACE" \
  LANGFUSE_INIT_ORG_ID="openclaw" \
  LANGFUSE_INIT_ORG_NAME="${INIT_ORG_NAME}" \
  LANGFUSE_INIT_PROJECT_ID="openclaw-traces" \
  LANGFUSE_INIT_PROJECT_NAME="${INIT_PROJECT_NAME}" \
  LANGFUSE_INIT_PROJECT_PUBLIC_KEY="${INIT_PUBLIC_KEY}" \
  LANGFUSE_INIT_PROJECT_SECRET_KEY="${INIT_SECRET_KEY}" \
  LANGFUSE_INIT_USER_EMAIL="${INIT_USER_EMAIL}" \
  LANGFUSE_INIT_USER_NAME="${INIT_USER_NAME}" \
  LANGFUSE_INIT_USER_PASSWORD="${INIT_USER_PASSWORD}"

echo "Waiting for langfuse-web rollout after env patches..."
oc rollout status deployment/langfuse-web -n "$NAMESPACE" --timeout=300s

echo "Waiting for langfuse-worker rollout after env patches..."
oc rollout status deployment/langfuse-worker -n "$NAMESPACE" --timeout=300s

echo "Auto-provisioning configured"

# ─── 11. Health check ─────────────────────────────────────────────────────────

echo ""
echo "=== Health check ==="

sleep 5

HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "${LANGFUSE_URL}/api/public/health" || echo "000")
echo "GET /api/public/health => ${HTTP_STATUS}"

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Warning: health check returned ${HTTP_STATUS} — pod may still be starting"
  echo "Check logs: oc logs deployment/langfuse-web -n ${NAMESPACE} --tail=30"
fi

# ─── 12. Summary ──────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo "  Langfuse deployed to ${NAMESPACE}"
echo "============================================="
echo ""
echo "  Web UI:  ${LANGFUSE_URL}"
echo "  API:     ${LANGFUSE_URL}/api/public"
echo ""
echo "  Auto-provisioned credentials:"
echo "    Email:      ${INIT_USER_EMAIL}"
echo "    Password:   ${INIT_USER_PASSWORD}"
echo "    Org:        ${INIT_ORG_NAME}"
echo "    Project:    ${INIT_PROJECT_NAME}"
echo ""
echo "  API Keys (for clients):"
echo "    Public:  ${INIT_PUBLIC_KEY}"
echo "    Secret:  ${INIT_SECRET_KEY}"
echo ""
echo "  Client integration (set these env vars on your app):"
echo "    LANGFUSE_PUBLIC_KEY=${INIT_PUBLIC_KEY}"
echo "    LANGFUSE_SECRET_KEY=${INIT_SECRET_KEY}"
echo "    LANGFUSE_HOST=${LANGFUSE_URL}"
echo ""
echo "  Supported clients:"
echo "    - Python SDK:     langfuse.Langfuse(public_key=..., secret_key=..., host=...)"
echo "    - JS SDK:         new Langfuse({ publicKey, secretKey, baseUrl })"
echo "    - OpenAI wrapper: from langfuse.openai import openai (auto-traces)"
echo "    - LangChain:      CallbackHandler(public_key=..., secret_key=..., host=...)"
echo "    - OTEL/OTLP:      POST to /api/public/otel/v1/traces with Basic auth"
echo ""
echo "  State file:  ${STATE_FILE}"
echo ""
echo "  Verify:"
echo "    oc get pods -n ${NAMESPACE}"
echo "    curl -sk ${LANGFUSE_URL}/api/public/health"
echo "    curl -s -u '${INIT_PUBLIC_KEY}:${INIT_SECRET_KEY}' ${LANGFUSE_URL}/api/public/traces?limit=1"
echo "============================================="
