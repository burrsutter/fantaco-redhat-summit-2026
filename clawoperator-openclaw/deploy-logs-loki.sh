#!/usr/bin/env bash
# deploy-logs-loki.sh
#
# Deploys centralized logging on OpenShift using:
#   - Loki Operator (log storage, backed by S3)
#   - Cluster Logging Operator (log collection via Vector)
#
# Enables the OpenShift Console "Observe → Logs" tab across all namespaces.
#
# Usage: ./deploy-logs-loki.sh
#
# Idempotent — safe to re-run. Skips resources that already exist.
#
# Prerequisites:
#   - oc logged in as cluster-admin
#   - aws CLI configured (with permissions to create S3 buckets, IAM users/policies)
#   - Cluster running on AWS

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
LOKI_CHANNEL="stable-6.2"
CLO_CHANNEL="stable-6.2"
LOKISTACK_SIZE="1x.extra-small"
RETENTION_DAYS=3
S3_REGION="us-east-2"          # same region as the OpenShift cluster
STATE_DIR="$(cd "$(dirname "$0")" && pwd)/.state"
STATE_FILE="${STATE_DIR}/logging.env"

# ─── 1. Pre-flight ───────────────────────────────────────────────────────────

echo "=== Pre-flight checks ==="

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi
echo "Logged in as: $(oc whoami)"

if ! command -v aws &>/dev/null; then
  echo "Error: aws CLI not found — install and configure it first" >&2
  exit 1
fi
echo "AWS CLI: $(aws --version 2>&1 | head -1)"

# Verify AWS credentials work
if ! aws sts get-caller-identity &>/dev/null; then
  echo "Error: AWS credentials not configured — run 'aws configure' first" >&2
  exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: ${AWS_ACCOUNT}"

CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "")
if [[ -z "$CLUSTER_ID" ]]; then
  echo "Error: could not determine cluster infrastructure name — is this an AWS cluster?" >&2
  exit 1
fi
echo "Cluster ID: ${CLUSTER_ID}"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
echo "Cluster domain: ${CLUSTER_DOMAIN:-unknown}"

# ─── 2. Create S3 bucket ─────────────────────────────────────────────────────

echo ""
echo "=== S3 bucket ==="

# Use last 8 chars of cluster ID for uniqueness
CLUSTER_SUFFIX="${CLUSTER_ID: -8}"
BUCKET_NAME="openclaw-loki-${CLUSTER_SUFFIX}"

if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$S3_REGION" 2>/dev/null; then
  echo "Bucket s3://${BUCKET_NAME} already exists — skipping"
else
  echo "Creating bucket s3://${BUCKET_NAME} in ${S3_REGION}..."
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$S3_REGION" \
    --create-bucket-configuration LocationConstraint="$S3_REGION"
  echo "Bucket created"
fi

# ─── 3. Create IAM user + policy ─────────────────────────────────────────────

echo ""
echo "=== IAM user (openclaw-loki-s3) ==="

IAM_USER="openclaw-loki-s3"

if aws iam get-user --user-name "$IAM_USER" &>/dev/null; then
  echo "IAM user ${IAM_USER} already exists — skipping user creation"
else
  echo "Creating IAM user ${IAM_USER}..."
  aws iam create-user --user-name "$IAM_USER"
  echo "IAM user created"
fi

# Ensure the policy is attached (idempotent — put-user-policy overwrites)
# Use wildcard so all openclaw-loki-* buckets are accessible (multi-cluster support)
POLICY_NAME="openclaw-loki-s3-access"
echo "Attaching S3 access policy (${POLICY_NAME}) — covers all openclaw-loki-* buckets..."
aws iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name "$POLICY_NAME" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": [
          \"s3:ListBucket\",
          \"s3:PutObject\",
          \"s3:GetObject\",
          \"s3:DeleteObject\"
        ],
        \"Resource\": [
          \"arn:aws:s3:::openclaw-loki-*\",
          \"arn:aws:s3:::openclaw-loki-*/*\"
        ]
      }
    ]
  }"
echo "Policy attached"

