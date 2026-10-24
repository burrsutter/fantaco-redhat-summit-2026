# Quick Start

## A — Fresh Cluster Setup (50 Users, End-to-End)

**Prerequisites:**
- `oc login` as cluster-admin
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo at `../../claw-operator`
- `clusters.csv` created (copy from `clusters.csv.example`, add your cluster ID + kubeconfig path — see Section E for format). Many scripts read this file to resolve cluster IDs to kubeconfig paths.

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
./0-admin-setup.sh 1 50              # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + S3) — needs AWS creds, see note
./deploy-dashboards-grafana.sh       # Step 3: Grafana dashboards (Prometheus + Loki data sources)
./deploy-traces-mlflow.sh            # Step 4: LLM trace collection (MLflow + OTEL)
./deploy-traces-langfuse.sh          # Step 5: LLM observability (Langfuse — populates .state/langfuse.env)

# ── Phase 2: Deploy everything + audience reset (no AWS needed) ──────
./audience-reset.sh 1 50             # Step 6: Claw instances, backends, MCP, traces, Prometheus, skills, URLs
./set-namespace-quotas.sh 1 50       # Step 7: Resource quotas (3c req, 4Gi req, 8c lim, 10Gi lim, 16 pods)

# ── Phase 2.5: Publish to broker ────────────────────────────────────
# Option A — OCP-native broker (no AWS, no custom domain):
./deploy-broker-ocp.sh               # Step 8a: One-time: build + deploy broker on OpenShift
./update-broker-ocp.sh --rotate-status-key  # Step 8b: Inject routes, print share URL

# Option B — S3 broker (yougetaclaw.com, requires AWS):
# aws login
# ./update-broker.sh --rotate-status-key

# ── Phase 3: Verify ──────────────────────────────────────────────────
./demo-preflight.sh 1 50             # Step 9: Pre-demo preflight check (pass/fail health checks)
./demo-urls.sh                       # Step 10: Stage-ready URLs, QR code, provider info
```

`deploy-logs-loki.sh` is the one step with an external dependency: it creates an S3 bucket and IAM user via the `aws` CLI, so it needs working AWS credentials and an AWS-backed cluster. Everything else in Section A is cluster-only. Skipping it costs you centralized logs and Grafana's Loki data source; the Prometheus source, MLflow, Langfuse and the demo flow are unaffected.

### What audience-reset.sh does

1. Deploys Claw instances, backends (FantaCo Java apps), and MCP servers
2. Injects MCP server config into Claw CRs
3. Creates Prometheus ServiceMonitor + NetworkPolicy per namespace
4. Clears previous MLflow/Langfuse traces
5. Configures `diagnostics-prometheus` + `diagnostics-otel` + `langfuse-tracer` plugins
6. Injects `quote-builder` enterprise skill + AGENTS.md + IDENTITY.md
7. Generates unique audience URLs (saves audience code to `.state/<cluster-guid>/broker.env`)

### FantaCo Web UIs (per namespace)

Each namespace has its own Customer, Product, and Sales Order web apps:

```bash
NS=agentic-user1
echo "Customers:    https://$(oc get route fantaco-customer-service -n $NS -o jsonpath='{.spec.host}')/customers/index.html"
echo "Products:     https://$(oc get route fantaco-product-service -n $NS -o jsonpath='{.spec.host}')/catalog/index.html"
echo "Sales Orders: https://$(oc get route fantaco-sales-order-service -n $NS -o jsonpath='{.spec.host}')/orders/index.html"
```

### Observability UIs

```bash
echo "Grafana:      https://$(oc get route grafana-route -n grafana -o jsonpath='{.spec.host}')"
echo "Langfuse:     https://$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}')"
echo "MLflow:       https://$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}')"
```

### Session Broker

The broker assigns audience members to OpenClaw instances. Each `audience-reset.sh` run generates a new audience ID (e.g. `b31cf`), so the audience entry URL changes each time.

**OCP broker** (recommended): runs directly on the cluster — no AWS or custom domain needed.

```bash
echo "Broker URL:    https://session-broker-session-broker.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')/<audience-code>"
echo "Broker status: https://session-broker-session-broker.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')/status?key=<status-key>"
```

**S3 broker** (yougetaclaw.com): requires AWS credentials and the custom domain.

```bash
echo "Broker status: https://yougetaclaw.com/status"
```

---

## B — New Audience Reset (Subsequent Demos)

Before each subsequent demo, re-run these commands to wipe all user state (chats, memory, skills, cron), generate new audience URLs, and re-inject everything:

```bash
# Reset (no AWS needed)
./audience-reset.sh 1 50             # Wipe state, new URLs, re-inject everything

