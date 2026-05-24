# Claw-Operator Deployment Scripts

Automate deployment of OpenClaw instances via the claw-operator for Red Hat Summit demo namespaces.

## Prerequisites

- `oc login` as cluster-admin (for admin setup) or as student user (for verification)
- `../.env` populated with credentials (copy from `../.env.example`)
- claw-operator repo available locally (default: `../../claw-operator`)

## Step 0: Admin Setup (one-time)

Install the claw-operator, create RBAC, and grant access to student namespaces:

```bash
# For agentic-user2 through agentic-user5
./0-admin-setup.sh 2 5

# Just agentic-user3
./0-admin-setup.sh 3
```

This script:
1. Installs the claw-operator (if not already running) via `make dev-deploy`
2. Patches memory limits to prevent OOMKilled (512Mi limit / 128Mi request)
3. Creates the `claw-user` ClusterRole
4. Grants `claw-user` role to each student user in their namespace

## Step 1: Deploy Claw Instances

Create secrets and Claw CRs in each namespace:

```bash
# Deploy to agentic-user2 through agentic-user5
./1-deploy-claw.sh 2 5

# Just agentic-user3
./1-deploy-claw.sh 3
```

This script:
1. Sources `../.env` for API keys and passwords
2. Creates the API key secret (provider-specific)
3. Creates the password secret (`claw-password`)
4. Applies the Claw CR with password auth enabled
5. Waits for all 3 pods per namespace (up to 120s)
6. Prints the URL for each instance

## Step 2: Check Health

Run the automated health check across namespaces:

```bash
# Check agentic-user2 through agentic-user5
./2-openclaw-status.sh 2 5

# Just agentic-user3
./2-openclaw-status.sh 3
```

This script checks:
1. Claw-operator pod is running
2. All 3 instance pods (instance, instance-proxy, instance-device-pairing) are Running
3. Claw CR status conditions
4. Gateway logs for errors
5. URL is reachable (HTTP 200/302)

## Step 3: Open in Browser

Open the OpenClaw UI for one or more namespaces:

```bash
# Open agentic-user2 through agentic-user5
./3-open-openclaw.sh 2 5

# Just agentic-user3
./3-open-openclaw.sh 3
```

Gets the URL from the Claw CR status and opens it in the default browser. Students enter the password when prompted.

## Provider Selection

Set `LLM_PROVIDER` env var before running `1-deploy-claw.sh`:

| Provider | `LLM_PROVIDER` | Env vars needed | Auth type |
|----------|----------------|-----------------|-----------|
| LiteLLM (default) | `litellm` | `LLM_API_KEY`, `LLM_API_BASE_URL` | bearer |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` | apiKey |
| OpenAI | `openai` | `OPENAI_API_KEY` | apiKey |
| GCP Vertex AI | `gcp` | `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`, `GEMINI_MODEL` | gcp (SA key) |

Example:
```bash
LLM_PROVIDER=anthropic ./1-deploy-claw.sh 2 5
```

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

3. Deploy: `./1-deploy-claw.sh`

The operator creates a proxy sidecar that handles OAuth2 token refresh — the gateway pod never sees real GCP credentials. See the [provider setup docs](https://github.com/codeready-toolchain/claw-operator/blob/master/docs/provider-setup.md) for details.

## Cluster Login Helper

Log in as a student user or admin without remembering the API server URL:

```bash
# Log in as user3
./cluster-login.sh 3

# Log in as admin
./cluster-login.sh admin
```

Sources `../.env` for credentials and derives the API server URL from `OPENSHIFT_CONSOLE_URL`.

## Reset to Fresh State

Wipe all user state (chat sessions, memory, cron jobs, custom skills, config) and restart the gateway so it behaves like a fresh install:

```bash
# Reset agentic-user2 through agentic-user5
./reset-openclaw.sh 2 5

# Just agentic-user3
./reset-openclaw.sh 3

