# Integrating MLflow with OpenClaw (Claw-Operator)

Connect OpenClaw instances (deployed via claw-operator) to an MLflow server for trace collection, feedback, and evaluations.

## Prerequisites

- MLflow deployed on OpenShift (via `../scripts/deploy-traces-mlflow.sh`)
- OpenClaw instances deployed via `1-deploy-claw.sh`
- `oc login` as cluster-admin or namespace admin

## Architecture

```
OpenClaw gateway pod                    MLflow pod (mlflow namespace)
┌──────────────────────┐                ┌─────────────────────┐
│  diagnostics-otel    │── OTLP/HTTP ──>│  /v1/traces         │
│  extension           │                │  (OTLP endpoint)    │
│                      │                │                     │
│  OTEL env vars set   │                │  PostgreSQL backend │
│  in openclaw.json    │                │  (traces stored)    │
└──────────────────────┘                └─────────────────────┘
```

OpenClaw has a built-in OpenTelemetry extension (`diagnostics-otel`) that exports spans via OTLP/HTTP. MLflow has a built-in OTLP ingestion endpoint at `/v1/traces`. No code changes needed — just configuration.

## Step 1: Get the MLflow endpoint

```bash
MLFLOW_URL="https://$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}')"
echo "MLflow: ${MLFLOW_URL}"

# Verify it's healthy
curl -sk "${MLFLOW_URL}/health"
# Expected: {"status":"OK"}
```

## Step 2: Get the experiment ID

The `deploy-traces-mlflow.sh` script creates an `openclaw-traces` experiment. Look up its ID:

```bash
curl -sk "${MLFLOW_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=openclaw-traces" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['experiment']['experiment_id'])"
# Expected: 1
```

Or create one if it doesn't exist:

```bash
curl -sk -X POST "${MLFLOW_URL}/api/2.0/mlflow/experiments/create" \
  -H "Content-Type: application/json" \
  -d '{"name": "openclaw-traces"}'
# Returns: {"experiment_id":"1"}
```

Save the experiment ID for the next step:

```bash
EXPERIMENT_ID=1
```

## Step 3: Enable diagnostics-otel in OpenClaw

Patch each OpenClaw gateway to enable the OTEL diagnostics extension and point it at MLflow.

### Single namespace (student mode)

```bash
NS=$(oc project -q)

oc exec deployment/instance -n "$NS" -c gateway -- node -e "
  const fs = require('fs');
  const f = '/home/node/.openclaw/openclaw.json';
  const c = JSON.parse(fs.readFileSync(f));

  // Enable diagnostics
  c.diagnostics = c.diagnostics || {};
  c.diagnostics.enabled = true;

  // Enable diagnostics-otel plugin
  if (!c.plugins) c.plugins = {};
  if (!c.plugins.allow) c.plugins.allow = [];
  if (!c.plugins.allow.includes('diagnostics-otel')) {
    c.plugins.allow.push('diagnostics-otel');
  }
  if (!c.plugins.entries) c.plugins.entries = {};
  c.plugins.entries['diagnostics-otel'] = { enabled: true };

  // Configure OTEL export to MLflow
  if (!c.env) c.env = {};
  c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = '${MLFLOW_URL}/v1/traces';
  c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = 'x-mlflow-experiment-id=${EXPERIMENT_ID}';

  fs.writeFileSync(f, JSON.stringify(c, null, 2));
  console.log('OK — diagnostics-otel enabled, pointing at MLflow');
"

# Restart to pick up config
oc rollout restart deployment/instance -n "$NS"
oc rollout status deployment/instance -n "$NS" --timeout=120s
```

### Multiple namespaces (admin mode)

```bash
MLFLOW_URL="https://$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}')"
EXPERIMENT_ID=1

for i in $(seq 1 5); do
  NS="agentic-user${i}"
  echo "=== Configuring $NS ==="

  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const f = '/home/node/.openclaw/openclaw.json';
    const c = JSON.parse(fs.readFileSync(f));
    c.diagnostics = c.diagnostics || {};
    c.diagnostics.enabled = true;
    if (!c.plugins) c.plugins = {};
    if (!c.plugins.allow) c.plugins.allow = [];
    if (!c.plugins.allow.includes('diagnostics-otel')) {
      c.plugins.allow.push('diagnostics-otel');
    }
    if (!c.plugins.entries) c.plugins.entries = {};
    c.plugins.entries['diagnostics-otel'] = { enabled: true };
    if (!c.env) c.env = {};
    c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = '${MLFLOW_URL}/v1/traces';
    c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = 'x-mlflow-experiment-id=${EXPERIMENT_ID}';
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
    console.log('OK');
  " 2>/dev/null && echo "  Patched" || echo "  WARN: could not patch"

  oc rollout restart deployment/instance -n "$NS"
done

# Wait for all rollouts
for i in $(seq 1 5); do
  oc rollout status deployment/instance -n "agentic-user${i}" --timeout=120s 2>/dev/null || true
done
```

