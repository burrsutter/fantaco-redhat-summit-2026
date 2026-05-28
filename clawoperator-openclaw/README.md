# OpenClaw Demo Setup

Scripts to deploy and reset OpenClaw instances for the FantaCo demo at Red Hat Summit 2026. Each audience member gets an isolated namespace with a unique, non-guessable URL.

**Full walkthrough:** [QUICKSTART.md](QUICKSTART.md)

## What Gets Customized

`audience-reset.sh` transforms a vanilla OpenClaw instance into a FantaCo demo environment. Here's everything it changes:

### FantaCo Backend Services (9 pods per namespace)

Each namespace gets three business data stacks deployed via Helm:

| Service | Components | MCP Port |
|---------|-----------|----------|
| **Customer** | PostgreSQL + REST API + MCP server | 9001 |
| **Product** | PostgreSQL + REST API + MCP server | 9003 |
| **Sales Order** | PostgreSQL + REST API + MCP server | 9004 |

The MCP servers are registered in the Claw CR using `streamable-http` transport and internal service URLs.

### Workspace Files

| File | Change |
|------|--------|
| `IDENTITY.md` | Pre-filled (octopus persona) to skip the onboarding questionnaire |
| `AGENTS.md` | Appended with FantaCo enterprise assistant instructions and proactive MCP tool usage |
| `TOOLS.md` | Replaced with a FantaCo-specific MCP tool reference guide |

### Enterprise Skill

**quote-builder** (`/quote_builder <customer>, <theme>`) — looks up customer data, searches products by theme, builds a priced quote table, and creates a project on approval.

### Plugins (2-3 per namespace)

| Plugin | Purpose |
|--------|---------|
| `diagnostics-prometheus` | Exposes Prometheus metrics endpoint |
| `diagnostics-otel` | Exports OTEL traces to MLflow (if deployed) |
| `langfuse-tracer` | Sends per-turn prompt/response traces to Langfuse (if deployed) |

### Gateway Config Patches (`openclaw.json`)

Applied after every restart via `post-restart-repatch.sh`:

- **allowedOrigins** — audience route host + broker domain
- **Primary model** — from `.env` (GCP, OpenRouter, LiteLLM, etc.)
- **diagnostics.otel** — OTEL tracing with `captureContent` enabled
- **Plugin entries** — each plugin enabled with `allowConversationAccess: true`

### Environment Variables (up to 11 per namespace)

Set on the gateway deployment via `oc set env`:

- 7 OTEL vars (endpoint, headers, protocol, service name, resource attributes, semconv)
- 4 Langfuse vars (public key, secret key, base URL, trace URL)

### Network Policies (up to 5 per namespace)

| Policy | Direction | Purpose |
|--------|-----------|---------|
| `allow-proxy-to-mcp` | Egress | Proxy pod to MCP service ports |
| `allow-instance-to-mlflow` | Egress | Gateway to MLflow (port 5000) |
| `allow-instance-to-langfuse` | Egress | Gateway to Langfuse (port 3000) |
| `allow-prometheus-scrape` | Ingress | Prometheus to gateway metrics (port 18789) |
| ServiceMonitor | — | Prometheus auto-discovery with Bearer auth |

### Observability Resets

After all namespaces are configured, the script cleans up stale data:

- **Prometheus** — deletes user-workload pods (emptyDir wipe)
- **Grafana** — deletes and re-creates the admin dashboard
- **MLflow** — bulk-deletes all traces from the `openclaw-traces` experiment
- **Langfuse** — truncates traces/observations/scores via ClickHouse

## Scripts

### Primary Workflow

| Script | Purpose |
|--------|---------|
| `0-admin-setup.sh [start] [end]` | One-time cluster setup: install operator, RBAC, student access |
| `audience-reset.sh [start] [end]` | Full demo reset: wipe state, deploy backends, configure everything |
| `update-broker.sh` | Publish audience routes to the Route-LB broker at yougetaclaw.com |
| `demo-preflight.sh [start] [end]` | 15-point pre-demo verification per namespace |

### Observability (one-time)

| Script | Purpose |
|--------|---------|
| `deploy-logs-loki.sh` | Loki + Cluster Logging for centralized logs |
| `deploy-traces-mlflow.sh` | MLflow for OTEL trace visualization |
| `deploy-traces-langfuse.sh` | Langfuse for rich prompt/response tracing |
| `deploy-dashboards-grafana.sh` | Grafana dashboard for metrics overview |

### Utilities

| Script | Purpose |
|--------|---------|
| `post-restart-repatch.sh <ns>` | Re-apply all config patches after a gateway restart |
| `switch-provider.sh <provider>` | Hot-swap LLM provider across running pods (~30s) |
| `reset-openclaw.sh [start] [end]` | Wipe user state and restart (without redeploying backends) |
| `monitor-pods.sh` | Live pod status display across all namespaces |
| `demo-preflight.sh [start] [end]` | Pre-demo health checks |

## Provider Selection

Set `LLM_PROVIDER` in `../.env`:

| Provider | `LLM_PROVIDER` | Key env vars |
|----------|----------------|-------------|
| GCP Vertex AI | `gcp` | `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`, `GEMINI_MODEL` |
| OpenRouter | `openrouter` | `OPENROUTER_API_KEY`, `OPENROUTER_MODEL` |
| LiteLLM | `litellm` | `LLM_API_KEY`, `LLM_API_BASE_URL`, `LLM_MODEL_NAME` |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` |
| OpenAI | `openai` | `OPENAI_API_KEY` |

Hot-swap without a full reset: `./switch-provider.sh openrouter`

## Key Gotcha

Every `oc rollout restart` causes the operator to re-seed `openclaw.json`, wiping custom config. All scripts that restart the gateway call `post-restart-repatch.sh` automatically to re-apply patches.