# Reset current namespace (student mode)
./reset-openclaw.sh
```

This script:
1. Wipes all user state from the gateway PVC (sessions, agent DBs, memory, cron, custom skills, config)
2. Preserves the PVC, operator ConfigMap, secrets, and the `platform/` skill
3. Restarts the deployment so the gateway re-initializes from the operator ConfigMap
4. Re-patches the model config from `../.env` (if `GEMINI_MODEL` or `LLM_MODEL_NAME` is set)
5. Waits for rollout to complete

After reset, the gateway has empty chats, no custom skills, no cron jobs, and no agent memory.

## Cleanup

Remove Claw CR and secrets from student namespaces (preserves operator and ClusterRole):

```bash
# Clean agentic-user2 through agentic-user5
./clean-namespace.sh 2 5

# Just agentic-user3
./clean-namespace.sh 3
```

This script:
1. Deletes the Claw CR (triggers operator cleanup of deployments/services/routes)
2. Waits for pods to terminate (up to 120s)
3. Deletes secrets (litellm-api-key, anthropic-api-key, openai-api-key, gcp-service-account, claw-password)

To uninstall the operator itself:
```bash
cd ../../claw-operator
make undeploy
```

## Audience Reset (Demo Mode)

Reset all instances for the next audience with **new unique, non-guessable URLs**:

```bash
# Reset user1 through user5
./audience-reset.sh 1 5

# Just user3
./audience-reset.sh 3
```

This script:
1. Generates a **unique random hostname** per user (e.g. `claw-a3kx7f.apps.<cluster>`)
2. Deletes the previous audience Route (old URL stops working immediately)
3. Wipes all user state (chats, memory, cron, custom skills, config)
4. Creates a new audience Route with the random hostname
5. Patches `allowedOrigins` so the gateway accepts the new URL
6. Restarts the gateway and re-patches model config
7. Prints the new URLs to share with the audience

Each URL is fully independent — knowing one URL reveals nothing about the others (no `user1`/`user2` pattern). The admin Route (`instance-agentic-userN.apps...`) stays intact for admin use.

**Requires admin login** — student users don't have Route create/delete permissions.

## Deploy FantaCo Backends

Deploy the FantaCo customer backend (database, REST API, MCP server) across student namespaces:

```bash
# Deploy to current namespace (student mode)
./deploy-fantaco-backends.sh

# Deploy to agentic-user2 through agentic-user5
./deploy-fantaco-backends.sh 2 5

# Just agentic-user3
./deploy-fantaco-backends.sh 3
```

This script renders customer-only templates from the `fantaco-app` and `fantaco-mcp` Helm charts and applies them with `oc apply`. Deploys 3 pods per namespace:
1. `postgresql-customer` — PostgreSQL database
2. `fantaco-customer-main` — Spring Boot REST API (port 8081)
3. `mcp-customer` — MCP server (port 9001)

Includes pod readiness waiting, smoke tests (`/actuator/health/liveness`), and route display.

**Note:** Uses `oc apply` so it is idempotent — safe to run on namespaces that already have these resources.

## Inject Customer MCP into Gateway

After deploying the FantaCo backends, register the customer MCP server in the OpenClaw gateway config:

```bash
# Inject into agentic-user2 through agentic-user5
./inject-mcp-customer.sh 2 5

# Just agentic-user3
./inject-mcp-customer.sh 3

# Inject into current namespace (student mode)
./inject-mcp-customer.sh
```

This script:
1. Verifies the Claw CR and `mcp-customer-service` exist
2. Patches the Claw CR with `spec.mcpServers.customer` — the operator handles proxy config, gateway config, and deployment rollouts automatically
3. Creates a supplemental NetworkPolicy (`allow-proxy-to-mcp`) so the proxy can reach the MCP service on port 9001 (the operator's default egress only allows port 443)
4. Waits for gateway and proxy rollouts to complete
5. Verifies connectivity from the gateway pod through the proxy to the MCP service

The MCP entry added to the Claw CR:
```json
{
  "mcp": {
    "servers": {
      "customer": {
        "transport": "streamable-http",
        "url": "http://mcp-customer-service:9001/mcp"
      }
    }
  }
}
```

**Prerequisite:** Run `deploy-fantaco-backends.sh` first to deploy the MCP service.

## Demo Preflight Check

Run a comprehensive pre-demo verification that catches configuration drift, operator reconciliation side-effects, and pod restarts — before the audience sees them:

```bash
# Check user1 through user5
./demo-preflight.sh 1 5

