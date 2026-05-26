# Claw-Operator Deployment Scripts

Automate deployment of OpenClaw instances via the claw-operator for Red Hat Summit demo namespaces.

## Quick Start — Fresh Cluster (20 Users)

Prerequisites: `oc login` as cluster-admin, `../.env` populated (copy from `../.env.example`), claw-operator repo at `../../claw-operator`.

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
./0-admin-setup.sh 1 20              # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + S3)
./deploy-dashboards-grafana.sh       # Step 3: Grafana dashboards (Prometheus + Loki data sources)
./deploy-traces-mlflow.sh            # Step 4: LLM trace collection (MLflow + OTEL)
./deploy-traces-langfuse.sh          # Step 5: LLM observability (Langfuse — optional, takes priority over MLflow)

# ── Phase 2: Deploy everything + audience reset ──────────────────────
./audience-reset.sh 1 20             # Step 6: Claw instances, backends, MCP, traces, skills, URLs, broker
./enable-prometheus.sh 1 20          # Step 7: Prometheus metrics (one-time: creates ServiceMonitor + NetworkPolicy)

# ── Phase 3: Verify ──────────────────────────────────────────────────
./demo-preflight.sh 1 20             # Step 8: 15-point pre-demo check

# ── FantaCo Web UIs (per namespace) ──────────────────────────────────
# Each namespace has its own Customer, Product, and Sales Order web apps.
# Get the URLs with:
NS=agentic-user1
echo "Customers:    https://$(oc get route fantaco-customer-service -n $NS -o jsonpath='{.spec.host}')/customers/index.html"
echo "Products:     https://$(oc get route fantaco-product-service -n $NS -o jsonpath='{.spec.host}')/catalog/index.html"
echo "Sales Orders: https://$(oc get route fantaco-sales-order-service -n $NS -o jsonpath='{.spec.host}')/orders/index.html"

# ── Observability UIs ────────────────────────────────────────────────
echo "Grafana:      https://$(oc get route grafana-route -n grafana -o jsonpath='{.spec.host}')"
echo "Langfuse:     https://$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}')"
echo "MLflow:       https://$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}')"
```

`audience-reset.sh` is the main workhorse — it deploys Claw instances (if missing), FantaCo backends, MCP endpoints, enterprise skills, generates unique audience URLs, configures OTEL tracing, and updates the Route-LB broker.

`enable-prometheus.sh` must run **once** to create the ServiceMonitor and NetworkPolicy. After that, `audience-reset.sh` handles re-installing the plugin and re-patching config automatically via `post-restart-repatch.sh`.

**Before each subsequent demo**, just re-run:
```bash
./audience-reset.sh 1 20             # Wipe state, new URLs, re-inject everything
./demo-preflight.sh 1 20             # Verify
```

---

## Script Reference

### Core Workflow Scripts

#### `0-admin-setup.sh` — Cluster Setup (one-time)

Install the claw-operator, create RBAC, and grant access to student namespaces:

```bash
./0-admin-setup.sh 2 5    # agentic-user2 through agentic-user5
./0-admin-setup.sh 3      # just agentic-user3
```

This script:
1. Installs the claw-operator (if not already running) via `make dev-deploy`
2. Patches memory limits to prevent OOMKilled (512Mi limit / 128Mi request)
3. Creates the `claw-user` ClusterRole
4. Grants `claw-user` role to each student user in their namespace

#### `audience-reset.sh` — Full Demo Reset

Reset all instances for the next audience with new unique, non-guessable URLs. This is the primary script for preparing a demo:

```bash
./audience-reset.sh 1 20   # all 20 users
./audience-reset.sh 1 5    # user1 through user5
./audience-reset.sh 3      # just user3
```

This script:
1. Deploys Claw instances if they don't exist (secrets + Claw CR)
2. Generates a **unique random hostname** per user (e.g. `claw-a3kx7f.apps.<cluster>`)
3. Wipes all user state (chats, memory, cron, custom skills, config)
4. Deploys FantaCo backends (PostgreSQL, REST API, MCP server per namespace)
5. Injects MCP endpoints into gateway config
6. Re-patches model config from `.env`
7. Configures OTEL tracing (`diagnostics-otel` → MLflow, `langfuse-tracer` → Langfuse)
8. Re-installs plugins and re-patches all config via `post-restart-repatch.sh`
9. Injects enterprise persona, skills (quote-builder), and AGENTS.md
10. Injects `langfuse-tracer` plugin into pods (if Langfuse keys in `.env`)
11. Generates `routes.csv`, uploads to S3, and updates the Route-LB broker

Each URL is fully independent — knowing one URL reveals nothing about the others. The admin Route (`instance-agentic-userN.apps...`) stays intact for admin use.

**Requires admin login** — student users don't have Route create/delete permissions.

#### `enable-prometheus.sh` — Prometheus Metrics (one-time)

Enable Prometheus scraping of OpenClaw gateway diagnostics (model calls, tokens, costs, sessions):

```bash
./enable-prometheus.sh 1 5   # user1 through user5
./enable-prometheus.sh 3     # just user3
```

This script:
1. Installs the `diagnostics-prometheus` plugin via npm inside the gateway pod
2. Patches `openclaw.json` to enable `diagnostics` and the plugin
3. Creates a `NetworkPolicy` allowing Prometheus to reach port 18789
4. Creates a `ServiceMonitor` CR for auto-discovery by User Workload Monitoring
5. Restarts the gateway and re-patches all config via `post-restart-repatch.sh`

Run this **once** after the initial `audience-reset.sh`. Subsequent `audience-reset.sh` and `reset-openclaw.sh` runs automatically re-install the plugin and re-patch config if a ServiceMonitor exists.

**Prerequisites:**
- User Workload Monitoring enabled on the cluster (`enableUserWorkload: true` in `openshift-monitoring/cluster-monitoring-config`)
- OpenClaw instances already deployed

**Verify:**
```bash
PASS=$(oc get secret claw-password -n agentic-user1 -o jsonpath='{.data.password}' | base64 -d)
oc exec deployment/instance -n agentic-user1 -c gateway -- \
  curl -s -H "Authorization: Bearer $PASS" \
  http://localhost:18789/api/diagnostics/prometheus | head -20
