#!/usr/bin/env bash
# deploy-broker-ocp.sh — Deploy the session broker to OpenShift
#
# Builds the broker container image in-cluster and deploys it as a
# Deployment + Service + Route. No AWS, no custom domain needed.
#
# Usage:
#   ./deploy-broker-ocp.sh              # build and deploy
#   ./deploy-broker-ocp.sh --rebuild    # force a new image build
#
# The broker runs in the "session-broker" namespace. After deploying,
# run ./update-broker-ocp.sh to inject routes and start assigning users.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BROKER_SRC="${SCRIPT_DIR}/../load-balancer/broker"
BROKER_NS="session-broker"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# --- Args ---
REBUILD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--rebuild]"
      echo "  --rebuild    Force a new image build"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# --- Preflight ---
if ! oc whoami &>/dev/null; then
  echo -e "${RED}Error: Not logged in to OpenShift. Run 'oc login' first.${RESET}"
  exit 1
fi

if [[ ! -d "$BROKER_SRC" ]]; then
  echo -e "${RED}Error: Broker source not found at ${BROKER_SRC}${RESET}"
  exit 1
fi

echo -e "${BOLD}=== Deploy Session Broker to OpenShift ===${RESET}"
echo ""

# --- Namespace ---
if ! oc get ns "$BROKER_NS" &>/dev/null; then
  echo -e "  Creating namespace ${CYAN}${BROKER_NS}${RESET}..."
  oc new-project "$BROKER_NS" --display-name="Session Broker" >/dev/null
  echo -e "  ${GREEN}✓${RESET} Namespace created"
else
  echo -e "  ${GREEN}✓${RESET} Namespace ${BROKER_NS} exists"
fi
echo ""

# --- Build ---
echo -e "${BOLD}--- Image Build ---${RESET}"

BUILD_EXISTS=false
if oc get bc session-broker -n "$BROKER_NS" &>/dev/null; then
  BUILD_EXISTS=true
fi

if [[ "$BUILD_EXISTS" == "false" ]]; then
  echo "  Creating BuildConfig..."
  oc new-build --binary --strategy=docker --name=session-broker -n "$BROKER_NS" \
    --docker-image=registry.access.redhat.com/ubi9/nodejs-22:latest 2>&1 \
    | sed 's/^/    /'
  echo ""
fi

if [[ "$BUILD_EXISTS" == "false" ]] || $REBUILD; then
  echo "  Starting build from ${BROKER_SRC}..."
  oc start-build session-broker --from-dir="$BROKER_SRC" -n "$BROKER_NS" --follow 2>&1 \
    | tail -5 | sed 's/^/    /'
  echo -e "  ${GREEN}✓${RESET} Build complete"
else
  echo -e "  ${GREEN}✓${RESET} Build exists (use --rebuild to force)"
fi
echo ""

# --- Deployment ---
echo -e "${BOLD}--- Deployment ---${RESET}"

if ! oc get deployment session-broker -n "$BROKER_NS" &>/dev/null; then
  echo "  Creating Deployment + Service..."
  cat <<'DEPLOY_EOF' | oc apply -n "$BROKER_NS" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: session-broker
  labels:
    app: session-broker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: session-broker
  template:
    metadata:
      labels:
        app: session-broker
    spec:
      containers:
      - name: broker
        image: image-registry.openshift-image-registry.svc:5000/session-broker/session-broker:latest
        ports:
        - containerPort: 3000
        env:
        - name: PORT
          value: "3000"
        - name: DB_PATH
          value: /var/lib/route-lb/broker.db
        - name: ROUTES_CSV_PATH
          value: /var/lib/route-lb/routes.csv
        - name: COOKIE_DOMAIN
          value: ""
        - name: TRUST_PROXY
          value: "1"
        volumeMounts:
        - name: data
          mountPath: /var/lib/route-lb
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 30
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: session-broker
  labels:
    app: session-broker
spec:
  selector:
    app: session-broker
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
DEPLOY_EOF
  echo -e "  ${GREEN}✓${RESET} Deployment + Service created"
else
  echo -e "  ${GREEN}✓${RESET} Deployment exists"
fi

# --- Route ---
if ! oc get route session-broker -n "$BROKER_NS" &>/dev/null; then
  echo "  Creating Route (edge TLS)..."
  oc create route edge session-broker \
    --service=session-broker \
    --port=3000 \
    -n "$BROKER_NS" 2>/dev/null
  echo -e "  ${GREEN}✓${RESET} Route created"
else
  echo -e "  ${GREEN}✓${RESET} Route exists"
fi
echo ""

# --- Wait for rollout ---
echo -e "${BOLD}--- Waiting for rollout ---${RESET}"
oc rollout status deployment/session-broker -n "$BROKER_NS" --timeout=120s 2>&1 | sed 's/^/  /'
echo ""

# --- Summary ---
BROKER_HOST=$(oc get route session-broker -n "$BROKER_NS" -o jsonpath='{.spec.host}' 2>/dev/null)
echo -e "${GREEN}${BOLD}=== Broker deployed ===${RESET}"
echo ""
echo -e "  Broker URL: ${CYAN}https://${BROKER_HOST}${RESET}"
echo ""
echo -e "  ${DIM}Next: Run ./update-broker-ocp.sh --rotate-status-key to inject routes${RESET}"
echo ""
