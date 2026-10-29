#!/usr/bin/env bash
# Deploy the portable PostgreSQL-backed broker with two or more replicas.
# The database uses the cluster's default StorageClass and OpenShift's
# CloudNativePG operator; no cloud-specific endpoint is embedded in the app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BROKER_NS="session-broker"
REBUILD=false
if [[ "${1:-}" == "--rebuild" ]]; then
  REBUILD=true
  shift
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--rebuild]" >&2
  exit 1
fi

oc whoami >/dev/null
# Every broker-pg manifest hardcodes `namespace: session-broker` and none of
# them declares it, so create it here. The pre-PostgreSQL deploy-broker-ocp.sh
# did this; dropping it only looked safe because the clusters it ran on already
# had the namespace from that earlier script.
oc get namespace "$BROKER_NS" >/dev/null 2>&1 ||
  oc new-project "$BROKER_NS" --display-name="Session Broker" >/dev/null ||
  oc create namespace "$BROKER_NS" >/dev/null

oc apply -f "$SCRIPT_DIR/broker-pg/openshift/cloudnativepg-operator.yaml"
for _ in $(seq 1 60); do
  OPERATOR_CSV=$(oc get subscription cloudnative-pg -n "$BROKER_NS" \
    -o jsonpath='{.status.currentCSV}' 2>/dev/null || true)
  [[ -n "$OPERATOR_CSV" ]] && break
  sleep 5
done
if [[ -z "${OPERATOR_CSV:-}" ]]; then
  echo "Error: CloudNativePG subscription did not select an operator." >&2
  exit 1
fi
oc wait "csv/$OPERATOR_CSV" -n "$BROKER_NS" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s

if ! oc get storageclass -o json | python3 -c '
import json, sys
items = json.load(sys.stdin)["items"]
assert any(i["metadata"].get("annotations", {}).get("storageclass.kubernetes.io/is-default-class") == "true" for i in items)
'; then
  echo "Error: a default StorageClass is required for the broker database." >&2
  exit 1
fi

oc apply -f "$SCRIPT_DIR/broker-pg/openshift/broker-db.yaml"
oc wait cluster/broker-db -n "$BROKER_NS" --for=condition=Ready --timeout=600s

if ! oc get buildconfig session-broker -n "$BROKER_NS" >/dev/null 2>&1; then
  oc new-build --binary --strategy=docker --name=session-broker -n "$BROKER_NS" \
    --docker-image=registry.access.redhat.com/ubi9/nodejs-22:latest
  REBUILD=true
fi
CURRENT_BROKER_ENV=$(oc get deployment session-broker -n "$BROKER_NS" \
  -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null || true)
WAS_POSTGRES=false
if grep -qw PGHOST <<< "$CURRENT_BROKER_ENV"; then
  WAS_POSTGRES=true
fi
if $REBUILD || ! grep -qw PGHOST <<< "$CURRENT_BROKER_ENV"; then
  oc start-build session-broker --from-dir="$SCRIPT_DIR/broker-pg" -n "$BROKER_NS" --follow
  BUILD_NAME=$(oc get builds -n "$BROKER_NS" -l buildconfig=session-broker \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
  oc wait "build/$BUILD_NAME" -n "$BROKER_NS" \
    --for=jsonpath='{.status.phase}'=Complete --timeout=180s
  BUILD_PHASE=$(oc get "build/$BUILD_NAME" -n "$BROKER_NS" \
    -o jsonpath='{.status.phase}')
  if [[ "$BUILD_PHASE" != "Complete" ]]; then
    echo "Error: latest broker image build is $BUILD_PHASE" >&2
    exit 1
  fi
fi

CLUSTER_GUID=$(oc whoami --show-server | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
BROKER_ENV="$SCRIPT_DIR/.state/$CLUSTER_GUID/broker.env"
if [[ ! -f "$BROKER_ENV" ]]; then
  echo "Error: missing $BROKER_ENV (run audience-reset.sh first)." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$BROKER_ENV"
if [[ -z "${STATUS_KEY:-}" ]]; then
  # audience-reset.sh writes only AUDIENCE_CODE; STATUS_KEY is minted by
  # update-broker-ocp.sh, which QUICKSTART runs *after* this script. Refusing
  # here made a fresh cluster unbootstrappable and only looked fine on clusters
  # where an earlier run had already populated the file. Mint one on the same
  # terms update-broker-ocp.sh uses; --rotate-status-key will replace it later.
  STATUS_KEY=$(python3 -c "import secrets; print(secrets.token_hex(8))")
  printf 'STATUS_KEY=%s\n' "$STATUS_KEY" >> "$BROKER_ENV"
  echo "Generated STATUS_KEY and saved it to $BROKER_ENV"
fi
oc create secret generic session-broker-status \
  --from-literal=status-key="$STATUS_KEY" \
  -n "$BROKER_NS" --dry-run=client -o yaml | oc apply -f - >/dev/null

oc apply -f "$SCRIPT_DIR/broker-pg/openshift/broker.yaml"
if $REBUILD && $WAS_POSTGRES; then
  oc rollout restart deployment/session-broker -n "$BROKER_NS"
fi
oc rollout status deployment/session-broker -n "$BROKER_NS" --timeout=300s

echo "PostgreSQL-backed broker ready. Run update-broker-ocp.sh to sync routes."