```

#### `demo-preflight.sh` — Pre-Demo Verification

Run a comprehensive 15-point check per namespace before presenting:

```bash
./demo-preflight.sh 1 20   # check all 20 users
./demo-preflight.sh 3      # just user3
```

| # | Check | Pass Criteria |
|---|-------|---------------|
| 1 | Claw-operator running | >= 1 Running pod |
| 2 | Gateway pod running | Running |
| 3 | Proxy pod running | Running |
| 4 | Device-pairing pod running | Running |
| 5 | FantaCo customer pods | All 3 Running (postgresql, REST API, MCP) |
| 6 | Claw CR Ready | `True` |
| 7 | McpServersConfigured | `True` |
| 8 | Primary model | Matches `.env` (`GEMINI_MODEL` or `LLM_MODEL_NAME`) |
| 9 | MCP in gateway config | `mcp-customer-service:9001` present |
| 10 | Audience Route | Exists with host populated |
| 11 | allowedOrigins | Contains audience Route host |
| 12 | NetworkPolicy | `allow-proxy-to-mcp` exists |
| 13 | Proxy allowlist | Contains `mcp-customer-service` |
| 14 | Admin URL reachable | HTTP 200 or 302 |
| 15 | Audience URL reachable | HTTP 200 or 302 |

Color-coded output: green for pass, red for fail. Exits non-zero if any check fails.

#### `post-restart-repatch.sh` — Config Re-patch (internal helper)

Re-applies all custom config to `openclaw.json` after a gateway restart. Called automatically by `audience-reset.sh`, `enable-prometheus.sh`, and `reset-openclaw.sh` — you generally don't run this directly.

```bash
./post-restart-repatch.sh agentic-user3   # single namespace by name
./post-restart-repatch.sh 1 5             # agentic-user1 through agentic-user5
./post-restart-repatch.sh 3               # just agentic-user3
```

What it patches (per namespace):
1. **allowedOrigins** — audience route host + broker domain
2. **Model** — `google/{GEMINI_MODEL}` or `openai/{LLM_MODEL_NAME}` from `.env`
3. **diagnostics.otel** — full OTEL config block pointed at MLflow (if deployed)
4. **diagnostics-prometheus** plugin — only if ServiceMonitor exists
5. **diagnostics-otel** plugin — `plugins.allow` + `plugins.entries` (MLflow target only)
6. **langfuse-tracer** plugin — only if Langfuse keys in `.env` + plugin files on disk

Sources `../.env` for config values. `diagnostics-otel` always targets MLflow; `langfuse-tracer` handles Langfuse via REST API. Does NOT restart — caller is responsible for restart timing.

### Observability Scripts

#### `deploy-logs-loki.sh` — Centralized Logging

Centralized log aggregation via the OpenShift Console's **Observe → Logs** tab.

```bash
./deploy-logs-loki.sh
```

Deploys:
- **Loki Operator** + **Cluster Logging Operator** (via OperatorHub)
- **Vector** DaemonSet — collects container logs from every node
- **LokiStack** (`1x.extra-small`) — stores logs in S3, 3-day retention

Creates an S3 bucket (`openclaw-loki-<cluster-suffix>`) and IAM user. Credentials saved to `.state/logging.env`.

**Access:** OpenShift Console → **Observe → Logs** → filter by namespace/pod.

#### `deploy-traces-mlflow.sh` — MLflow Tracing (OTEL)

LLM call tracing via OpenTelemetry, exported to MLflow for visualization:

```bash
./deploy-traces-mlflow.sh
```

Deploys PostgreSQL + MLflow 3.12 server. Creates experiment `openclaw-traces`. Tracing on OpenClaw instances is configured automatically by `audience-reset.sh`.

**Access:** MLflow UI → Experiments → openclaw-traces → Traces tab.

#### `deploy-traces-langfuse.sh` — Langfuse Tracing (optional)

Richer LLM observability with prompt/response content, evaluation, and cost tracking:

```bash
./deploy-traces-langfuse.sh
```

Deploys 11 pods (web, worker, PostgreSQL, ClickHouse, Redis, MinIO, ZooKeeper). Auto-provisions org, project, user, and API keys. Credentials saved to `.state/langfuse.env` — add `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` to `../.env` for `audience-reset.sh` to use.

When both MLflow and Langfuse are deployed, each gets a dedicated trace pipeline:
- **Langfuse** receives rich traces (user prompts + model responses) via the `langfuse-tracer` plugin (REST API)
- **MLflow** receives OTEL spans (token counts, timing, model info) via `diagnostics-otel`

The `langfuse-tracer` plugin is vendored at `claw_plugins/langfuse-tracer/` and injected into pods by `audience-reset.sh`. See `LANGFUSE_INTEGRATION_PLAN.md` for full architecture details.

**Access:** `https://langfuse-langfuse.apps.<cluster>`