# Just user3
./demo-preflight.sh 3
```

This script checks 15 things per namespace:

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

Reads `openclaw.json` via a single `oc exec` per namespace (not multiple) for speed. Sources `../.env` to determine the expected model. Color-coded output: green for pass, red for fail. Exits non-zero if any check fails.

**Run this after `audience-reset.sh` and before presenting.**

## Prometheus Metrics

Enable Prometheus scraping of OpenClaw gateway diagnostics (model calls, tokens, costs, sessions):

```bash
# Enable for user1 through user5
./enable-prometheus.sh 1 5

# Just user3
./enable-prometheus.sh 3
```

This script:
1. Installs the `diagnostics-prometheus` plugin via npm inside the gateway pod
2. Patches `openclaw.json` to enable `diagnostics` and the plugin
3. Creates a `NetworkPolicy` allowing Prometheus to reach port 18789
4. Creates a `ServiceMonitor` CR for auto-discovery by User Workload Monitoring
5. Restarts the gateway to load the plugin

The `reset-openclaw.sh` script automatically re-installs the plugin and re-patches diagnostics config if a `ServiceMonitor` exists in the namespace.

**Prerequisites:**
- User Workload Monitoring enabled on the cluster (the script does NOT enable this — it's a one-time cluster-admin step: set `enableUserWorkload: true` in `openshift-monitoring/cluster-monitoring-config`)
- OpenClaw instances already deployed

**Verify:**
```bash
# Check metrics endpoint
PASS=$(oc get secret claw-password -n agentic-user1 -o jsonpath='{.data.password}' | base64 -d)
oc exec deployment/instance -n agentic-user1 -c gateway -- \
  curl -s -H "Authorization: Bearer $PASS" \
  http://localhost:18789/api/diagnostics/prometheus | head -20

# Check Prometheus targets
oc get servicemonitor -n agentic-user1

# In OpenShift Console -> Observe -> Metrics, query:
#   openclaw_model_call_total
#   sum by (model) (increase(openclaw_model_cost_usd_total[1h]))
```

### Key Learnings

- **`gateway.token` is invalid with password auth.** The gateway config schema rejects `gateway.token` when `gateway.auth.mode` is `password`. Setting it crashes the pod on startup (`gateway: Invalid input`). Use the existing `claw-password` secret as a Bearer token instead — the gateway accepts the password in `Authorization: Bearer` headers for operator-scope API routes.
- **The plugin must be npm-installed**, not just config-enabled. Adding `diagnostics-prometheus` to `plugins.allow` and `plugins.entries` without installing the package results in "0 plugins" at startup. Install with: `openclaw plugins install @openclaw/diagnostics-prometheus` (runs inside the pod).
- **Use npm, not ClawHub, for the current runtime.** The ClawHub version may require a newer plugin API than the deployed runtime exposes (e.g., ClawHub requires `>=2026.5.22` but runtime is `2026.5.20`). The npm package works because it matches the bundled version.
- **A NetworkPolicy is required for Prometheus.** The operator's default `instance-ingress` NetworkPolicy only allows ingress from OpenShift ingress/host-network namespaces. Prometheus in `openshift-user-workload-monitoring` needs a separate policy targeting `network.openshift.io/policy-group: monitoring`.

## Centralized Logging (Loki)

Centralized log aggregation across all namespaces via the OpenShift Console's **Observe → Logs** tab.

**Components deployed:**
- **Loki Operator** (`openshift-operators-redhat`) — manages the LokiStack log storage backend
- **Cluster Logging Operator** (`openshift-logging`) — manages log collection and forwarding
- **Vector** (DaemonSet) — collects container logs from every node
- **LokiStack** (`1x.extra-small`) — stores logs in S3, 3-day retention

**Log flow:**
```
container stdout → Vector (DaemonSet on each node) → LokiStack → OpenShift Console
```

**Setup:**
```bash
./scripts/deploy-logs-loki.sh
```

The script creates:
1. An S3 bucket (`openclaw-loki-<cluster-suffix>`) in `us-east-2` for log storage
2. An IAM user (`openclaw-loki-s3`) with scoped S3 access
3. Both operators via OperatorHub subscriptions (`stable-6.2` channel)
4. A `ClusterLogForwarder` that collects application + infrastructure logs

AWS credentials and bucket info are saved to `scripts/.state/logging.env` for teardown/reuse.

**Access logs:**
- OpenShift Console → **Observe → Logs**
- Filter by namespace (`agentic-user1`, `agentic-user2`, etc.)
- Filter by pod name (`gateway`, `instance-proxy`, etc.)
- Search log content with LogQL queries

**Verify:**
```bash
# All pods in openshift-logging
oc get pods -n openshift-logging

