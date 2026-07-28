# Demo Ready Guide

Everything needed to go from a fresh OpenShift cluster to a live, demo-ready FantaCo environment.

---

## What This Demo Is

FantaCo is an enterprise AI assistant demo built on [OpenClaw](https://github.com/openclaw/openclaw). Each audience member gets their own isolated OpenClaw instance connected to three FantaCo backend APIs (Customer, Product, Sales Order) via MCP servers. The demo showcases enterprise AI capabilities — tool use, observability (Prometheus metrics, Grafana dashboards, Loki logs, MLflow/Langfuse traces), zero-trust proxy controls, and enterprise skills — across up to 100 concurrent users on 2 OpenShift clusters, managed by a session broker at `yougetaclaw.com`.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| `oc` CLI | Logged in as cluster-admin (`oc whoami` should show admin user) |
| `.env` file | Copy `../.env.example` to `../.env` and populate: OpenRouter key, Langfuse keys, AWS credentials, broker config |
| claw-operator repo | Cloned at `../../claw-operator` (relative to `clawoperator-openclaw/`) |
| AWS credentials | For Loki S3 bucket and broker S3 uploads. Run `aws login` before steps that need it |
| `qrencode` | For QR code generation in `demo-urls.sh` (`brew install qrencode`) |
| `helm` | For deploying FantaCo backend charts |
| `podman` | For container builds (if rebuilding images). Always use `--platform linux/amd64` |

---

## Fresh Cluster Setup

Run these steps in order from the `clawoperator-openclaw/` directory. Replace `1 50` with your namespace range (e.g. `1 20` for 20 users).

### Step 1: Operator + RBAC

```bash
./0-admin-setup.sh 1 50
```

Installs the claw-operator, enables User Workload Monitoring, creates the ClusterRole, and grants RBAC to all student namespaces.

### Step 2: Centralized logging (Loki)

```bash
./deploy-logs-loki.sh
```

Deploys Loki Operator + Cluster Logging Operator with S3 backend. Creates an S3 bucket, IAM user, and LokiStack CR. State saved to `.state/logging.env`.

### Step 3: Grafana dashboards

```bash
./deploy-dashboards-grafana.sh
```

Deploys Grafana Operator with Prometheus and Loki data sources for unified observability.

### Step 4: MLflow traces

```bash
./deploy-traces-mlflow.sh
```

Deploys MLflow with PostgreSQL backend for OTEL trace collection. Sets `MLFLOW_SERVER_DISABLE_SECURITY_MIDDLEWARE=true` to avoid TLS-terminating proxy conflicts.

### Step 5: Langfuse traces

```bash
./deploy-traces-langfuse.sh
```

Deploys Langfuse for LLM observability. Populates `.state/langfuse.env` with public/secret keys (used by audience-reset.sh).

### Step 6: Audience reset (the big one)

```bash
./audience-reset.sh 1 50
```

This is the core deployment step. See [What audience-reset.sh Does](#what-audience-resetsh-does-to-each-instance) below for full details.

### Step 7: Resource quotas

```bash
./set-namespace-quotas.sh 1 50
```

Applies ResourceQuotas per namespace: 3 cores request, 4Gi memory request, 8 cores limit, 10Gi memory limit, 16 pods max.

### Step 8: Publish to broker

**Option A — OCP broker** (recommended, no AWS needed):

```bash
./deploy-broker-ocp.sh               # One-time: build + deploy broker on OpenShift
./update-broker-ocp.sh --rotate-status-key
```

**Option B — S3 broker** (yougetaclaw.com, requires AWS):

```bash
aws login
./update-broker.sh --rotate-status-key
```

Discovers audience routes from the cluster, builds `routes.csv`, injects into the broker (OCP) or uploads to S3, and prints the share URL.

### Step 9: Preflight + URLs

```bash
./demo-preflight.sh 1 50
./demo-urls.sh
```

`demo-preflight.sh` runs pass/fail health checks across all namespaces (pod status, Claw CR conditions, gateway config, network policies, URL reachability). `demo-urls.sh` prints all stage-ready URLs and a QR code.

### Step 10: Disable heartbeat

```bash
./manage-heartbeat.sh disable
```

Disables the OpenClaw heartbeat to stop idle LLM token consumption.

---

## Subsequent Demo Reset

Before each subsequent demo, run these commands to wipe all user state (chats, memory, skills, cron), generate new audience URLs, and re-inject everything:

```bash
# Reset (no AWS needed)
./audience-reset.sh 1 50

# Publish to broker
./update-broker-ocp.sh --rotate-status-key   # OCP broker (no AWS needed)
# Or: aws login && ./update-broker.sh --rotate-status-key   # S3 broker

# Verify
./demo-preflight.sh 1 50
./demo-urls.sh
```

No need to re-run Steps 1–5 or 7 — those are one-time cluster setup.

---

## What audience-reset.sh Does to Each Instance

This is the core script. It transforms a vanilla OpenClaw instance into a fully configured FantaCo enterprise demo environment. Here is every customization it applies:

### Phase 0: Ensure Claw Instances Exist

- Creates Claw CR in each namespace if missing
- Creates K8s Secrets for LLM provider API keys (based on `LLM_PROVIDER` in `.env`)
- Creates `claw-password` Secret for UI authentication
- Creates `langfuse-auth` Secret with Base64-encoded Basic Auth credentials
- Waits for gateway pods to reach Running state

### Phase 1: Per-Namespace Reset (parallel, up to 5 concurrent)

**State wipe:**
- Deletes the previous `audience` Route (old URL dies immediately)
- Wipes user state from PVC: chat sessions, memory, cron jobs, identity files, intermediate data

**FantaCo backend deployment** (via Helm charts):
- 3 PostgreSQL databases (customer, product, sales-order)
- 3 REST API applications (customer-service, product-service, sales-order-service)
- 3 MCP servers (customer:9001, product:9003, sales-order:9004)
- Routes and Services for each component
- Total: 9 pods per namespace

**New audience Route:**
- Creates a new `audience` Route with a unique random hostname
- Saves the audience code to `.state/<cluster-guid>/broker.env`

**Langfuse injection:**
- Injects OTEL auth headers into MCP server deployments (if Langfuse deployed)
- Sets Langfuse env vars on gateway, removes raw keys (proxy injects them via Secret)
- Triggers deployment rollout

### Phase 2: MCP Endpoint Registration + Network Policies

**MCP servers registered in Claw CR** (`spec.mcpServers`):

| Server | URL | Transport | Tools |
|--------|-----|-----------|-------|
| customer | `http://mcp-customer-service:9001/mcp` | streamable-http | `search_customers`, `get_customer`, `get_customer_contacts`, `get_customer_projects` |
| product | `http://mcp-product-service:9003/mcp` | streamable-http | `search_products`, `get_product`, `list_themes` |
| sales-order | `http://mcp-sales-order-service:9004/mcp` | streamable-http | `search_orders`, `get_order` |

**NetworkPolicies created:**

| Policy | Direction | Purpose |
|--------|-----------|---------|
| `allow-proxy-to-mcp` | Proxy → MCP services (ports 9001, 9003, 9004) | Allow proxy to reach MCP servers |
| `allow-instance-to-mlflow` | Gateway → MLflow namespace (port 5000) | Allow OTEL trace export (if MLflow deployed) |
| `allow-prometheus-scrape` | Monitoring namespace → Gateway | Allow Prometheus metrics collection |

**ServiceMonitor created:**
- `openclaw-gateway` — Prometheus scrape config (30s interval, `/api/diagnostics/prometheus` endpoint, Bearer token auth)

### Phase 3: Plugin Installation + Config Patching

**Plugins installed:**

| Plugin | Version | Condition |
|--------|---------|-----------|
| `@openclaw/diagnostics-prometheus` | `2026.5.26` | Always |
| `@openclaw/diagnostics-otel` | `2026.5.26` | If MLflow deployed |
| `langfuse-tracer` (custom) | Local files | If Langfuse deployed + keys in .env |

**Config patches applied** (via `post-restart-repatch.sh`):

| Config Path | Value |
|------------|-------|
| `gateway.controlUi.allowedOrigins` | Audience route URL + broker domain |
| `agents.defaults.model.primary` | LLM model from .env (e.g. `openai/moonshotai/kimi-k2.6`) |
| `models.providers.*` | Provider-specific config (base URL, context window, token limits) |
| `diagnostics.enabled` | `true` |
| `diagnostics.otel` | Full OTEL config (endpoint, headers, sample rate, content capture) |
| `plugins.bundledDiscovery` | `"compat"` |
| `plugins.entries["diagnostics-prometheus"]` | `{enabled: true}` |
| `plugins.entries["diagnostics-otel"]` | `{enabled: true, hooks: {allowConversationAccess: true}}` |
| `plugins.entries["langfuse-tracer"]` | `{enabled: true, hooks: {allowConversationAccess: true}}` |

**Important:** `allowConversationAccess: true` is required for non-bundled plugins to access conversation hooks. Without it, only heartbeat traces appear.

### Phase 4: Enterprise Persona + Skill Injection

**Workspace files injected** (to `/home/node/.openclaw/workspace/` on the gateway pod):

| File | Source | Purpose |
|------|--------|---------|
| `IDENTITY.md` | `workspace-templates/IDENTITY.md` | Pre-filled identity (skips bootstrap questionnaire) |
| `AGENTS.md` (appended) | `workspace-templates/AGENTS.md.append` | Enterprise assistant instructions for FantaCo |
| `TOOLS.md` | `workspace-templates/TOOLS.md` | Documentation of available MCP tools |
| `skills/quote-builder/SKILL.md` | `claw_skills/quote-builder/SKILL.md` | Enterprise quote-builder skill |

### Environment Variables Set on Gateway

| Variable | Value |
|----------|-------|
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | `http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces` |
| `OTEL_EXPORTER_OTLP_TRACES_HEADERS` | `x-mlflow-experiment-id={ID}` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` |
| `OTEL_SERVICE_NAME` | `openclaw-{namespace}` |
| `OTEL_RESOURCE_ATTRIBUTES` | `openclaw.namespace={namespace}` |
| `OTEL_SEMCONV_STABILITY_OPT_IN` | `gen_ai_latest_experimental` |
| `LANGFUSE_BASE_URL` | Langfuse route URL |
| `LANGFUSE_TRACE_URL` | Instance's public audience URL |

### Trace Backend Reset

- **MLflow:** Deletes all traces via `POST /api/2.0/mlflow/traces/delete-traces`
- **Langfuse:** Clears traces via ClickHouse SQL (`ALTER TABLE traces/observations/scores DELETE WHERE 1=1`)
- **Prometheus:** Deletes pods (emptyDir wiped on recreate), re-creates Grafana dashboard

---

## Multi-Cluster Setup

To scale beyond one cluster:

1. **Set up each cluster independently** using the Fresh Cluster Setup steps above

2. **Create `clusters.csv`** (one line per cluster):
   ```csv
   ql7rg,/Users/bsutter/.kube/config-cluster-ql7rg
   w6hwm,/Users/bsutter/.kube/config-cluster-w6hwm
   ```

3. **Run audience-reset on each cluster:**
   ```bash
   KUBECONFIG=~/.kube/config-cluster-ql7rg ./audience-reset.sh 1 50
   KUBECONFIG=~/.kube/config-cluster-w6hwm ./audience-reset.sh 1 50
   ```

4. **Publish merged routes:**
   ```bash
   aws login
   ./update-broker.sh --rotate-status-key
   ```
   `update-broker.sh` auto-detects `clusters.csv`, discovers routes from all clusters, merges into a single `routes.csv`, and uploads to S3.

5. **Verify each cluster:**
   ```bash
   KUBECONFIG=~/.kube/config-cluster-ql7rg ./demo-preflight.sh 1 50
   KUBECONFIG=~/.kube/config-cluster-w6hwm ./demo-preflight.sh 1 50
   ./demo-urls.sh
   ```

If `clusters.csv` is absent, `update-broker.sh` falls back to single-cluster mode using the current `oc` context.

---

## Day-of-Demo Checklist

```
[ ] aws login                              # Root sessions expire after 1 hour
[ ] demo-preflight.sh passes all checks    # Run against each cluster
[ ] demo-urls.sh shows correct URLs        # Audience URL, status board, QR code
[ ] manage-heartbeat.sh disable            # Stop idle LLM token consumption
[ ] Test one instance end-to-end           # Open audience URL, send a prompt, verify MCP tools work
[ ] Grafana dashboard loads                # Check metrics are flowing
[ ] Langfuse UI shows traces               # Verify trace pipeline is working
[ ] Browser tabs ready                     # Status board, Grafana, Langfuse (hide status key tab from audience)
[ ] OpenRouter credit balance checked      # source .env && curl -s https://openrouter.ai/api/v1/auth/key -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

---

## Proxy Allowlist Demo Flow

Demonstrates the zero-trust network boundary:

1. **Prompt:** `Show me the NASA Astronomy Picture of the Day` → agent fails (proxy blocks `apod.nasa.gov`)
2. **Review:** `./review-blocked-requests.sh 5m` → see the blocked domain in Loki logs
3. **Allow:** `./manage-proxy-allowlist.sh allow apod.nasa.gov` → proxy config updated (~10 sec)
4. **Re-prompt:** same prompt → succeeds

See `test_prompts.md` for full demo script and alternative prompts.

---

## Key Scripts Reference

| Script | Purpose |
|--------|---------|
| `0-admin-setup.sh` | Install claw-operator, enable User Workload Monitoring, RBAC |
| `audience-reset.sh` | Full demo reset: deploy instances, backends, MCP, plugins, skills, URLs |
| `demo-preflight.sh` | Pass/fail health checks across all namespaces |
| `demo-urls.sh` | Print stage-ready URLs and QR code |
| `deploy-broker-ocp.sh` | One-time: build + deploy session broker on OpenShift (no AWS needed) |
| `update-broker-ocp.sh` | Inject routes into OCP broker, print share URL |
| `update-broker.sh` | Upload routes to S3 broker at yougetaclaw.com (requires AWS) |
| `deploy-logs-loki.sh` | Deploy Loki + Cluster Logging (S3 backend) |
| `deploy-dashboards-grafana.sh` | Deploy Grafana with Prometheus + Loki data sources |
| `deploy-traces-mlflow.sh` | Deploy MLflow for OTEL trace collection |
| `deploy-traces-langfuse.sh` | Deploy Langfuse for LLM observability |
| `set-namespace-quotas.sh` | Apply ResourceQuotas per namespace |
| `manage-heartbeat.sh` | Enable/disable OpenClaw heartbeat |
| `manage-proxy-allowlist.sh` | Add/remove/list domains in proxy allowlist |
| `review-blocked-requests.sh` | Query Loki for blocked proxy requests |
| `post-restart-repatch.sh` | Re-apply config patches after pod restart |
| `switch-provider.sh` | Hot-swap LLM provider without restarts |
| `rotate-api-key.sh` | Rotate OpenRouter API key across all clusters |
| `extend-cluster.sh` | Add more agentic-user namespaces to a cluster |
| `extract-langfuse-traces.sh` | Export user chat traces from Langfuse |
| `lookup-route.sh` | Resolve broker URL to cluster + namespace |
| `soft-reset-user-state.sh` | Reset chat state without touching routes or config |
| `monitor-pods.sh` | Live pod monitor across all namespaces |

---

## Key Files

| File | Purpose |
|------|---------|
| `../.env` | AWS keys, LLM provider keys, Langfuse keys, broker config |
| `clusters.csv` | Multi-cluster config (copy from `clusters.csv.example`) |
| `.state/langfuse.env` | Auto-populated by `deploy-traces-langfuse.sh` |
| `.state/logging.env` | Auto-populated by `deploy-logs-loki.sh` |
| `.state/<guid>/broker.env` | Per-cluster broker state (audience code, status key) |
| `workspace-templates/` | IDENTITY.md, AGENTS.md.append, TOOLS.md templates |
| `claw_skills/quote-builder/` | Enterprise skill injected into every instance |
| `claw_plugins/langfuse-tracer/` | Custom Langfuse plugin (injected by audience-reset.sh) |
| `test_prompts.md` | Demo prompts with expected behaviors |

---

## Gotchas

- **Post-restart config wipe:** `oc rollout restart` re-seeds `openclaw.json` from the operator, wiping JSON patches. Use `post-restart-repatch.sh` to re-apply, or use `kill 1` inside the container to restart without re-seeding.
- **API key security:** OpenRouter keys use placeholder `proxy-managed-credential` in gateway config. The proxy injects the real key from K8s Secrets. Never write raw keys to `openclaw.json`.
- **Container architecture:** Always build with `--platform linux/amd64` when targeting OpenShift (amd64 nodes). Apple Silicon builds cause `exec format error`.
- **AWS session timeout:** Root sessions expire after 1 hour. Run `aws login` immediately before S3 broker operations. The OCP broker (`deploy-broker-ocp.sh` / `update-broker-ocp.sh`) avoids this entirely.
- **Skill injection timing:** Skills must be injected AFTER the final restart (Phase 4), because restarts wipe PVC state.
- **NO_PROXY bypass:** MCP services and MLflow use internal cluster URLs (`*.svc.cluster.local`) to bypass the proxy allowlist.