#### `deploy-dashboards-grafana.sh` — Grafana Dashboard

Deploys a pre-built **OpenClaw Admin Overview** dashboard:

```bash
./deploy-dashboards-grafana.sh
```

| Row | What it shows |
|-----|---------------|
| Overview | Total model calls, cost (USD), agent runs, tool executions, tokens |
| Cost & Tokens | Cost over time by user, cumulative cost, input vs output tokens |
| Model Performance | Call rate per user, p50/p95 latency, outcome breakdown |
| Agent Runs | Runs over time, duration, channel breakdown |
| Tool Usage | Executions by tool, execution rate, p95 duration |
| Per-User Summary | One row per namespace with all key metrics |

**Prerequisites:** Prometheus metrics enabled (`./enable-prometheus.sh`) and Grafana deployed.

### Utility Scripts

#### `reset-openclaw.sh` — Reset to Fresh State

Wipe all user state and restart the gateway:

```bash
./reset-openclaw.sh 2 5    # agentic-user2 through agentic-user5
./reset-openclaw.sh 3      # just agentic-user3
./reset-openclaw.sh        # current namespace (student mode)
```

This script:
1. Wipes all user state from the gateway PVC (sessions, agent DBs, memory, cron, custom skills, config)
2. Preserves the PVC, operator ConfigMap, secrets, and the `platform/` skill
3. Restarts the deployment so the gateway re-initializes from the operator ConfigMap
4. Re-installs plugins (prometheus if ServiceMonitor exists, OTEL if configured)
5. Re-patches all config via `post-restart-repatch.sh` (model, diagnostics, allowedOrigins, plugins)

After reset, the gateway has empty chats, no custom skills, no cron jobs, and no agent memory. Use `audience-reset.sh` instead if you also need new URLs, backends, and skills.

#### `clean-namespace.sh` — Remove Claw from Namespaces

Remove Claw CR and secrets (preserves operator and ClusterRole):

```bash
./clean-namespace.sh 2 5   # agentic-user2 through agentic-user5
./clean-namespace.sh 3     # just agentic-user3
```

To uninstall the operator itself: `cd ../../claw-operator && make undeploy`

#### `cluster-login.sh` — Login Helper

```bash
./cluster-login.sh 3       # log in as user3
./cluster-login.sh admin   # log in as admin
```

Sources `../.env` for credentials and derives the API server URL from `OPENSHIFT_CONSOLE_URL`.

#### `2-openclaw-status.sh` — Health Check

```bash
./2-openclaw-status.sh 2 5   # check agentic-user2 through agentic-user5
```