# ─── 4. Save AWS state / create access key ────────────────────────────────────

echo ""
echo "=== AWS state ==="

mkdir -p "$STATE_DIR"

IAM_ARN=$(aws iam get-user --user-name "$IAM_USER" --query 'User.Arn' --output text)

# Reuse existing access key if state file exists and key is still valid
if [[ -f "$STATE_FILE" ]]; then
  source "$STATE_FILE"
  if [[ -n "${AWS_ACCESS_KEY_ID_LOKI:-}" ]] && \
     aws iam list-access-keys --user-name "$IAM_USER" --query "AccessKeyMetadata[?AccessKeyId=='${AWS_ACCESS_KEY_ID_LOKI}'].Status" --output text 2>/dev/null | grep -q Active; then
    echo "Reusing existing access key from ${STATE_FILE}"
    ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID_LOKI"
    SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY_LOKI"
  else
    echo "Existing access key invalid — creating new one"
    KEY_JSON=$(aws iam create-access-key --user-name "$IAM_USER" --output json)
    ACCESS_KEY_ID=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
    SECRET_ACCESS_KEY=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")
  fi
else
  echo "Creating access key for ${IAM_USER}..."
  KEY_JSON=$(aws iam create-access-key --user-name "$IAM_USER" --output json)
  ACCESS_KEY_ID=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  SECRET_ACCESS_KEY=$(echo "$KEY_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")
  echo "Access key created"
fi

# Write state file
cat > "$STATE_FILE" <<EOF
# Loki S3 state — generated by deploy-logs-loki.sh
# DO NOT commit this file (contains secrets)
BUCKET_NAME="${BUCKET_NAME}"
S3_REGION="${S3_REGION}"
IAM_USER="${IAM_USER}"
IAM_ARN="${IAM_ARN}"
AWS_ACCESS_KEY_ID_LOKI="${ACCESS_KEY_ID}"
AWS_SECRET_ACCESS_KEY_LOKI="${SECRET_ACCESS_KEY}"
EOF
chmod 600 "$STATE_FILE"
echo "State saved to ${STATE_FILE}"

# ─── 5. Install Loki Operator ────────────────────────────────────────────────

echo ""
echo "=== Loki Operator (${LOKI_CHANNEL}) ==="

# Ensure the namespace exists
if ! oc get namespace openshift-operators-redhat &>/dev/null; then
  oc create namespace openshift-operators-redhat
  echo "Created namespace openshift-operators-redhat"
fi

if oc get subscription loki-operator -n openshift-operators-redhat &>/dev/null; then
  echo "Loki Operator subscription already exists — skipping"
else
  echo "Creating Loki Operator subscription..."
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators-redhat
spec:
  channel: "${LOKI_CHANNEL}"
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "Subscription created"
fi

# Also ensure the OperatorGroup exists
if ! oc get operatorgroup -n openshift-operators-redhat 2>/dev/null | grep -q .; then
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-operators-redhat
  namespace: openshift-operators-redhat
spec: {}
EOF
  echo "OperatorGroup created"
fi

# ─── 6. Wait for Loki Operator ───────────────────────────────────────────────

echo ""
echo "=== Waiting for Loki Operator CSV ==="

