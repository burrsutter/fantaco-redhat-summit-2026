#!/usr/bin/env bash
# deploy-openclaw-dev15.sh
#
# Deploys a minimal OpenClaw instance into a target namespace with only
# two integrations: the customer MCP server (cross-namespace from
# parasol-insurance-dev) and Telegram. No sub-agents, no skills, no cron,
# no heartbeat.
#
# Usage: ./deploy-openclaw-dev15.sh <namespace>
#
# Idempotent — safe to re-run. The target namespace must already exist.
#
# Required:
#   - oc logged in to the target cluster
#   - .env file at the repository root with TELEGRAM_BOT_TOKEN, TELEGRAM_USER_ID,
#     and at least one of OPENAI_API_KEY or ANTHROPIC_API_KEY

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <namespace>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="$1"
IMAGE="ghcr.io/openclaw/openclaw@sha256:0b2170d5ec3a487a6313ed0556d377c5c5c80a0f806043daa2e685a4bedd45e3"

# ─── 1. Pre-flight ─────────────────────────────────────────────────────────────

echo "=== Pre-flight checks ==="

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi
echo "Logged in as: $(oc whoami)"

CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
if [[ -z "$CLUSTER_DOMAIN" ]]; then
  echo "Warning: could not auto-detect CLUSTER_DOMAIN" >&2
fi
echo "Cluster domain: ${CLUSTER_DOMAIN:-unknown}"

# Source .env
ENV_FILE="$PROJECT_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  echo "Loaded .env from $ENV_FILE"
else
  echo "Error: .env not found at $ENV_FILE" >&2
  exit 1
fi

# Validate required vars
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "Error: TELEGRAM_BOT_TOKEN not set in .env" >&2
  exit 1
fi
if [[ -z "${TELEGRAM_USER_ID:-}" ]]; then
  echo "Warning: TELEGRAM_USER_ID not set — Telegram will accept messages from anyone" >&2
fi

# Check for at least one model API key
IS_PLACEHOLDER_ANTHROPIC=false
if [[ -z "${ANTHROPIC_API_KEY:-}" || "${ANTHROPIC_API_KEY}" == "CHANGE_ME" || "${ANTHROPIC_API_KEY}" == sk-ant-your-* ]]; then
  IS_PLACEHOLDER_ANTHROPIC=true
fi

HAS_OPENAI=false
if [[ -n "${OPENAI_API_KEY:-}" && "${OPENAI_API_KEY}" != "CHANGE_ME" ]]; then
  HAS_OPENAI=true
fi

HAS_ANTHROPIC=false
if [[ "$IS_PLACEHOLDER_ANTHROPIC" == "false" ]]; then
  HAS_ANTHROPIC=true
fi

if [[ "$HAS_OPENAI" == "false" && "$HAS_ANTHROPIC" == "false" ]]; then
  echo "Error: need at least one of OPENAI_API_KEY or ANTHROPIC_API_KEY in .env" >&2
  exit 1
fi

echo "Model providers: openai=$HAS_OPENAI anthropic=$HAS_ANTHROPIC"
echo "Telegram bot token: set"
echo "Telegram user ID: ${TELEGRAM_USER_ID:-not set}"

# Verify namespace exists (must be pre-created)
echo ""
echo "=== Namespace ==="
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
  echo "Error: namespace $NAMESPACE does not exist — it must be created before running this script" >&2
  exit 1
fi
echo "Namespace $NAMESPACE exists"

# ─── 2. Secret ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Secret (openclaw-secrets) ==="

SECRET_DATA="  TELEGRAM_BOT_TOKEN: \"${TELEGRAM_BOT_TOKEN}\""
if [[ "$HAS_OPENAI" == "true" ]]; then
  SECRET_DATA="${SECRET_DATA}
  OPENAI_API_KEY: \"${OPENAI_API_KEY}\""
fi
if [[ "$HAS_ANTHROPIC" == "true" ]]; then
  SECRET_DATA="${SECRET_DATA}
  ANTHROPIC_API_KEY: \"${ANTHROPIC_API_KEY}\""
fi

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
  labels:
    app: openclaw
type: Opaque
stringData:
${SECRET_DATA}
EOF
echo "Secret applied"

# ─── 3. ConfigMap ──────────────────────────────────────────────────────────────

echo ""
echo "=== ConfigMap (openclaw-config) ==="