Checks operator pod, instance pods, Claw CR conditions, gateway logs, and URL reachability.

#### `3-open-openclaw.sh` — Open in Browser

```bash
./3-open-openclaw.sh 2 5   # open agentic-user2 through agentic-user5
```

Gets the URL from the Claw CR status and opens it in the default browser.

#### `monitor-pods.sh` — Live Pod Monitor

```bash
./monitor-pods.sh          # monitor all agentic-user namespaces (Ctrl+C to stop)
```

Live-updating display of pod status across all agentic-user namespaces. Useful during demos or while waiting for deployments.

#### `analyze-cluster-capacity.sh` — Capacity Analysis

```bash
./analyze-cluster-capacity.sh [sample-namespace]
```

Calculates cluster capacity, per-student resource footprint, and projects scaling limits for 20-100 students. Color-coded recommendations.

Also available as a skill: `/fantaco:analyze-cluster-capacity`

#### `test-network-policy.sh` — Network Security Demo

Interactive demo showing the claw-operator's two-layer security model:

```bash
./test-network-policy.sh      # current namespace
./test-network-policy.sh 3    # agentic-user3
```

| # | Prompt | Expected | Why |
|---|--------|----------|-----|
| 1 | Fetch `api.github.com/zen` | ALLOWED | GitHub is a passthrough domain |
| 2 | Search customers with "coffee" | ALLOWED | MCP via supplemental NetworkPolicy |
| 3 | Fetch `example.com` | BLOCKED (403) | Not in proxy allowlist |
| 4 | Fetch `api.nasa.gov` APOD | BLOCKED (403) | Not in proxy allowlist |
| 5 | POST to `evil.com/upload` | BLOCKED (403) | Data exfiltration denied |

Automated version: `/fantaco:test-openclaw-network-policy 3`

#### `cleanup-loki-s3.sh` — AWS Cleanup

Delete orphaned Loki S3 buckets from terminated clusters:

```bash
./cleanup-loki-s3.sh             # interactive — prompts before deleting
./cleanup-loki-s3.sh --dry-run   # list only
./cleanup-loki-s3.sh --all       # delete all openclaw-loki-* buckets
```

### Standalone Step Scripts

These scripts are called internally by `audience-reset.sh`. You do **not** need to run them separately in the normal workflow, but they can be useful for targeted operations:

| Script | What it does | When to use standalone |
|--------|-------------|----------------------|
| `1-deploy-claw.sh` | Creates secrets + Claw CR | Deploy without full audience reset |
| `4-deploy-fantaco-backends.sh` | Deploys PostgreSQL, REST API, MCP server | Re-deploy backends only |
| `5-inject-mcp-endpoints.sh` | Patches Claw CR with MCP server config | Fix MCP config without full reset |
| `6-inject-enterprise-skills.sh` | Injects quote-builder skill + AGENTS.md | Re-inject skills only |

## Provider Selection

Set `LLM_PROVIDER` in `../.env` (or as an env var):

