# Langfuse Integration — Implementation Notes

**Status:** IMPLEMENTED (2026-05-25)

**Commit:** `f26dc3a` — `feat: add langfuse-tracer plugin for rich trace input/output in Langfuse`

---

## The Problem

The built-in `diagnostics-otel` plugin sends OTEL spans to Langfuse, but Langfuse can't map OTEL span attributes to its native input/output fields. Result: traces show model name, token counts, and timing — but **no user prompt or model response text**. The trace list is full of noise (`openclaw.run`, `openclaw.harness.run`, `openclaw.model.usage`, `openclaw.liveness.warning`) with empty input/output columns.

## The Solution

Two separate trace pipelines, each going where it's most useful:

| Plugin | Target | What it sends | Why |
|--------|--------|---------------|-----|
| `langfuse-tracer` | Langfuse (REST API) | User prompt text + model response text | Langfuse's native input/output fields are populated |
| `diagnostics-otel` | MLflow (OTEL) | OTEL spans with token counts, timing, model info | MLflow handles OTEL spans well |
| `diagnostics-prometheus` | Prometheus/Grafana | Metrics (request counts, latencies) | Grafana dashboards |

The `langfuse-tracer` plugin (vendored from [MCKRUZ/openclaw-langfuse](https://github.com/MCKRUZ/openclaw-langfuse), pinned at commit `fb720a4`) talks to Langfuse's REST API directly — not OTEL. It captures:

- **Input:** User prompt text (up to 2K chars)
- **Output:** Model response text (up to 4K chars)
- **Trace name:** `openclaw-turn` (easy to filter in Langfuse UI)

---

## Architecture

```
OpenClaw Gateway Pod (3 plugins loaded)
├── langfuse-tracer          ──→  Langfuse REST API  (prompt/response text)
│     reads: LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_BASE_URL
│     endpoint: http://langfuse-web.langfuse.svc.cluster.local:3000
│
├── diagnostics-otel         ──→  MLflow OTEL        (spans, tokens, timing)
│     reads: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, OTEL_EXPORTER_OTLP_TRACES_HEADERS
│     endpoint: http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces
│
└── diagnostics-prometheus   ──→  Prometheus scrape   (metrics)
      exposes: /metrics on gateway service
```

Key design decision: `diagnostics-otel` **always targets MLflow**, never Langfuse. This eliminates the OTEL noise from Langfuse's trace list. The `langfuse-tracer` plugin handles Langfuse exclusively via REST API.

---

## Plugin Files

Vendored at: `claw_plugins/langfuse-tracer/`

```
claw_plugins/langfuse-tracer/
├── index.js                 # Plugin code (register function, event hooks)
├── openclaw.plugin.json     # Plugin manifest (id, name, version)
└── LICENSE                  # MIT license from upstream
```

Injected into pods at: `/home/node/.openclaw/extensions/langfuse-tracer/`

The `/extensions/` directory is **not wiped** by the state reset (wipe only touches sessions, agents, cron, memory, skills, config). So the plugin survives across resets.

### How the plugin works

`index.js` exports a `register(api)` function that:

1. Reads `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_BASE_URL` from `process.env`
2. Hooks into `before_agent_start` to capture the user's prompt text
3. Hooks into `after_agent_end` to capture the model's response text
4. POSTs a trace + generation to `${LANGFUSE_BASE_URL}/api/public/ingestion` using Basic auth
5. Populates Langfuse's native `input` and `output` fields with actual text content

### Plugin registration

The extensions directory is **NOT auto-discovered** by OpenClaw. The plugin must be explicitly registered in `openclaw.json`:

```json
{
  "plugins": {
    "allow": ["diagnostics-prometheus", "diagnostics-otel", "langfuse-tracer"],
    "entries": {
      "langfuse-tracer": {
        "enabled": true,
        "hooks": { "allowConversationAccess": true }
      }
    }
  }
}
```

`allowConversationAccess: true` is required because the plugin is non-bundled. Without it, the runtime silently blocks conversation hooks and the plugin only sees heartbeat events.

---

## Environment Variables

Set on the gateway deployment via `oc set env`:

| Variable | Value | Used by |
|----------|-------|---------|
| `LANGFUSE_PUBLIC_KEY` | From `.env` (set by `deploy-traces-langfuse.sh`) | langfuse-tracer |
| `LANGFUSE_SECRET_KEY` | From `.env` (set by `deploy-traces-langfuse.sh`) | langfuse-tracer |
| `LANGFUSE_BASE_URL` | `http://langfuse-web.langfuse.svc.cluster.local:3000` | langfuse-tracer |
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | `http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces` | diagnostics-otel |
| `OTEL_EXPORTER_OTLP_TRACES_HEADERS` | `x-mlflow-experiment-id=1` | diagnostics-otel |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `http/protobuf` | diagnostics-otel |
| `OTEL_SERVICE_NAME` | `openclaw-${NS}` | diagnostics-otel |
| `OTEL_SEMCONV_STABILITY_OPT_IN` | `gen_ai_latest_experimental` | diagnostics-otel |

The `LANGFUSE_*` env vars are only set when `OTEL_BACKEND == "Langfuse"` (i.e., Langfuse is deployed and keys are in `.env`).

The `OTEL_*` env vars always point at MLflow when MLflow is deployed, regardless of whether Langfuse is also present.

---

## Scripts Modified

### 1. `audience-reset.sh`

**Phase 4 — Trace backend detection (~line 785):**
- After detecting MLflow, saves `MLFLOW_OTEL_ENDPOINT` and `MLFLOW_OTEL_HEADERS`
- Langfuse detection sets `OTEL_BACKEND="Langfuse"` but does NOT overwrite `OTEL_ENDPOINT/HEADERS` (those stay pointed at MLflow)

**Phase 4 — Per-namespace OTEL config (~line 871):**
- When MLflow is available: installs `diagnostics-otel`, patches `openclaw.json`, sets OTEL env vars pointed at MLflow
- When Langfuse is active: sets `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_BASE_URL` env vars
- Both can run simultaneously (diagnostics-otel → MLflow, langfuse-tracer → Langfuse)

**Phase 5 — Post-restart re-install (~line 989):**
- Re-installs `diagnostics-otel` only when `MLFLOW_OTEL_ENDPOINT` is set (not gated on `OTEL_BACKEND`)

**Phase 6 — Plugin injection (~line 1086):**
- Copies `index.js` and `openclaw.plugin.json` from `claw_plugins/langfuse-tracer/` into each pod at `/home/node/.openclaw/extensions/langfuse-tracer/`
- Registers the plugin in `openclaw.json` (`plugins.allow` + `plugins.entries` with `allowConversationAccess: true`)
- Only runs when `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` are set and the plugin directory exists locally
- Uses the same `oc exec mkdir` + `oc cp` pattern as skill injection

### 2. `post-restart-repatch.sh`

Every `oc rollout restart` re-seeds `openclaw.json` from the operator ConfigMap, wiping plugin registrations.

- **OTEL detection (~line 103):** `OTEL_ENDPOINT` always points at MLflow. Langfuse detection no longer overwrites it.
- **Step 5 — diagnostics-otel config:** Only patches when `OTEL_ENDPOINT` is set (i.e., MLflow deployed)
- **Step 6 — langfuse-tracer registration:** If `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` are set AND `/home/node/.openclaw/extensions/langfuse-tracer/index.js` exists on disk, re-registers the plugin in `openclaw.json`

### 3. `deploy-traces-langfuse.sh`

- Added `ENABLE_EXPERIMENTAL_FEATURES=true` env var to both `langfuse-web` and `langfuse-worker` deployments
- Required for Langfuse's `/api/public/otel/v1/traces` OTEL ingestion endpoint to actually accept data (without it, the endpoint returns HTTP 200 but silently discards everything)

---

## NetworkPolicies

Both MLflow and Langfuse NetworkPolicies are applied when the respective backends are deployed:

```yaml
# allow-instance-to-langfuse (port 3000)
# allow-instance-to-mlflow (port 5000)
```

The gateway pod egresses through `instance-proxy:8080`, but internal service URLs (`*.svc.cluster.local`) bypass the proxy via `NO_PROXY`. The NetworkPolicies allow direct egress from gateway pods to the trace backend namespaces.

---

## Trace Cleanup

Langfuse doesn't have a bulk trace deletion API. The `audience-reset.sh` script clears traces via ClickHouse directly:

```bash
# Get ClickHouse password
CH_PASS=$(oc get secret langfuse-clickhouse-auth -n langfuse -o jsonpath='{.data.password}' | base64 -d)

# Truncate traces and observations
oc exec langfuse-clickhouse-shard0-0 -n langfuse -- \
  clickhouse-client --user default --password "$CH_PASS" \
  --query "ALTER TABLE default.traces DELETE WHERE 1=1"
oc exec langfuse-clickhouse-shard0-0 -n langfuse -- \
  clickhouse-client --user default --password "$CH_PASS" \
  --query "ALTER TABLE default.observations DELETE WHERE 1=1"
```

Note: `analytics_traces` and `analytics_observations` are views (not tables) and cannot be truncated directly.

---

## Verification

After running `./audience-reset.sh <N>`:

```bash
# 1. Check 3 plugins loaded
oc logs deployment/instance -n agentic-user<N> -c gateway | grep "plugins:"
# Expected: "3 plugins: diagnostics-otel, diagnostics-prometheus, langfuse-tracer"

# 2. Check Langfuse env vars
oc exec deployment/instance -n agentic-user<N> -c gateway -- env | grep LANGFUSE
# Expected: LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_BASE_URL

# 3. Check OTEL env vars point at MLflow (not Langfuse)
oc exec deployment/instance -n agentic-user<N> -c gateway -- env | grep OTEL_EXPORTER
# Expected: ...mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces

# 4. Check plugin files exist
oc exec deployment/instance -n agentic-user<N> -c gateway -- ls /home/node/.openclaw/extensions/langfuse-tracer/
# Expected: index.js  openclaw.plugin.json

# 5. Send a chat message, then check Langfuse API
source .env
curl -s -u "${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}" \
  "${LANGFUSE_HOST}/api/public/traces?limit=5" | python3 -m json.tool
# Expected: traces with name "openclaw-turn" and populated input/output fields

# 6. Check MLflow also has OTEL traces
# Open MLflow UI → Experiments → openclaw-traces → Traces tab
```

---

## Gotchas

1. **Extensions NOT auto-discovered:** Placing files in `/extensions/` is not enough. The plugin must be registered in `openclaw.json` under `plugins.allow` and `plugins.entries`.

2. **`allowConversationAccess: true` required:** Without this flag in `plugins.entries`, non-bundled plugins are silently blocked from conversation hooks. The plugin would load but only see heartbeat events, not user messages.

3. **`oc rollout restart` wipes config:** Restarts re-seed `openclaw.json` from the operator, removing plugin registrations. The `post-restart-repatch.sh` script re-registers the plugin. Plugin files in `/extensions/` survive because that directory isn't part of the state wipe.

4. **`kill 1` preserves config:** To restart the gateway process without re-seeding `openclaw.json`, use `oc exec ... -- kill 1` inside the container. This preserves PVC-based config including plugin registrations.

5. **OTEL noise in Langfuse:** The `diagnostics-otel` plugin generates ~3 traces per heartbeat cycle per namespace (every ~2.5 minutes). With 20 namespaces, that's ~60 noise traces every few minutes — all with `input: null, output: null`. Routing `diagnostics-otel` to MLflow instead of Langfuse eliminates this noise entirely.

6. **`ENABLE_EXPERIMENTAL_FEATURES=true`:** Required on both `langfuse-web` and `langfuse-worker` deployments. Without it, Langfuse's OTEL ingestion endpoint (`/api/public/otel/v1/traces`) returns HTTP 200 but silently discards all data.

7. **ClickHouse auth:** The ClickHouse password is stored in `langfuse-clickhouse-auth` secret (not the default `langfuse-clickhouse` secret). The `default` user requires a password — anonymous access is disabled.
