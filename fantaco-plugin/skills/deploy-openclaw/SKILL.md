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

**First, load keys from the project `.env` file** (at the repository root). Source it to pick up `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `TELEGRAM_BOT_TOKEN`:

```bash
ENV_FILE="${PROJECT_ROOT:-.}/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi
```

Use values from `.env` automatically. Only ask the user with `AskUserQuestion` if a key is empty or matches a placeholder (`CHANGE_ME`, or `sk-ant-your-*` pattern):

- `OPENAI_API_KEY` — if set and not a placeholder, use it silently. Otherwise ask: "Provide an OpenAI-compatible API key?" (Yes → ask for value / No → leave empty)
- `ANTHROPIC_API_KEY` — if set and not a placeholder (`CHANGE_ME` or matching `sk-ant-your-*`), use it silently. Otherwise ask: "Provide an Anthropic API key?" (Yes → ask for value / No → leave empty)
- `TELEGRAM_BOT_TOKEN` — if set and not a placeholder, use it silently. Otherwise ask: "Provide a Telegram bot token?" (Yes → ask for value / No → leave empty)

Report which keys were loaded from `.env` so the user knows what's being used.

Create the `openclaw-secrets` Secret with the resolved values:

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
  TELEGRAM_BOT_TOKEN: "<USER_VALUE_OR_EMPTY>"
EOF
```

## Step 3a: Build model provider configuration

Before creating the ConfigMap, determine which model providers to configure based on the API keys resolved in Step 3.

**Placeholder detection** — treat these values as "not set":
- Empty string
- `CHANGE_ME`
- Values matching `sk-ant-your-*` (the `.env.example` placeholder for Anthropic)

**Build the providers object using this logic:**

1. **If `OPENAI_API_KEY` is set and not a placeholder** → add an `openai` provider:
```json
"openai": {
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
}
```

2. **If `ANTHROPIC_API_KEY` is set and not a placeholder** → add an `anthropic` provider:
```json
"anthropic": {
    "apiKey": "${ANTHROPIC_API_KEY}",
    "models": [
        {
            "id": "claude-sonnet-4-6",
            "name": "Claude Sonnet 4.6"
        }
    ]
}
```

3. **If neither key is available** → leave `"providers": {}` empty and warn the user: "No model API keys found — the gateway will start but agents cannot respond until a model is configured."

**Default model priority** (for `agents.defaults.model.primary`):
- If OpenAI is available → `"openai/gpt-5.4"`
- Else if Anthropic is available → `"anthropic/claude-sonnet-4-6"`
- Else → omit the `model` key from `agents.defaults`

**Report to the user:**
- Which providers were configured (e.g., "Configured model providers: openai (gpt-5.4), anthropic (claude-sonnet-4-6)")
- Which model is the default (e.g., "Default agent model: openai/gpt-5.4")
- Which keys were skipped and why (e.g., "Skipped ANTHROPIC_API_KEY: matches placeholder pattern sk-ant-your-*")

## Step 4: Create ConfigMap

Create the `openclaw-config` ConfigMap with a minimal `openclaw.json` and allow-all `exec-approvals.json`.

**Note:** The `controlUi.allowedOrigins` will be empty initially. After the Route is created in Step 8, patch the ConfigMap with the route hostname (see Step 8).

**Use the model provider configuration built in Step 3a.** Insert the providers determined there into the `models.providers` object, and if a default model was determined, add `"model": {"primary": "<DEFAULT_MODEL>"}` to `agents.defaults`.