| Provider | `LLM_PROVIDER` | Env vars needed | Auth type |
|----------|----------------|-----------------|-----------|
| GCP Vertex AI | `gcp` | `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`, `GEMINI_MODEL` | gcp (SA key) |
| LiteLLM | `litellm` | `LLM_API_KEY`, `LLM_API_BASE_URL`, `LLM_MODEL_NAME` | bearer |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` | apiKey |
| OpenAI | `openai` | `OPENAI_API_KEY` | apiKey |

### GCP Vertex AI Setup

1. Create a GCP service account with `roles/aiplatform.user`:
   ```bash
   gcloud iam service-accounts create claw-vertex --display-name="Claw Vertex AI"
   gcloud projects add-iam-policy-binding YOUR_PROJECT \
     --member="serviceAccount:claw-vertex@YOUR_PROJECT.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user" --condition=None
   gcloud iam service-accounts keys create sa-key.json \
     --iam-account=claw-vertex@YOUR_PROJECT.iam.gserviceaccount.com
   ```

2. Set `.env` variables:
   ```bash
   LLM_PROVIDER=gcp
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
   GOOGLE_CLOUD_PROJECT=your-project-id
   GOOGLE_CLOUD_LOCATION=us-central1
   GEMINI_MODEL=gemini-2.5-flash
   ```

The operator creates a proxy sidecar that handles OAuth2 token refresh — the gateway pod never sees real GCP credentials. See the [provider setup docs](https://github.com/codeready-toolchain/claw-operator/blob/master/docs/provider-setup.md) for details.

## Key Learnings

### Gateway Restart Behavior

Every `oc rollout restart` causes the claw-operator to re-seed `openclaw.json` from its ConfigMap, wiping custom config (allowedOrigins, model, plugins, diagnostics). `post-restart-repatch.sh` re-applies all config after any restart. All scripts that restart the gateway call it automatically.

### Prometheus

- **`gateway.token` is invalid with password auth.** Use the `claw-password` secret as a Bearer token instead.
- **The plugin must be npm-installed**, not just config-enabled. Install with: `node /app/dist/index.js plugins install @openclaw/diagnostics-prometheus`
- **A NetworkPolicy is required** for Prometheus to reach port 18789 on the gateway pod.

### MLflow Tracing

- **MLflow 3.x behind TLS proxy returns 403.** Fix: `MLFLOW_SERVER_DISABLE_SECURITY_MIDDLEWARE=true` (set automatically by `deploy-traces-mlflow.sh`).
- **OTEL env vars must be real container env vars.** The `env` section in `openclaw.json` is NOT read by the OTEL SDK. Use `oc set env` to set `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` etc.
- **Use the internal service URL.** The gateway pod egresses through `instance-proxy:8080`. Use `http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces` which matches `NO_PROXY=.svc.cluster.local`. A NetworkPolicy is needed for direct egress.

### Langfuse Tracing

Two separate trace pipelines feed Langfuse and MLflow:

| Plugin | Target | What it sends |
|--------|--------|---------------|
| `langfuse-tracer` | Langfuse (REST API) | User prompt text + model response text |
| `diagnostics-otel` | MLflow (OTEL) | OTEL spans with token counts, timing, model info |
| `diagnostics-prometheus` | Prometheus/Grafana | Metrics (request counts, latencies) |

The `langfuse-tracer` plugin (vendored from [MCKRUZ/openclaw-langfuse](https://github.com/MCKRUZ/openclaw-langfuse)) talks to Langfuse's REST API directly, populating native input/output fields with actual prompt and response text. `diagnostics-otel` is **not** sent to Langfuse — its OTEL spans have no input/output content and create noise in the Langfuse UI.

Key details:
- **`ENABLE_EXPERIMENTAL_FEATURES=true` is required** on both `langfuse-web` and `langfuse-worker`. Without it, the OTEL ingestion endpoint silently discards data. The deploy script sets this automatically.
- **Auto-provisioning via `LANGFUSE_INIT_*` env vars** creates org, project, user, and API keys on first startup.
- **S3 external endpoints must be patched** for presigned URL downloads.
- **Plugin files** are vendored at `claw_plugins/langfuse-tracer/` and injected into pods at `/home/node/.openclaw/extensions/langfuse-tracer/`. The extensions directory survives state resets.
- **Plugin must be registered** in `openclaw.json` (`plugins.allow` + `plugins.entries` with `allowConversationAccess: true`). Extensions are NOT auto-discovered.
- **Traces include namespace and URL** — `userId` is set to the namespace, `tags` include the audience URL. Filter by user in the Langfuse UI.
- **11 pods vs MLflow's 2** — more complex but richer features (prompt/response inspection, scoring, cost tracking).

### OTEL Plugin Configuration (MLflow)

The `diagnostics-otel` plugin always targets MLflow (never Langfuse). It requires 5 things (all handled by `audience-reset.sh` and `post-restart-repatch.sh`):
1. Plugin npm install: `node /app/dist/index.js plugins install @openclaw/diagnostics-otel`
2. `diagnostics.otel` config block with `captureContent`
3. `allowConversationAccess: true` in plugin hooks — without this, non-bundled plugins are silently blocked from conversation hooks
4. Real container env vars: `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` (pointed at MLflow), `OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental`
5. Config applied **after restart** — `oc rollout restart` re-seeds config from operator

## Environment Variables

All scripts support:

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE_PREFIX` | `agentic-user` | Namespace name prefix |

Admin setup also supports:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAW_OPERATOR_HOME` | `../../claw-operator` | Path to claw-operator repo |
| `REGISTRY` | `quay.io/bsutter` | Container image registry |
| `TAG` | `latest` | Container image tag |

## Useful Commands

```bash
# Get the URL for a namespace
oc get claw instance -n agentic-user2 -o jsonpath='{.status.url}'

# Check gateway logs
oc logs deployment/instance -n agentic-user2 -c gateway --tail=30

# Check proxy logs
oc logs deployment/instance-proxy -n agentic-user2 --tail=30

# List all Claw instances across namespaces
oc get claws -A
```