TIMEOUT=300
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CSV_PHASE=$(oc get csv -n openshift-operators-redhat -l operators.coreos.com/loki-operator.openshift-operators-redhat="" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$CSV_PHASE" == "Succeeded" ]]; then
    CSV_NAME=$(oc get csv -n openshift-operators-redhat -l operators.coreos.com/loki-operator.openshift-operators-redhat="" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "Loki Operator ready: ${CSV_NAME}"
    break
  fi
  echo "  Waiting... (${ELAPSED}s, phase: ${CSV_PHASE:-pending})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: Loki Operator did not reach Succeeded in ${TIMEOUT}s"
  echo "Check: oc get csv -n openshift-operators-redhat"
fi

# ─── 7. Create openshift-logging namespace ───────────────────────────────────

echo ""
echo "=== Namespace (openshift-logging) ==="

if oc get namespace openshift-logging &>/dev/null; then
  echo "Namespace openshift-logging already exists"
else
  oc create namespace openshift-logging
  echo "Namespace openshift-logging created"
fi

# ─── 8. Create S3 credentials Secret ─────────────────────────────────────────

echo ""
echo "=== Secret (logging-loki-s3) ==="

oc apply -n openshift-logging -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
type: Opaque
stringData:
  access_key_id: "${ACCESS_KEY_ID}"
  access_key_secret: "${SECRET_ACCESS_KEY}"
  bucketnames: "${BUCKET_NAME}"
  endpoint: "https://s3.${S3_REGION}.amazonaws.com"
  region: "${S3_REGION}"
EOF
echo "Secret applied"

# ─── 9. Create LokiStack CR ──────────────────────────────────────────────────

echo ""
echo "=== LokiStack (logging-loki, ${LOKISTACK_SIZE}) ==="

oc apply -n openshift-logging -f - <<EOF
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: ${LOKISTACK_SIZE}
  storage:
    schemas:
      - version: v13
        effectiveDate: "2024-10-25"
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  limits:
    global:
      retention:
        days: ${RETENTION_DAYS}
EOF
echo "LokiStack CR applied"

# ─── 10. Wait for LokiStack ──────────────────────────────────────────────────

echo ""
echo "=== Waiting for LokiStack ==="

TIMEOUT=300
INTERVAL=15
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  READY=$(oc get lokistack logging-loki -n openshift-logging \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "$READY" == "True" ]]; then
    echo "LokiStack is ready"
    break
  fi
  REASON=$(oc get lokistack logging-loki -n openshift-logging \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || echo "unknown")
  echo "  Waiting... (${ELAPSED}s, reason: ${REASON})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: LokiStack did not become ready in ${TIMEOUT}s"
  echo "Check: oc get lokistack -n openshift-logging -o yaml"
  echo "Pods:  oc get pods -n openshift-logging -l app.kubernetes.io/instance=logging-loki"
fi

# ─── 11. Install Cluster Logging Operator ────────────────────────────────────

echo ""
echo "=== Cluster Logging Operator (${CLO_CHANNEL}) ==="

# Ensure the OperatorGroup exists for openshift-logging
if ! oc get operatorgroup -n openshift-logging 2>/dev/null | grep -q .; then
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  targetNamespaces:
    - openshift-logging
EOF
  echo "OperatorGroup created"
fi

if oc get subscription cluster-logging -n openshift-logging &>/dev/null; then
  echo "Cluster Logging Operator subscription already exists — skipping"
else
  echo "Creating Cluster Logging Operator subscription..."
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  channel: "${CLO_CHANNEL}"
  installPlanApproval: Automatic
  name: cluster-logging
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "Subscription created"
fi

# ─── 12. Wait for CLO ────────────────────────────────────────────────────────

echo ""
echo "=== Waiting for Cluster Logging Operator CSV ==="

TIMEOUT=300
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CSV_PHASE=$(oc get csv -n openshift-logging -l operators.coreos.com/cluster-logging.openshift-logging="" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$CSV_PHASE" == "Succeeded" ]]; then
    CSV_NAME=$(oc get csv -n openshift-logging -l operators.coreos.com/cluster-logging.openshift-logging="" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "Cluster Logging Operator ready: ${CSV_NAME}"
    break
  fi
  echo "  Waiting... (${ELAPSED}s, phase: ${CSV_PHASE:-pending})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: Cluster Logging Operator did not reach Succeeded in ${TIMEOUT}s"
  echo "Check: oc get csv -n openshift-logging"
fi

# ─── 13. Create ServiceAccount + role bindings (before CLF) ───────────────────

echo ""
echo "=== ServiceAccount (cluster-logging) ==="

if ! oc get sa cluster-logging -n openshift-logging &>/dev/null; then
  oc create sa cluster-logging -n openshift-logging
  echo "ServiceAccount cluster-logging created"
else
  echo "ServiceAccount cluster-logging already exists"
fi

# Collect roles (allow CLO to collect logs from pods)
for ROLE in collect-application-logs collect-infrastructure-logs; do
  if ! oc get clusterrolebinding "cluster-logging-${ROLE}" &>/dev/null 2>&1; then
    oc adm policy add-cluster-role-to-user "${ROLE}" \
      -z cluster-logging -n openshift-logging 2>/dev/null || \
    oc create clusterrolebinding "cluster-logging-${ROLE}" \
      --clusterrole="${ROLE}" \
      --serviceaccount=openshift-logging:cluster-logging 2>/dev/null || true
    echo "Bound ${ROLE} to cluster-logging SA"
  else
    echo "ClusterRoleBinding cluster-logging-${ROLE} already exists"
  fi
done

# Write roles (allow Vector to push logs to Loki via the gateway OPA)
for ROLE in logging-collector-logs-writer cluster-logging-write-application-logs cluster-logging-write-audit-logs cluster-logging-write-infrastructure-logs; do
  if oc get clusterrole "${ROLE}" &>/dev/null 2>&1; then
    if ! oc get clusterrolebinding "sa-${ROLE}" &>/dev/null 2>&1; then
      oc create clusterrolebinding "sa-${ROLE}" \
        --clusterrole="${ROLE}" \
        --serviceaccount=openshift-logging:cluster-logging
      echo "Bound ${ROLE} to cluster-logging SA"
    else
      echo "ClusterRoleBinding sa-${ROLE} already exists"
    fi
  fi
done

# Read roles for admin user (allow viewing logs in the console)
ADMIN_USER=$(oc whoami)
for ROLE in cluster-logging-application-view cluster-logging-infrastructure-view; do
  if oc get clusterrole "${ROLE}" &>/dev/null 2>&1; then
    if ! oc get clusterrolebinding "logging-admin-${ROLE}" &>/dev/null 2>&1; then
      oc create clusterrolebinding "logging-admin-${ROLE}" \
        --clusterrole="${ROLE}" \
        --user="${ADMIN_USER}"
      echo "Bound ${ROLE} to ${ADMIN_USER}"
    else
      echo "ClusterRoleBinding logging-admin-${ROLE} already exists"
    fi
  fi
done

# ─── 14. Create Loki gateway CA secret (for TLS) ─────────────────────────────

echo ""
echo "=== Loki gateway CA secret ==="

# The LokiStack uses the OpenShift service-serving CA for TLS. Vector needs this
# CA to trust the Loki gateway connection. Extract it from the auto-generated
# configmap and create a secret that the ClusterLogForwarder can reference.
echo "Waiting for Loki gateway CA bundle..."
TIMEOUT=120
INTERVAL=5
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if oc get configmap logging-loki-gateway-ca-bundle -n openshift-logging &>/dev/null; then
    echo "CA bundle configmap found"
    break
  fi
  echo "  Waiting... (${ELAPSED}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if oc get configmap logging-loki-gateway-ca-bundle -n openshift-logging &>/dev/null; then
  CA_CERT=$(oc get configmap logging-loki-gateway-ca-bundle -n openshift-logging \
    -o jsonpath='{.data.service-ca\.crt}' 2>/dev/null)
  if [[ -n "$CA_CERT" ]]; then
    oc create secret generic loki-gateway-ca -n openshift-logging \
      --from-literal=ca-bundle.crt="$CA_CERT" \
      --dry-run=client -o yaml | oc apply -f -
    echo "Secret loki-gateway-ca created/updated"
  else
    echo "Warning: service-ca.crt not found in CA bundle — Vector may fail to connect to Loki"
  fi
else
  echo "Warning: logging-loki-gateway-ca-bundle configmap not found — Vector may fail to connect to Loki"
fi

# ─── 15. Create ClusterLogForwarder CR ────────────────────────────────────────

echo ""
echo "=== ClusterLogForwarder ==="

oc apply -n openshift-logging -f - <<EOF
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  serviceAccount:
    name: cluster-logging
  outputs:
    - name: default-lokistack
      type: lokiStack
      tls:
        ca:
          key: ca-bundle.crt
          secretName: loki-gateway-ca
      lokiStack:
        target:
          name: logging-loki
          namespace: openshift-logging
        authentication:
          token:
            from: serviceAccount
  pipelines:
    - name: application-logs
      inputRefs:
        - application
      outputRefs:
        - default-lokistack
    - name: infrastructure-logs
      inputRefs:
        - infrastructure
      outputRefs:
        - default-lokistack
EOF
echo "ClusterLogForwarder CR applied"

# ─── 16. Wait for collector DaemonSet ─────────────────────────────────────────

echo ""
echo "=== Waiting for Vector collector ==="

TIMEOUT=180
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  DESIRED=$(oc get daemonset -n openshift-logging -l component=collector \
    -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo "0")
  READY=$(oc get daemonset -n openshift-logging -l component=collector \
    -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo "0")
  if [[ "$DESIRED" -gt 0 && "$DESIRED" == "$READY" ]]; then
    echo "Vector collector DaemonSet ready: ${READY}/${DESIRED} nodes"
    break
  fi
  echo "  Waiting... (${ELAPSED}s, ready: ${READY}/${DESIRED})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: collector DaemonSet not fully ready in ${TIMEOUT}s"
  echo "Check: oc get daemonset -n openshift-logging -l component=collector"
  echo "Pods:  oc get pods -n openshift-logging -l component=collector"
fi

# ─── 17. Install Cluster Observability Operator (for console Logs tab) ────────

echo ""
echo "=== Cluster Observability Operator ==="

if oc get subscription cluster-observability-operator -n openshift-operators &>/dev/null; then
  echo "Cluster Observability Operator subscription already exists — skipping"
else
  echo "Creating Cluster Observability Operator subscription..."
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
  echo "Subscription created"
fi

echo "Waiting for Cluster Observability Operator CSV..."
TIMEOUT=300
INTERVAL=10
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  CSV_PHASE=$(oc get csv -n openshift-operators \
    -l operators.coreos.com/cluster-observability-operator.openshift-operators="" \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [[ "$CSV_PHASE" == "Succeeded" ]]; then
    CSV_NAME=$(oc get csv -n openshift-operators \
      -l operators.coreos.com/cluster-observability-operator.openshift-operators="" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    echo "Cluster Observability Operator ready: ${CSV_NAME}"
    break
  fi
  # Auto-approve install plan if needed
  PLAN_NAME=$(oc get subscription cluster-observability-operator -n openshift-operators \
    -o jsonpath='{.status.installPlanRef.name}' 2>/dev/null || echo "")
  if [[ -n "$PLAN_NAME" ]]; then
    PLAN_APPROVED=$(oc get installplan "$PLAN_NAME" -n openshift-operators \
      -o jsonpath='{.spec.approved}' 2>/dev/null || echo "true")
    if [[ "$PLAN_APPROVED" == "false" ]]; then
      echo "  Approving install plan ${PLAN_NAME}..."
      oc patch installplan "$PLAN_NAME" -n openshift-operators --type merge -p '{"spec":{"approved":true}}'
    fi
  fi
  echo "  Waiting... (${ELAPSED}s, phase: ${CSV_PHASE:-pending})"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "Warning: Cluster Observability Operator did not reach Succeeded in ${TIMEOUT}s"
  echo "Check: oc get csv -n openshift-operators"
fi

# ─── 18. Create UIPlugin for logging console view ────────────────────────────

echo ""
echo "=== UIPlugin (logging console view) ==="

# Wait for UIPlugin CRD to become available (Cluster Observability Operator may still be starting)
echo "Waiting for UIPlugin CRD..."
CRD_TIMEOUT=120
CRD_ELAPSED=0
while [[ $CRD_ELAPSED -lt $CRD_TIMEOUT ]]; do
  if oc api-resources 2>/dev/null | grep -q uiplugin; then
    echo "UIPlugin CRD available"
    break
  fi
  echo "  Waiting... (${CRD_ELAPSED}s)"
  sleep 10
  CRD_ELAPSED=$((CRD_ELAPSED + 10))
done

if [[ $CRD_ELAPSED -ge $CRD_TIMEOUT ]]; then
  echo "Warning: UIPlugin CRD not available after ${CRD_TIMEOUT}s"
  echo "The Logs tab will not appear in the OpenShift Console"
else
  oc apply -f - <<EOF
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
    logsLimit: 50
EOF
  echo "UIPlugin applied"

  echo "Waiting for logging console plugin..."
  TIMEOUT=120
  INTERVAL=10
  ELAPSED=0
  while [[ $ELAPSED -lt $TIMEOUT ]]; do
    PLUGINS=$(oc get console.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' 2>/dev/null || echo "[]")
    if echo "$PLUGINS" | grep -q "logging"; then
      echo "Logging console plugin enabled"
      break
    fi
    echo "  Waiting... (${ELAPSED}s)"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "Warning: logging console plugin not enabled in ${TIMEOUT}s"
  fi
fi

# ─── 19. Health check ─────────────────────────────────────────────────────────

echo ""
echo "=== Health check ==="

# LokiStack pods
LOKI_PODS=$(oc get pods -n openshift-logging -l app.kubernetes.io/instance=logging-loki --no-headers 2>/dev/null | wc -l | tr -d ' ')
LOKI_READY=$(oc get pods -n openshift-logging -l app.kubernetes.io/instance=logging-loki --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "LokiStack pods: ${LOKI_READY}/${LOKI_PODS} Running"

# Collector pods
COLLECTOR_PODS=$(oc get pods -n openshift-logging -l component=collector --no-headers 2>/dev/null | wc -l | tr -d ' ')
COLLECTOR_READY=$(oc get pods -n openshift-logging -l component=collector --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo "Collector pods: ${COLLECTOR_READY}/${COLLECTOR_PODS} Running"

# Quick log query test — try to query logs from the last 5 minutes
echo ""
echo "Testing log query..."
QUERY_RESULT=$(oc exec -n openshift-logging \
  $(oc get pods -n openshift-logging -l app.kubernetes.io/component=query-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) \
  -- curl -s "http://localhost:3100/loki/api/v1/query?query=%7Bkubernetes_namespace_name%3D%22openshift-logging%22%7D&limit=1" 2>/dev/null || echo '{"status":"error"}')

if echo "$QUERY_RESULT" | grep -q '"success"'; then
  echo "Log query test: OK"
else
  echo "Log query test: skipped (query-frontend may still be starting)"
fi

# ─── 20. Summary ──────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo "  Centralized Logging Deployed"
echo "============================================="
echo ""
echo "  Components:"
echo "    Loki Operator:                  ${LOKI_CHANNEL}"
echo "    Cluster Logging Operator:       ${CLO_CHANNEL}"
echo "    Cluster Observability Operator: stable"
echo "    LokiStack size:                 ${LOKISTACK_SIZE}"
echo "    Log retention:                  ${RETENTION_DAYS} days"
echo ""
echo "  S3 Storage:"
echo "    Bucket: s3://${BUCKET_NAME}"
echo "    Region: ${S3_REGION}"
echo "    IAM user: ${IAM_USER}"
echo ""
echo "  State file: ${STATE_FILE}"
echo ""
echo "  ── Access Logs ──"
echo "  OpenShift Console → Observe → Logs"
echo "    Filter by namespace: agentic-user1, agentic-user2, etc."
echo "    Filter by pod: gateway, instance-proxy, etc."
echo ""
echo "  ── Example Queries ──"
echo "    {kubernetes_namespace_name=\"agentic-user1\"}"
echo "    {kubernetes_namespace_name=~\"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5\"}"
echo "    NOTE: namespace wildcards (.*) are NOT allowed — use explicit alternation (|)"
echo ""
echo "  ── Log Flow ──"
echo "  container stdout → Vector (DaemonSet) → LokiStack → Console"
echo ""
echo "  ── Verify ──"
echo "    oc get pods -n openshift-logging"
echo "    oc get lokistack -n openshift-logging"
echo "    oc get clusterlogforwarder -n openshift-logging"
echo "    oc get uiplugin logging"
echo "============================================="