## Step 4: Verify traces are flowing

1. Send a message in any OpenClaw instance (via UI or Telegram)
2. Check the MLflow UI:
   ```bash
   open "${MLFLOW_URL}"
   ```
3. Navigate to **Experiments > openclaw-traces > Traces** tab
4. Or query via API:
   ```bash
   curl -sk "${MLFLOW_URL}/api/2.0/mlflow/traces?experiment_id=${EXPERIMENT_ID}" \
     | python3 -m json.tool | head -20
   ```

## Step 5: Add feedback on traces

### Via the MLflow UI

1. Open a trace in the MLflow UI
2. Click on a span to see inputs/outputs
3. Use the built-in feedback controls (thumbs up/down, comments)

### Via Python client

```bash
pip install mlflow
```

```python
import mlflow

mlflow.set_tracking_uri("https://<ROUTE_HOST>")

# List recent traces
traces = mlflow.search_traces(experiment_ids=["1"])
print(traces[["trace_id", "timestamp_ms", "status"]].head())

# Add feedback
from mlflow.entities import AssessmentSource, AssessmentSourceType

mlflow.log_feedback(
    trace_id="<trace-id-from-ui>",
    name="user_rating",
    value=True,   # thumbs up (False = thumbs down)
    source=AssessmentSource(
        source_type=AssessmentSourceType.HUMAN,
        source_id="burr@example.com"
    ),
    rationale="Good response, used MCP tools correctly"
)
```

## Step 6: Run evaluations

```python
import mlflow
from mlflow.genai.scorers import Guidelines

mlflow.set_tracking_uri("https://<ROUTE_HOST>")

results = mlflow.genai.evaluate(
    data=mlflow.genai.datasets.traces_from_experiment("openclaw-traces"),
    scorers=[
        Guidelines(name="helpful", guideline="Is the response helpful and accurate?"),
        Guidelines(name="tool_use", guideline="Did the agent use MCP tools appropriately?"),
    ]
)
print(results.tables["eval_results"])
```

## NetworkPolicy Note

The claw-operator's default egress NetworkPolicy only allows port 443. MLflow's Route uses TLS edge termination (port 443), so OTLP/HTTP traffic from the gateway pod through the proxy to the MLflow Route works without any supplemental NetworkPolicy.

If MLflow is accessed via a ClusterIP service (not a Route), add a supplemental NetworkPolicy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-proxy-to-mlflow
spec:
  podSelector:
    matchLabels:
      app: claw-proxy
      claw.sandbox.redhat.com/instance: instance
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: mlflow
          podSelector:
            matchLabels:
              app.kubernetes.io/name: mlflow
      ports:
        - port: 5000
          protocol: TCP
```

## Disabling OTEL export

To stop sending traces to MLflow:

```bash
NS=$(oc project -q)

oc exec deployment/instance -n "$NS" -c gateway -- node -e "
  const fs = require('fs');
  const f = '/home/node/.openclaw/openclaw.json';
  const c = JSON.parse(fs.readFileSync(f));
  if (c.plugins && c.plugins.entries && c.plugins.entries['diagnostics-otel']) {
    c.plugins.entries['diagnostics-otel'].enabled = false;
  }
  if (c.env) {
    delete c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;
    delete c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS;
  }
  fs.writeFileSync(f, JSON.stringify(c, null, 2));
  console.log('OK — diagnostics-otel disabled');
"

oc rollout restart deployment/instance -n "$NS"
```

## Reference

| Component | Location |
|-----------|----------|
| MLflow deploy script | `../scripts/deploy-traces-mlflow.sh` |
| MLflow namespace | `mlflow` |
| MLflow OTLP endpoint | `https://<mlflow-route>/v1/traces` |
| Experiment name | `openclaw-traces` |
| OpenClaw OTEL extension | `diagnostics-otel` plugin |
| Config file (in pod) | `/home/node/.openclaw/openclaw.json` |
