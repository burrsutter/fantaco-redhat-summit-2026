#!/usr/bin/env bash
# Mirror the six FantaCo demo images into the cluster registry. This avoids
# Docker Hub pull limits when many audience namespaces start together.

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi
for command in oc podman python3; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done
oc whoami >/dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_GUID=$(oc whoami --show-server | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
STATE_DIR="$SCRIPT_DIR/.state/$CLUSTER_GUID"
MIRROR_NS="${FANTACO_MIRROR_NS:-demo-images}"
ARCH=$(oc get nodes -l node-role.kubernetes.io/worker \
  -o jsonpath='{.items[0].status.nodeInfo.architecture}')
if [[ -z "$ARCH" ]]; then
  echo "Could not detect worker architecture" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"
oc get namespace "$MIRROR_NS" >/dev/null 2>&1 || oc create namespace "$MIRROR_NS" >/dev/null
oc policy add-role-to-group system:image-puller system:serviceaccounts \
  -n "$MIRROR_NS" >/dev/null 2>&1

CREATED_ROUTE=false
if ! oc get route default-route -n openshift-image-registry >/dev/null 2>&1; then
  oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
    -p '{"spec":{"defaultRoute":true}}' >/dev/null
  CREATED_ROUTE=true
fi

AUTH_FILE="$STATE_DIR/registry-auth.json"
cleanup() {
  python3 - "$AUTH_FILE" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).unlink(missing_ok=True)
PY
  if $CREATED_ROUTE; then
    oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
      -p '{"spec":{"defaultRoute":false}}' >/dev/null || true
  fi
}
trap cleanup EXIT

REGISTRY_HOST=""
for _ in $(seq 1 30); do
  REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)
  [[ -n "$REGISTRY_HOST" ]] && break
  sleep 2
done
if [[ -z "$REGISTRY_HOST" ]]; then
  echo "The registry route did not become available" >&2
  exit 1
fi

oc registry login --registry "$REGISTRY_HOST" --insecure --to "$AUTH_FILE" >/dev/null
chmod 600 "$AUTH_FILE"

images=(
  fantaco-customer-main:1.0.0
  fantaco-product-main:1.0.0
  fantaco-sales-order-main:1.0.0
  mcp-server-customer:2.0.0
  mcp-server-product:2.0.0
  mcp-server-sales-order:2.0.0
)
# Pull from docker.io/burrsutter.
#
# quay.io/openclawopenshift carries the same six names and tags, and we tried
# switching to it 2026-11-18 — but THE IMAGES ARE NOT THE SAME CONTENT. The
# quay mcp-server-* images are missing the httpx Python module and crashloop:
#   ModuleNotFoundError: No module named 'httpx'
# That took out ~298 pods, all three MCP servers on every seat. Verified
# directly: docker.io has httpx 0.28.1, quay has no httpx at all, same tag.
#
# Matching names and tags do NOT mean matching content. Do not switch back
# until the quay images are rebuilt and a pod actually starts from them.
#
# Mirroring into the cluster registry is still worth doing: it turns 600
# public pulls into six, and the anonymous Docker Hub limit is otherwise hit
# around seat 62 and presents as a broken demo rather than a quota error.
SOURCE_REGISTRY="${FANTACO_SOURCE_REGISTRY:-docker.io/burrsutter}"

for image in "${images[@]}"; do
  source_image="$SOURCE_REGISTRY/$image"
  target_image="$REGISTRY_HOST/$MIRROR_NS/$image"
  podman pull --arch "$ARCH" "$source_image"
  podman tag "$source_image" "$target_image"
  podman push --authfile "$AUTH_FILE" --tls-verify=false "$target_image"
  echo "Mirrored $image"
done

printf 'FANTACO_IMAGE_PREFIX=image-registry.openshift-image-registry.svc:5000/%s/\n' \
  "$MIRROR_NS" > "$STATE_DIR/image-mirror.env"
chmod 600 "$STATE_DIR/image-mirror.env"
echo "Future FantaCo deployments will use the cluster registry."