# Build providers JSON
PROVIDERS=""
if [[ "$HAS_OPENAI" == "true" && "$HAS_ANTHROPIC" == "true" ]]; then
  PROVIDERS='"openai": {
            "baseUrl": "https://api.openai.com/v1",
            "apiKey": "${OPENAI_API_KEY}",
            "api": "openai-completions",
            "models": [
              {
                "id": "gpt-5.4",
                "name": "GPT-5.4",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 128000,
                "maxTokens": 16384
              }
            ]
          },
          "anthropic": {
            "apiKey": "${ANTHROPIC_API_KEY}",
            "models": [
              {
                "id": "claude-sonnet-4-6",
                "name": "Claude Sonnet 4.6"
              }
            ]
          }'
  DEFAULT_MODEL='"model": { "primary": "openai/gpt-5.4" }'
elif [[ "$HAS_OPENAI" == "true" ]]; then
  PROVIDERS='"openai": {
            "baseUrl": "https://api.openai.com/v1",
            "apiKey": "${OPENAI_API_KEY}",
            "api": "openai-completions",
            "models": [
              {
                "id": "gpt-5.4",
                "name": "GPT-5.4",
                "reasoning": false,
                "input": ["text"],
                "contextWindow": 128000,
                "maxTokens": 16384
              }
            ]
          }'
  DEFAULT_MODEL='"model": { "primary": "openai/gpt-5.4" }'
else
  PROVIDERS='"anthropic": {
            "apiKey": "${ANTHROPIC_API_KEY}",
            "models": [
              {
                "id": "claude-sonnet-4-6",
                "name": "Claude Sonnet 4.6"
              }
            ]
          }'
  DEFAULT_MODEL='"model": { "primary": "anthropic/claude-sonnet-4-6" }'
fi

# Telegram allowFrom — dmPolicy "open" requires allowFrom ["*"]
ALLOW_FROM="\"*\""

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  labels:
    app: openclaw
data:
  openclaw.json: |
    {
      "gateway": {
        "port": 18789,
        "bind": "lan",
        "controlUi": {
          "allowedOrigins": []
        }
      },
      "models": {
        "providers": {
          ${PROVIDERS}
        }
      },
      "agents": {
        "defaults": {
          "workspace": "~/.openclaw/workspace",
          ${DEFAULT_MODEL}
        },
        "list": []
      },
      "mcp": {
        "servers": {
          "customer": {
            "url": "http://mcp-customer-service.parasol-insurance-dev.svc.cluster.local:9001/mcp"
          }
        }
      },
      "channels": {
        "telegram": {
          "enabled": true,
          "dmPolicy": "open",
          "allowFrom": [${ALLOW_FROM}],
          "botToken": "\${TELEGRAM_BOT_TOKEN}"
        }
      }
    }
  exec-approvals.json: |
    {
      "version": "1.0",
      "defaultPolicy": "allow",
      "rules": []
    }
EOF
echo "ConfigMap applied"

# ─── 4. PVC ────────────────────────────────────────────────────────────────────

echo ""
echo "=== PVC (openclaw-data, 2Gi) ==="

oc apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openclaw-data
  labels:
    app: openclaw
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF
echo "PVC applied"

# ─── 5. NetworkPolicy ─────────────────────────────────────────────────────────

echo ""
echo "=== NetworkPolicy (openclaw-egress) ==="

oc apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-egress
  labels:
    app: openclaw
spec:
  podSelector:
    matchLabels:
      app: openclaw
  policyTypes:
    - Egress
  egress:
    - {}
EOF
echo "NetworkPolicy applied"

# ─── 6. Service ────────────────────────────────────────────────────────────────

echo ""
echo "=== Service (openclaw-service) ==="

oc apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: openclaw-service
  labels:
    app: openclaw
spec:
  selector:
    app: openclaw
  ports:
    - port: 18789
      targetPort: 18789
      protocol: TCP
  type: ClusterIP
EOF
echo "Service applied"

# ─── 7. Route + patch ConfigMap with allowedOrigins ────────────────────────────

echo ""
echo "=== Route (openclaw-route) ==="

oc apply -n "$NAMESPACE" -f - <<'EOF'
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: openclaw-route
  labels:
    app: openclaw
spec:
  to:
    kind: Service
    name: openclaw-service
    weight: 100
  port:
    targetPort: 18789
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
echo "Route applied"

ROUTE_HOST=$(oc get route openclaw-route -n "$NAMESPACE" -o jsonpath='{.spec.host}')
echo "Route host: $ROUTE_HOST"