# LokiStack status
oc get lokistack -n openshift-logging

# ClusterLogForwarder status
oc get clusterlogforwarder -n openshift-logging

# Collector DaemonSet
oc get daemonset -n openshift-logging -l component=collector
```

## Grafana Dashboard

A pre-built **OpenClaw Admin Overview** dashboard is deployed automatically by the Grafana script:

```bash
./scripts/deploy-dashboards-grafana.sh
```

The dashboard provides a single-pane view across all 5 OpenClaw instances (`agentic-user1` through `agentic-user5`):

| Row | Panels | What it shows |
|-----|--------|---------------|
| Overview | 5 stat panels | Total model calls, cost (USD), agent runs, tool executions, tokens |
| Cost & Tokens | 4 time series | Cost over time by user, cumulative cost, input vs output tokens, cache reads |
| Model Performance | 3 panels | Call rate per user, p50/p95 latency, outcome breakdown (pie) |
| Agent Runs | 3 panels | Runs over time by user, p50/p95 duration, channel breakdown (pie) |
| Tool Usage | 3 panels | Executions by tool (bar), execution rate, p95 duration by tool |
| Per-User Summary | 1 table | One row per namespace: model calls, cost, tokens, runs, tool calls |

**Access:** Open Grafana URL → Dashboards → **OpenClaw Admin Overview**

**Verify:**
```bash
oc get grafanadashboard -n grafana
```

**Prerequisites:** Prometheus metrics enabled (`./enable-prometheus.sh 1 5`) and Grafana deployed.

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

## Test Network Policy Enforcement

Interactive demo (like `7-demo-sandbox-security.sh` for OpenShell) that shows the claw-operator's two-layer security model in action:

```bash
# Test current namespace
./test-network-policy.sh

# Test agentic-user3
./test-network-policy.sh 3
```

**Phase 1 — Architecture:** Shows the NetworkPolicies, proxy config allowlist, and explains the L4 + L7 security layers.

**Phase 2 — Test prompts:** Prints 5 prompts to type into the OpenClaw UI:

| # | Prompt | Expected | Why |
|---|--------|----------|-----|
| 1 | Fetch `api.github.com/zen` | ALLOWED | GitHub is a passthrough domain |
| 2 | Search customers with "coffee" | ALLOWED | MCP via supplemental NetworkPolicy |
| 3 | Fetch `example.com` | BLOCKED (403) | Not in proxy allowlist |
| 4 | Fetch `api.nasa.gov` APOD | BLOCKED (403) | Not in proxy allowlist |
| 5 | POST to `evil.com/upload` | BLOCKED (403) | Data exfiltration denied |

**Phase 3 — Audit trail:** Shows proxy logs with allow/deny entries.

**Phase 4 — Summary:** Recap of what was demonstrated.

### Automated Playwright Test

The `/fantaco:test-openclaw-network-policy` skill runs the same 5 prompts via Playwright, verifying pass/fail automatically:

```bash
# Run via Claude Code skill
/fantaco:test-openclaw-network-policy 3
```

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