# Publish to broker
./update-broker-ocp.sh --rotate-status-key   # OCP broker (no AWS needed)
# Or: aws login && ./update-broker.sh --rotate-status-key   # S3 broker

# Verify
./demo-preflight.sh 1 50
./demo-urls.sh
```

Prometheus setup (ServiceMonitor, NetworkPolicy, plugin) is handled automatically by `audience-reset.sh` — no separate step needed.

---

## C — Proxy Allowlist Demo

Demonstrates the zero-trust network boundary: agents can only reach approved external domains.

### Review blocked requests (via Loki)

```bash
./review-blocked-requests.sh              # last 1 hour, all namespaces
./review-blocked-requests.sh 5m           # last 5 minutes
./review-blocked-requests.sh 24h user2    # last 24 hours, specific user
```

### Allow/revoke domains

```bash
# Allow a single domain (all namespaces)
./manage-proxy-allowlist.sh allow apod.nasa.gov

# Allow multiple domains (comma-separated, specific user)
./manage-proxy-allowlist.sh allow xkcd.com,imgs.xkcd.com 2

# Revoke access
./manage-proxy-allowlist.sh revoke apod.nasa.gov

# List current allowlist
./manage-proxy-allowlist.sh list 2
```

### Demo flow

1. Send prompt: `Show me the NASA APOD` → agent fails (proxy blocks `apod.nasa.gov`)
2. Run `./review-blocked-requests.sh 5m` → see the blocked domain in Loki
3. Run `./manage-proxy-allowlist.sh allow apod.nasa.gov` → operator updates proxy config (~10 sec)
4. Re-send prompt → succeeds

See `test_prompts.md` for full demo script and alternative prompts (BBC News, XKCD, etc.).

---

## D — Standalone Broker Update

If the broker needs re-syncing with the cluster (without a full audience-reset):

```bash
# OCP broker (no AWS needed)
./update-broker-ocp.sh --rotate-status-key

# S3 broker (yougetaclaw.com)
# aws login
# ./update-broker.sh --rotate-status-key
```

---

## E — Multi-Cluster Setup (2+ Clusters)

Scale the demo beyond a single cluster by distributing audience members across multiple OpenShift clusters. The broker merges routes from all clusters into one pool — visitors are assigned to any available instance regardless of which cluster it runs on.

### Prerequisites

- Each cluster fully set up via **Section A** (operator, observability, audience-reset)
- A separate kubeconfig file per cluster (e.g. `~/.kube/config-cluster-fr9sv`)
- `oc login` working for each kubeconfig

Per-cluster vs shared, so you know what to repeat on cluster 2:

| Repeat on every cluster | Deploy once, shared |
|---|---|
| operator + RBAC, MLflow, Langfuse, Grafana, `audience-reset.sh`, quotas, per-user API keys | the session broker (`deploy-broker-ocp.sh`) |

MLflow and Langfuse are per-cluster because `post-restart-repatch.sh` points each gateway at the `mlflow`/`langfuse` route **in its own cluster** — a gateway cannot reach the other cluster's internal service. The broker is shared by design: it holds one route pool, so it must run on exactly one cluster and discover the rest through `clusters.csv`.

Scripts derive `.state/<cluster-guid>/` from the API hostname and handle both shapes in use — `api.ocp.<guid>.sandboxNNNN.opentlc.com` (sandbox) and `api.cluster-<guid>.dyn.redhatworkshops.io` (RHDP workshop).

### Step 1: Create `clusters.csv`

```bash
cp clusters.csv.example clusters.csv
```

Edit with your cluster details — one line per cluster:

```csv
fr9sv,/Users/bsutter/.kube/config-cluster-fr9sv
w6hwm,/Users/bsutter/.kube/config-cluster-w6hwm
```

Format: `cluster_id,kubeconfig_path` (lines starting with `#` are ignored).

### Step 2: Run audience-reset on each cluster

```bash
# Cluster 1
export KUBECONFIG=~/.kube/config-cluster-fr9sv
./audience-reset.sh 1 50

# Cluster 2
export KUBECONFIG=~/.kube/config-cluster-w6hwm
./audience-reset.sh 1 50
```

### Step 3: Publish merged routes to broker

