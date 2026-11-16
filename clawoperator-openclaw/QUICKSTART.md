# Quick Start

## A — Fresh Cluster Setup (50 Users, End-to-End)

**Prerequisites:**
- `oc login` as cluster-admin
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo at `../../claw-operator`
- For multi-cluster broker sync, create `clusters.csv` as described in Section E. A single-cluster setup does not need it.
- `agentic-user1` through `agentic-user50` namespaces and user accounts already provisioned on the cluster
- For OCP + ODF logging: the `openshift-storage.noobaa.io` StorageClass and ObjectBucketClaim CRD must be available. Set `LOKI_OBJECT_STORE=odf` and `SITE_NAME=ocp` in `../.env`.

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
USER_PREFIX=agentic-user ./0-admin-setup.sh 1 50  # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + ODF when configured)
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

With `LOKI_OBJECT_STORE=odf`, `deploy-logs-loki.sh` creates a NooBaa ObjectBucketClaim in the cluster; no AWS account or S3 domain is needed. Its default `s3` mode creates an AWS bucket and IAM user and does require AWS credentials. `SITE_NAME=ocp` selects the OpenShift audience-route domain for scripts that read the site configuration; `--site ocp` is the equivalent per-command option. Use the OCP broker commands in Phase 2.5 for this setup.

For AWS installations only, CloudWatch trace forwarding is an optional
step after MLflow is ready. It is not part of an OCP/ODF installation. See
[cloudwatch-traces/README.md](cloudwatch-traces/README.md) for the explicit
`INSTALLATION_TYPE=aws` setup and seat opt-in.

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

The existing session broker stays on the original cluster (currently `jzsjx`). Each new cluster gets its own operator, observability services, and 50 OpenClaw instances. The broker then combines their audience routes into one pool; do not run `deploy-broker-ocp.sh` on the new cluster.

### 1. Prepare each new OCP + ODF cluster

Have a separate, logged-in kubeconfig for each cluster and provision `agentic-user1` through `agentic-user50` namespaces and user accounts first. Use the root `../.env` with `SITE_NAME=ocp`, `LOKI_OBJECT_STORE=odf`, and the intended LiteLLM model, URL, and API token. The ODF cluster needs the NooBaa StorageClass and ObjectBucketClaim CRD described in Section A. The operator checkout at `../../claw-operator` (or `CLAW_OPERATOR_HOME`) and tools required by Section A must be available where you run these commands.

From `clawoperator-openclaw`, point `KUBECONFIG` at the **new** cluster and run Section A's per-cluster phases only:

```bash
export KUBECONFIG=/absolute/path/kubeconfig-NEWGUID
oc whoami --show-server          # Confirm the new cluster before changing it
USER_PREFIX=agentic-user ./0-admin-setup.sh 1 50
./deploy-logs-loki.sh
./deploy-dashboards-grafana.sh
./deploy-traces-mlflow.sh
./deploy-traces-langfuse.sh
./audience-reset.sh --site ocp 1 50
./set-namespace-quotas.sh 1 50
```

Repeat this block for each additional cluster, with its own kubeconfig. `audience-reset.sh` creates the audience routes and per-cluster state; it also configures each gateway to use that cluster's MLflow and Langfuse services. `sites/ocp.env` derives the apps domain from the active cluster. The scripts derive `.state/<cluster-guid>/` from the cluster API hostname.

The pinned operator image `554d988` needs the MCP ordering fix in [`operator-patches/README.md`](operator-patches/README.md). Build and deploy that corrected image on each cluster before relying on gateway readiness with three MCP servers.

### 2. Register all clusters for broker discovery

In `clawoperator-openclaw`, copy and edit the local CSV. Include the **existing broker cluster** as well as every new cluster; otherwise its users disappear from the broker's route pool on the next sync.

```bash
cp clusters.csv.example clusters.csv
```

```csv
jzsjx,/absolute/path/kubeconfig-jzsjx
NEWGUID,/absolute/path/kubeconfig-NEWGUID
```

Use the real new GUID and absolute kubeconfig paths. Add another line for a third cluster. The format is `cluster_id,kubeconfig_path`; lines beginning with `#` are ignored. `clusters.csv` is local and gitignored. Each listed kubeconfig must work with `oc whoami`.

### 3. Sync the existing broker and verify

Switch the ambient context **back to the cluster hosting `session-broker`**. The sync script uses that context to reach the broker and `clusters.csv` to discover all clusters' audience routes.

