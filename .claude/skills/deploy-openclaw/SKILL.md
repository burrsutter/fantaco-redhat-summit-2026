---
name: deploy-openclaw
description: Deploy the OpenClaw AI agent gateway to OpenShift
argument-hint: "[namespace]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Deploy OpenClaw AI Agent Gateway

Deploy the OpenClaw gateway to the current OpenShift namespace using raw Kubernetes manifests applied via heredocs. No external manifest files are needed.

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

If `$ARGUMENTS` is provided and non-empty, switch to that namespace:

```bash
oc project "$ARGUMENTS"
```

Report the current user and namespace to the user.

## Step 2: Check existing deployment

Check if OpenClaw is already deployed:

```bash
oc get deployment openclaw -o name 2>/dev/null
```

If the deployment already exists, ask the user with `AskUserQuestion`:
- **Upgrade** — re-apply all manifests (keeps PVC data)
- **Delete + reinstall** — delete all OpenClaw resources and recreate from scratch
- **Abort** — stop without changes

If "Delete + reinstall" is chosen:
```bash
oc delete deployment openclaw --ignore-not-found
oc delete service openclaw-service --ignore-not-found
oc delete route openclaw-route --ignore-not-found
oc delete configmap openclaw-config --ignore-not-found
oc delete secret openclaw-secrets --ignore-not-found
oc delete networkpolicy openclaw-egress --ignore-not-found
oc delete pvc openclaw-data --ignore-not-found
```

Wait 10 seconds after deletion before proceeding.

## Step 3: Create Secret

Ask the user with `AskUserQuestion`: "Do you have an LLM API key to configure now?"

- **Yes** — ask a follow-up question for the API key value, then use it in the Secret below
- **No / Skip** — create the Secret with empty placeholders (user can configure later via `setup-openclaw.sh`)

If the user provides a key, also ask which provider it is for:
- **OpenAI-compatible** (most common — works with vLLM, LiteLLM, OpenRouter, etc.) — store as `OPENAI_API_KEY`
- **Anthropic** — store as `ANTHROPIC_API_KEY`

Create the `openclaw-secrets` Secret, substituting the user's key if provided:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-secrets
  labels:
    app: openclaw
type: Opaque
stringData:
  ANTHROPIC_API_KEY: "<USER_VALUE_OR_EMPTY>"
  OPENAI_API_KEY: "<USER_VALUE_OR_EMPTY>"
EOF
```

## Step 4: Create ConfigMap

Create the `openclaw-config` ConfigMap with a minimal `openclaw.json` and allow-all `exec-approvals.json`.

**Note:** The `controlUi.allowedOrigins` will be empty initially. After the Route is created in Step 9, patch the ConfigMap with the route hostname (see Step 9).

```bash
oc apply -f - <<'EOF'
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
        "bind": "0.0.0.0",
        "controlUi": {
          "allowedOrigins": [],
          "dangerouslyDisableDeviceAuth": true
        }
      },
      "models": {
        "providers": {}
      },
      "agents": {
        "defaults": {
          "workspace": "~/.openclaw/workspace"
        },
        "list": []
      },
      "mcp": {
        "servers": {}
      },
      "channels": {},
      "cron": {
        "enabled": false
      }
    }
  exec-approvals.json: |
    {
      "version": "1.0",
      "defaultPolicy": "allow",
      "rules": []
    }
EOF
```

## Step 5: Create PVC

Create the `openclaw-data` PVC for persistent gateway data:

```bash
oc apply -f - <<'EOF'
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
      storage: 10Gi
EOF
```

## Step 6: Create NetworkPolicy

Create the `openclaw-egress` NetworkPolicy. Uses allow-all egress because OpenClaw needs to reach external LLM APIs (Anthropic, OpenAI, etc.) and in-cluster MCP servers. Port-restricted policies break on some OVN-Kubernetes clusters.

```bash
oc apply -f - <<'EOF'
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
```

## Step 7: Create Deployment

Create the `openclaw` Deployment with an init container that copies config from the ConfigMap to the PVC, and the main `gateway` container:

**IMPORTANT:** The main container MUST be named `gateway` — existing scripts (`approve-telegram-pairing.sh`, `inject-mcp-openclaw.sh`) exec into `-c gateway`.

```bash
oc apply -f - <<'EOF'
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
          image: ghcr.io/openclaw/openclaw:latest
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
          image: ghcr.io/openclaw/openclaw:latest
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
            initialDelaySeconds: 15
            periodSeconds: 30
            timeoutSeconds: 5
          readinessProbe:
            tcpSocket:
              port: 18789
            initialDelaySeconds: 10
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
```

## Step 8: Create Service

Create the `openclaw-service` Service:

```bash
oc apply -f - <<'EOF'
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
```

## Step 9: Create Route

Create the `openclaw-route` Route with edge TLS termination:

```bash
oc apply -f - <<'EOF'
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
```

Now patch the ConfigMap to add the route hostname to `controlUi.allowedOrigins` (required for the Control UI to load):

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
PATCHED=$(oc get configmap openclaw-config -o jsonpath='{.data.openclaw\.json}' | python3 -c "
import sys, json
config = json.load(sys.stdin)
config['gateway']['controlUi'] = {'allowedOrigins': ['https://${ROUTE_HOST}']}
print(json.dumps(config, indent=2))
")
oc patch configmap openclaw-config --type merge -p "{\"data\":{\"openclaw.json\":$(echo "$PATCHED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")}}"
```

## Step 10: Wait and verify

Wait for the rollout to complete:

```bash
oc rollout status deployment/openclaw --timeout=120s
```

Then check pod status:

```bash
oc get pods -l app=openclaw
```

If any pod is not Running/Ready, show the last 30 lines of logs:

```bash
oc logs deployment/openclaw -c gateway --tail=30
```

## Step 11: Smoke test

Get the route URL and test connectivity:

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://${ROUTE_HOST}/")
echo "Route: https://${ROUTE_HOST}"
echo "HTTP Status: ${HTTP_STATUS}"
```

Report whether the route is responding (any non-5xx status is acceptable for an unconfigured gateway).

## Step 12: Retrieve auth token and open in browser

Extract the gateway auth token from the running pod's config:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json; print(json.load(sys.stdin).get('gateway',{}).get('auth',{}).get('token','(no token found)'))"
```

Display the token to the user so they can log in to the UI.

Then open the route in the default browser:

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
open "https://${ROUTE_HOST}"
```

## Step 13: Next steps

Tell the user:

1. **Configure the gateway** with a model, MCP servers, and optionally Telegram:
   ```
   ./scripts/setup-openclaw.sh \
     --model-name "qwen3-14b" \
     --model-url "https://your-model-server/v1" \
     --model-api-key "sk-..." \
     --mcp customer=https://mcp-customer-route.apps.example.com/mcp \
     --mcp finance=https://mcp-finance-route.apps.example.com/mcp
   ```

2. **Inject MCP servers** (alternative to setup-openclaw.sh for MCP-only changes):
   ```
   ./scripts/inject-mcp-openclaw.sh
   ```

3. **Approve Telegram pairing** (after setting up Telegram):
   ```
   ./scripts/approve-telegram-pairing.sh <PAIRING_CODE>
   ```
