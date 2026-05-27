# Quick Start

## A — Fresh Cluster Setup (20 Users, End-to-End)

**Prerequisites:**
- `oc login` as cluster-admin
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo at `../../claw-operator`
- AWS credentials active (`aws login` — root sessions expire after 1 hour)

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
./0-admin-setup.sh 1 22              # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + S3)
./deploy-dashboards-grafana.sh       # Step 3: Grafana dashboards (Prometheus + Loki data sources)
./deploy-traces-mlflow.sh            # Step 4: LLM trace collection (MLflow + OTEL)
./deploy-traces-langfuse.sh          # Step 5: LLM observability (Langfuse — populates .state/langfuse.env)

# ── Phase 1.5: Refresh AWS session ──────────────────────────────────
# Root sessions are capped at 1 hour by AWS. Refresh RIGHT BEFORE
# audience-reset.sh to maximize the window (the script takes ~15 min).
aws login
aws sts get-caller-identity          # Verify credentials are active

# ── Phase 2: Deploy everything + audience reset ──────────────────────
./audience-reset.sh 1 22             # Step 6: Claw instances, backends, MCP, traces, skills, URLs, broker
./set-namespace-quotas.sh 1 22       # Step 7: Resource quotas (3c req, 4Gi req, 8c lim, 10Gi lim, 16 pods)
./enable-prometheus.sh 1 22          # Step 8: Prometheus metrics (one-time: creates ServiceMonitor + NetworkPolicy)

# ── Phase 3: Verify ──────────────────────────────────────────────────
./demo-preflight.sh 1 22             # Step 9: Pre-demo preflight check + stage-ready URLs
```

### What audience-reset.sh does

1. Deploys Claw instances, backends (FantaCo Java apps), and MCP servers
2. Injects MCP server config into Claw CRs
3. Clears previous MLflow/Langfuse traces
4. Configures `diagnostics-otel` + `langfuse-tracer` plugins (from `claw_plugins/langfuse-tracer/`)
5. Injects `quote-builder` enterprise skill + AGENTS.md + IDENTITY.md
6. Generates unique audience URLs and uploads `routes.csv` to S3
7. Updates the Route-LB broker at `yougetaclaw.com`

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

Before each subsequent demo, re-run these commands to wipe all user state (chats, memory, skills, cron), generate new audience URLs, re-inject everything, and update the broker:

```bash
# Refresh AWS session first (root = 1 hour max)
aws login
aws sts get-caller-identity

# Reset and verify
./audience-reset.sh 1 22             # Wipe state, new URLs, re-inject everything
./demo-preflight.sh 1 22             # Verify
```

`enable-prometheus.sh` does **not** need to re-run — `audience-reset.sh` automatically re-installs the plugin and re-patches config if a ServiceMonitor already exists.

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

If audience URLs need refreshing without a full audience-reset:

```bash
./update-broker.sh 1 22
```

---

## E — Post-Restart Re-patch

If pods restart (e.g. after `oc rollout restart`), the operator re-seeds `openclaw.json` from the Claw CR, wiping JSON patches. Re-apply config:

```bash
./post-restart-repatch.sh 1 22
```

Or kill PID 1 inside the container instead of `oc rollout restart` — this preserves PVC config.

---

## Key Files

| File | Purpose |
|------|---------|
| `../.env` | AWS keys, Langfuse keys, GCP project, broker config |
| `.state/langfuse.env` | Auto-populated by `deploy-traces-langfuse.sh` |
| `.state/logging.env` | Auto-populated by `deploy-logs-loki.sh` |
| `claw_plugins/langfuse-tracer/` | Custom Langfuse plugin (injected by audience-reset.sh) |
| `test_prompts.md` | Demo prompts with expected behaviors |
| `E2E_MCP_TRACING.md` | Research: distributed tracing through MCP servers |
