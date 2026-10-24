#!/usr/bin/env bash
# Deploy the optional collector that copies OTLP spans to MLflow and CloudWatch.
set -euo pipefail

if [[ "${INSTALLATION_TYPE:-}" != "aws" ]]; then
  echo "CloudWatch traces require INSTALLATION_TYPE=aws; skip this step for OCP/ODF" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
ROLE_NAME="${CLOUDWATCH_TRACE_ROLE_NAME:-$(oc whoami --show-server | sed -E 's|^https?://api\.([^.:]+).*|\1|')-cloudwatch-traces}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

[[ "$AWS_REGION" =~ ^[a-z0-9-]+$ ]] || { echo "Invalid AWS_REGION" >&2; exit 1; }
[[ "$ROLE_NAME" =~ ^[a-zA-Z0-9+=,.@_-]+$ ]] || { echo "Invalid role name" >&2; exit 1; }
aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text >/dev/null
DESTINATION_STATUS="$(aws xray get-trace-segment-destination --region "$AWS_REGION" --query Status --output text)"
[[ "$DESTINATION_STATUS" == "ACTIVE" ]] || {
  echo "CloudWatch Transaction Search is ${DESTINATION_STATUS}; wait for ACTIVE before deploying" >&2
  exit 1
}
oc create namespace trace-forwarder --dry-run=client -o yaml | oc apply -f -
oc create configmap trace-collector-config -n trace-forwarder \
  --from-file=collector.yaml="${SCRIPT_DIR}/cloudwatch-traces/collector.yaml" \
  --dry-run=client -o yaml | oc apply -f -
sed -e "s|__AWS_REGION__|${AWS_REGION}|g" \
    -e "s|__AWS_ROLE_ARN__|${ROLE_ARN}|g" \
    "${SCRIPT_DIR}/cloudwatch-traces/kubernetes.yaml" | oc apply -f -
oc rollout restart deployment/trace-collector -n trace-forwarder
oc rollout status deployment/trace-collector -n trace-forwarder --timeout=180s
echo "Collector: http://trace-collector.trace-forwarder.svc.cluster.local:4318/v1/traces"