For example, if both OpenAI and Anthropic keys were available, the ConfigMap would look like:

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
        "bind": "lan",
        "controlUi": {
          "allowedOrigins": []
        }
      },
      "models": {
        "providers": {
          "openai": {
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
          }
        }
      },
      "agents": {
        "defaults": {
          "workspace": "~/.openclaw/workspace",
          "model": {
            "primary": "openai/gpt-5.4"
          },
          "heartbeat": {
            "every": "30m",
            "target": "telegram",
            "isolatedSession": true,
            "lightContext": true
          }
        },
        "list": []
      },
      "mcp": {
        "servers": {}
      },
      "channels": {},
      "cron": {
        "enabled": true
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

**Adapt this heredoc based on Step 3a results:**
- If only OpenAI is available → include only the `openai` provider, set `"primary": "openai/gpt-5.4"`
- If only Anthropic is available → include only the `anthropic` provider, set `"primary": "anthropic/claude-sonnet-4-6"`
- If neither is available → use `"providers": {}` and omit the `"model"` key from `agents.defaults`
- The `"apiKey": "${OPENAI_API_KEY}"` and `"apiKey": "${ANTHROPIC_API_KEY}"` values use the literal env var names — the gateway resolves them at runtime from the pod environment variables (set via the Secret in Step 3)

**If the user provided a Telegram bot token in Step 3**, replace `"channels": {}` in the heredoc above with:

```json
"channels": {
  "telegram": {
    "enabled": true,
    "dmPolicy": "pairing",
    "botToken": "<TELEGRAM_TOKEN_FROM_STEP_3>"
  }
}
```

If no token was provided, leave `"channels": {}` as-is. The heartbeat will queue but won't deliver until Telegram is configured later.

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

## Step 7: Create Service

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

## Step 8: Create Route and patch ConfigMap

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

Now patch the ConfigMap to add the route hostname to `controlUi.allowedOrigins` (required for the Control UI to load). **This must happen before creating the Deployment** so the init container copies a ConfigMap that already includes the correct origin:

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

## Step 9: Create Deployment

**OpenClaw image:** Both containers use a **digest-pinned** reference so deploys are reproducible. To bump: pull the desired tag from `ghcr.io/openclaw/openclaw`, note the resolved digest (registry UI, `oc get pod … -o jsonpath='{.status.containerStatuses[?(@.name=="gateway")].imageID}'`, or `crane digest ghcr.io/openclaw/openclaw:<tag>`), and replace the `sha256:…` below in both `image:` fields.

Create the `openclaw` Deployment with an init container that copies config from the ConfigMap to the PVC, and the main `gateway` container.

**IMPORTANT:** The main container MUST be named `gateway` — existing scripts (`approve-telegram-pairing.sh`) and skills (`/fantaco:openclaw-inject-mcp-servers`) exec into `-c gateway`.

**IMPORTANT:** This step must come **after** the Route and ConfigMap patch (Step 8) so the init container copies a ConfigMap that already has the correct `allowedOrigins`.

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
          image: ghcr.io/openclaw/openclaw@sha256:0b2170d5ec3a487a6313ed0556d377c5c5c80a0f806043daa2e685a4bedd45e3
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
          image: ghcr.io/openclaw/openclaw@sha256:0b2170d5ec3a487a6313ed0556d377c5c5c80a0f806043daa2e685a4bedd45e3
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

## Step 12a: Approve device pairing

After the user enters the token in the UI, the gateway requires a server-side approval before the browser is fully connected. **Wait for the user to confirm they have entered the token**, then approve the pending pairing request:

1. List pending devices:
```bash
oc exec deployment/openclaw -c gateway -- openclaw devices list
```

2. Find the pending request ID (UUID in the "Request" column), then approve it:
```bash
oc exec deployment/openclaw -c gateway -- openclaw devices approve <REQUEST_UUID>
```

3. Tell the user to refresh the browser — the UI should now connect.

**If the user says "pairing required" at any point later**, repeat the two commands above (list → approve) to approve the pending device.

## Step 13: Next steps

Tell the user:

**Already enabled:** Cron, heartbeat (every 30m → Telegram), and model providers (auto-configured from `.env` API keys) are configured out of the box.

1. **Inject MCP servers** so agents can access FantaCo services:
   ```
   /fantaco:openclaw-inject-mcp-servers
   ```

2. **Inject sub-agents** (Account Watchdog, Finance Monitor) for autonomous monitoring:
   ```
   /fantaco:openclaw-inject-sub-agents
   ```

3. **If Telegram was configured** — pair your Telegram account:
   ```
   /fantaco:openclaw-pairing
   ```