```bash
export KUBECONFIG=/absolute/path/kubeconfig-jzsjx
oc whoami --show-server          # Confirm the broker cluster
./update-broker-ocp.sh --rotate-status-key
./demo-preflight.sh --site ocp 1 50
./demo-urls.sh --site ocp
```

If local DNS intermittently fails for the wildcard app routes during preflight, set `PREFLIGHT_ROUTE_IP_MAP` to comma-separated `GUID:ingress-ip` entries and optionally lower `PREFLIGHT_MAX_PARALLEL`. The preflight still connects over TLS to each route host using its matching cluster ingress IP.

`update-broker-ocp.sh` prints the route count per cluster and the live audience and status URLs. For two fully populated clusters, expect 100 routes. The default reload preserves existing visitor assignments; do not use `--reset` when simply adding capacity. `--rotate-status-key` changes the status-page link, so share the newly printed one. `demo-preflight.sh` checks every cluster listed in `clusters.csv`.

To add another cluster later, repeat steps 1–3 and append its line to the same CSV. If `clusters.csv` is absent, the OCP broker sync uses only the current `oc` context.

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

## H — ROSA Single-Cluster Demo with AWS S3

For a ROSA hosted control plane, scale the worker machine pool through the ROSA CLI or OpenShift Cluster Manager. The cluster does not expose worker `MachineSet` resources. Confirm that the new workers are Ready before deploying the audience seats.

The OpenShift apps domain already resolves to the cluster's AWS Network Load Balancer. The broker and all audience Routes use that domain; no Route 53 zone or custom domain is required. Keep `clusters.csv` to a single entry for this cluster, or remove it to use the current `oc` context.

The root `.env` may remain configured for an ODF cluster. Select AWS S3 only for this deployment:

```bash
oc whoami --show-server
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}'
# If Loki was paused while waiting for workers, resume its operator first:
oc patch lokistack logging-loki -n openshift-logging --type merge -p '{"spec":{"managementState":"Managed"}}'
./deploy-logs-loki.sh --object-store s3
./deploy-dashboards-grafana.sh
./deploy-traces-mlflow.sh
./deploy-traces-langfuse.sh
./mirror-fantaco-images.sh          # mirror six images into the OpenShift registry before a large rollout
./audience-reset.sh --site ocp 1 130
./set-namespace-quotas.sh 1 130
./deploy-broker-ocp.sh --rebuild
./update-broker-ocp.sh
./demo-preflight.sh --site ocp 1 130
./demo-urls.sh --site ocp
```

The S3 bucket stores Loki logs. Langfuse still deploys its bundled MinIO object store through its Helm chart. The image mirror uses the cluster registry and saves its image prefix in gitignored `.state/<cluster-guid>/image-mirror.env`; later backend deployments use that prefix automatically. The broker uses portable PostgreSQL with three CloudNativePG instances and two broker replicas; its data layer has no AWS-specific connection settings. See [broker-pg/README.md](broker-pg/README.md). Audience members can use the broker without OpenShift console accounts; console logins require a supported identity provider.

For an AWS installation that also needs CloudWatch traces, opt in after MLflow
is ready. This is not a step for OCP/ODF installations; see
[cloudwatch-traces/README.md](cloudwatch-traces/README.md) for the AWS and
collector setup, then connect the desired seats:

```bash
export INSTALLATION_TYPE=aws
./setup-cloudwatch-traces-aws.py
./deploy-cloudwatch-traces.sh
./enable-cloudwatch-traces-seats.py 1 150 --site ocp --parallel 5
```

To add seats to the existing ROSA audience, confirm the new worker is `Ready`, then use a kubeconfig whose current context is this ROSA cluster. Expansion reuses the current audience code and leaves existing routes, assignments, and observability history intact:

```bash
export KUBECONFIG=/absolute/path/to/rosa-kubeconfig
oc whoami --show-server
oc get nodes
EXPAND_NODE_SELECTOR='node.kubernetes.io/instance-type=m6a.4xlarge' \
  ./audience-reset.sh --site ocp --expand 131 150
./set-namespace-quotas.sh 131 150
./update-broker-ocp.sh              # no --reset; preserve assignments
./demo-preflight.sh --site ocp 131 150
```

The node selector is optional; use a type with enough capacity for the new seats. Keep `clusters.csv` pointed at the same logged-in ROSA kubeconfig before the broker sync.

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
