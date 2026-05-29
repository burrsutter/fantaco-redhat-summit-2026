# Quick Start

## A — Fresh Cluster Setup (20 Users, End-to-End)

**Prerequisites:**
- `oc login` as cluster-admin
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo at `../../claw-operator`

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
./0-admin-setup.sh 1 22              # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + S3)
./deploy-dashboards-grafana.sh       # Step 3: Grafana dashboards (Prometheus + Loki data sources)
./deploy-traces-mlflow.sh            # Step 4: LLM trace collection (MLflow + OTEL)
./deploy-traces-langfuse.sh          # Step 5: LLM observability (Langfuse — populates .state/langfuse.env)

# ── Phase 2: Deploy everything + audience reset (no AWS needed) ──────
./audience-reset.sh 1 22             # Step 6: Claw instances, backends, MCP, traces, Prometheus, skills, URLs
./set-namespace-quotas.sh 1 22       # Step 7: Resource quotas (3c req, 4Gi req, 8c lim, 10Gi lim, 16 pods)

# ── Phase 2.5: Publish to broker (requires AWS) ─────────────────────
aws login                            # Root sessions expire after 1 hour
./update-broker.sh --rotate-status-key  # Step 8: Upload routes to S3, reset broker, print share URL + QR

# ── Phase 3: Verify ──────────────────────────────────────────────────
./demo-preflight.sh 1 22             # Step 9: Pre-demo preflight check (pass/fail health checks)
./demo-urls.sh                       # Step 10: Stage-ready URLs, QR code, provider info
```

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

```bash
echo "Broker status: https://yougetaclaw.com/status"
```

The broker assigns audience members to OpenClaw instances. Each `audience-reset.sh` run generates a new audience ID (e.g. `b31cf`), so the audience entry URL changes each time (e.g. `https://yougetaclaw.com/b31cf`).

---

## B — New Audience Reset (Subsequent Demos)

Before each subsequent demo, re-run these commands to wipe all user state (chats, memory, skills, cron), generate new audience URLs, and re-inject everything:

```bash
# Reset (no AWS needed)
./audience-reset.sh 1 22             # Wipe state, new URLs, re-inject everything

# Publish to broker (requires AWS)
aws login
./update-broker.sh --rotate-status-key

# Verify
./demo-preflight.sh 1 22
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
aws login
./update-broker.sh --rotate-status-key
```

---

## E — Multi-Cluster Setup (2+ Clusters)

Scale the demo beyond a single cluster by distributing audience members across multiple OpenShift clusters. The broker merges routes from all clusters into one pool — visitors are assigned to any available instance regardless of which cluster it runs on.

### Prerequisites

- Each cluster fully set up via **Section A** (operator, observability, audience-reset)
- A separate kubeconfig file per cluster (e.g. `~/.kube/config-cluster-fr9sv`)
- `oc login` working for each kubeconfig

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
./audience-reset.sh 1 22

# Cluster 2
export KUBECONFIG=~/.kube/config-cluster-w6hwm
./audience-reset.sh 1 22
```

### Step 3: Publish merged routes to broker

```bash
aws login
./update-broker.sh --rotate-status-key
```

`update-broker.sh` automatically detects `clusters.csv` and switches to multi-cluster mode:
- Discovers routes from **all** clusters listed in `clusters.csv`
- Merges them into a single `routes.csv`
- Uploads to S3 and resets the broker

Output shows per-cluster counts:

```
Routes: 22 fr9sv + 22 w6hwm = 44 total
```

### Step 4: Verify

```bash
./demo-preflight.sh 1 22    # Run against each cluster via KUBECONFIG
./demo-urls.sh               # Stage-ready URLs, QR code, provider info
```

The status board (`https://yougetaclaw.com/status`) shows a **Cluster** column so you can see which cluster each route belongs to.

### Adding a cluster later

1. Run **Section A** on the new cluster
2. Add the new line to `clusters.csv`
3. Re-run `./update-broker.sh --rotate-status-key`

The broker pool grows — existing assignments are preserved.

### Single-cluster fallback

If `clusters.csv` is absent, `update-broker.sh` falls back to the current `oc` context (single cluster). No changes needed for single-cluster demos.

---

## F — Post-Restart Re-patch

If pods restart (e.g. after `oc rollout restart`), the operator re-seeds `openclaw.json` from the Claw CR, wiping JSON patches. Re-apply config:

```bash
./post-restart-repatch.sh 1 22
```

Or kill PID 1 inside the container instead of `oc rollout restart` — this preserves PVC config.

---

## Key Files

| File | Purpose |
|------|---------|
| `demo-preflight.sh` | Pass/fail health checks across all namespaces/clusters |
| `demo-urls.sh` | Stage-ready URLs, QR code, observability links, provider info |
| `../.env` | AWS keys, Langfuse keys, GCP project, broker config |
| `clusters.csv` | Multi-cluster config — one `cluster_id,kubeconfig_path` per line (copy from `.example`) |
| `.state/langfuse.env` | Auto-populated by `deploy-traces-langfuse.sh` |
| `.state/logging.env` | Auto-populated by `deploy-logs-loki.sh` |
| `.state/<guid>/broker.env` | Per-cluster broker state (audience code, status key) |
| `claw_plugins/langfuse-tracer/` | Custom Langfuse plugin (injected by audience-reset.sh) |
| `test_prompts.md` | Demo prompts with expected behaviors |
| `E2E_MCP_TRACING.md` | Research: distributed tracing through MCP servers |