```bash
# Point the current context at the cluster the broker runs on — the script
# reads clusters.csv for route *discovery*, but finds the broker Deployment
# itself through the ambient oc context.
export KUBECONFIG=~/.kube/config-cluster-fr9sv

# OCP broker (no AWS needed)
./update-broker-ocp.sh --rotate-status-key

# S3 broker (yougetaclaw.com)
# aws login
# ./update-broker.sh --rotate-status-key
```

Both `update-broker-ocp.sh` and `update-broker.sh` automatically detect `clusters.csv` and switch to multi-cluster mode:
- Discovers routes from **all** clusters listed in `clusters.csv`
- Merges them into a single `routes.csv`
- OCP broker: injects routes into the broker pod on the cluster
- S3 broker: uploads to S3 and resets the broker

Output shows per-cluster counts:

```
Routes: 50 fr9sv + 50 w6hwm = 100 total
```

### Step 4: Verify

```bash
./demo-preflight.sh 1 50    # Run against each cluster via KUBECONFIG
./demo-urls.sh               # Stage-ready URLs, QR code, provider info
```

The status board shows a **Cluster** column so you can see which cluster each route belongs to. The status URL is printed by the update script (OCP: `https://session-broker-.../<status-path>`, S3: `https://yougetaclaw.com/status`).

### Adding a cluster later

1. Run **Section A** on the new cluster
2. Add the new line to `clusters.csv`
3. Re-run `./update-broker-ocp.sh --rotate-status-key` (or `./update-broker.sh` for S3)

The broker pool grows — existing assignments are preserved.

### Single-cluster fallback

If `clusters.csv` is absent, `update-broker.sh` falls back to the current `oc` context (single cluster). No changes needed for single-cluster demos.

---

## F — Post-Restart Re-patch

If pods restart (e.g. after `oc rollout restart`), the operator re-seeds `openclaw.json` from the Claw CR, wiping JSON patches. Re-apply config:

```bash
./post-restart-repatch.sh 1 50
```

Killing PID 1 inside the container is **not** a way around this. The pod is recreated, the init containers re-run, and the re-seed happens exactly as it would after `oc rollout restart`.

Anything that must survive a restart belongs in the CR instead, under `spec.config.raw` — merged into `operator.json` before the operator's enrichment pipeline runs, so it is re-applied on every pod start rather than overwritten. `gateway.controlUi.allowedOrigins` is set that way (see Section G).

---

## G — Repairs

| Symptom | Fix |
|---------|-----|
| Control UI shows **"Browser origin not allowed"** when reached via the broker | `./set-audience-origins.sh 1 50` — puts the audience route host into `spec.config.raw` so the operator seeds it. `--check` to report only. |
| Gateway in `CrashLoopBackOff` with `plugin manifest not found` or `older than the config last written` | `./repair-gateway.sh 1 50` — mounts the PVC from a node-pinned repair pod. `--check` to report only. |
| Model reverted to `openai/gpt-5.6`, no embeddings, no OTEL | `./post-restart-repatch.sh --site ocp 1 50` |
| Share URL 404s | The broker's own `stats.audience_id` is authoritative; `./update-broker-ocp.sh` reads it back and prints the right one. |

Always re-run `post-restart-repatch.sh` after a repair — a restart can trigger an operator re-seed.

---

## Key Files

| File | Purpose |
|------|---------|
| `demo-preflight.sh` | Pass/fail health checks across all namespaces/clusters |
| `demo-urls.sh` | Stage-ready URLs, QR code, observability links, provider info |
| `deploy-broker-ocp.sh` | One-time: build + deploy session broker on OpenShift (no AWS needed) |
| `update-broker-ocp.sh` | Inject routes into OCP broker, print share URL |
| `update-broker.sh` | Upload routes to S3 broker at yougetaclaw.com (requires AWS) |
| `set-audience-origins.sh` | Make the Control UI accept the broker's audience host (Section G) |
| `repair-gateway.sh` | Repair gateways that cannot boot, without wiping the PVC (Section G) |
| `../.env` | AWS keys, Langfuse keys, GCP project, broker config |
| `clusters.csv` | Multi-cluster config — one `cluster_id,kubeconfig_path` per line (copy from `.example`) |
| `.state/langfuse.env` | Auto-populated by `deploy-traces-langfuse.sh` |
| `.state/logging.env` | Auto-populated by `deploy-logs-loki.sh` |
| `.state/<guid>/broker.env` | Per-cluster broker state (audience code, status key) |
| `claw_plugins/langfuse-tracer/` | Custom Langfuse plugin (injected by audience-reset.sh) |
| `test_prompts.md` | Demo prompts with expected behaviors |
| `E2E_MCP_TRACING.md` | Research: distributed tracing through MCP servers |