echo "Patching ConfigMap with allowedOrigins..."
PATCHED=$(oc get configmap openclaw-config -n "$NAMESPACE" -o jsonpath='{.data.openclaw\.json}' | python3 -c "
import sys, json
config = json.load(sys.stdin)
config['gateway']['controlUi']['allowedOrigins'] = ['https://$ROUTE_HOST']
print(json.dumps(config, indent=2))
")

PATCH_PAYLOAD=$(python3 -c "
import sys, json
print(json.dumps({'data': {'openclaw.json': sys.stdin.read()}}))
" <<< "$PATCHED")

oc patch configmap openclaw-config -n "$NAMESPACE" --type merge -p "$PATCH_PAYLOAD"
echo "ConfigMap patched with allowedOrigins"

# ─── 8. Deployment ─────────────────────────────────────────────────────────────

echo ""
echo "=== Deployment (openclaw) ==="

oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw
  labels:
    app: openclaw
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: openclaw
  template:
    metadata:
      labels:
        app: openclaw
    spec:
      initContainers:
        - name: copy-config
          image: ${IMAGE}
          command:
            - sh
            - -c
            - |
              mkdir -p /home/node/.openclaw
              cp /config/openclaw.json /home/node/.openclaw/openclaw.json
              cp /config/exec-approvals.json /home/node/.openclaw/exec-approvals.json
          volumeMounts:
            - name: openclaw-data
              mountPath: /home/node/.openclaw
            - name: config-volume
              mountPath: /config
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop:
                - ALL
      containers:
        - name: gateway
          image: ${IMAGE}
          command:
            - openclaw
            - gateway
            - --bind
            - lan
            - --port
            - "18789"
            - --allow-unconfigured
          ports:
            - containerPort: 18789
              protocol: TCP
          env:
            - name: HOME
              value: /home/node
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: ANTHROPIC_API_KEY
                  optional: true
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: OPENAI_API_KEY
                  optional: true
            - name: TELEGRAM_BOT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-secrets
                  key: TELEGRAM_BOT_TOKEN
                  optional: true
          volumeMounts:
            - name: openclaw-data
              mountPath: /home/node/.openclaw
            - name: credentials
              mountPath: /run/secrets/openclaw
              readOnly: true
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
          livenessProbe:
            tcpSocket:
              port: 18789
            initialDelaySeconds: 45
            periodSeconds: 30
            timeoutSeconds: 5
          readinessProbe:
            tcpSocket:
              port: 18789
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
          securityContext:
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            capabilities:
              drop:
                - ALL
      volumes:
        - name: openclaw-data
          persistentVolumeClaim:
            claimName: openclaw-data
        - name: config-volume
          configMap:
            name: openclaw-config
        - name: credentials
          emptyDir:
            medium: Memory
            sizeLimit: 1Mi
EOF
echo "Deployment applied"

# ─── 9. Wait for rollout + smoke test ──────────────────────────────────────────

echo ""
echo "=== Waiting for rollout ==="
oc rollout status deployment/openclaw -n "$NAMESPACE" --timeout=120s

echo ""
echo "=== Pod status ==="
oc get pods -l app=openclaw -n "$NAMESPACE"

echo ""
echo "=== Smoke test ==="
ROUTE_HOST=$(oc get route openclaw-route -n "$NAMESPACE" -o jsonpath='{.spec.host}')
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://${ROUTE_HOST}/")
echo "Route:  https://${ROUTE_HOST}"
echo "HTTP:   ${HTTP_STATUS}"

if [[ "$HTTP_STATUS" =~ ^5 ]]; then
  echo "Warning: gateway returned a 5xx — checking logs..."
  oc logs deployment/openclaw -n "$NAMESPACE" -c gateway --tail=30
fi

# ─── 10. Print summary ────────────────────────────────────────────────────────

echo ""
echo "=== Retrieving auth token ==="
AUTH_TOKEN=$(oc exec deployment/openclaw -n "$NAMESPACE" -c gateway -- \
  cat /home/node/.openclaw/openclaw.json 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('gateway',{}).get('auth',{}).get('token','(no token found)'))" 2>/dev/null || echo "(could not extract token)")

echo ""
echo "============================================="
echo "  OpenClaw (minimal) deployed to ${NAMESPACE}"
echo "============================================="
echo ""
echo "  URL:   https://${ROUTE_HOST}"
echo "  Token: ${AUTH_TOKEN}"
echo ""
echo "  Integrations:"
echo "    - Customer MCP: http://mcp-customer-service.parasol-insurance-dev.svc.cluster.local:9001/mcp"
echo "    - Telegram: enabled (user ${TELEGRAM_USER_ID:-*})"
echo ""
echo "  Next steps:"
echo "    1. Open the URL above in your browser"
echo "    2. Enter the auth token"
echo "    3. Approve device pairing:"
echo "       oc exec deployment/openclaw -n ${NAMESPACE} -c gateway -- openclaw devices list"
echo "       oc exec deployment/openclaw -n ${NAMESPACE} -c gateway -- openclaw devices approve <ID>"
echo "    4. Send a message to your Telegram bot to verify"
echo "============================================="
