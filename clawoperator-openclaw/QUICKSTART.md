# Quick Start

## Reference architecture

**One ROSA HCP cluster with N seats, entirely on OpenShift.** No AWS S3, no
Route 53, no ELB, no custom domain. Loki stores logs in in-cluster ODF object
storage, and the session broker is a Route on the cluster itself.

This is a deliberate change from the original design, which assumed an
RHDP-provisioned cluster, an AWS S3 bucket and the `yougetaclaw.com` domain.
Those paths still work and are documented, but they are now **secondary**:

| path | status | when to use |
|---|---|---|
| **Single ROSA HCP cluster, full OCP** | **default** | everything below assumes this |
| Multiple OCP clusters | secondary | more seats than one cluster can hold |
| AWS S3 / Route 53 / ELB | optional | you already have the AWS estate and want it |

N is whatever the person building the cluster chooses — the tooling takes a
seat range everywhere. Darmstadt ran 100.

### Sizing the cluster

Measured on `rosa-tztnl` with 100 seats live:

| per seat | measured |
|---|---|
| pods | **11** |
| CPU requests | **0.57 cores** |
| memory requests | **2.66 GiB** |

**Pods are the binding constraint, not CPU or memory.** At 100 seats the
cluster was at 71% of its pod ceiling (1412 of 2000 slots) while using 46% of
memory requests and 20% of CPU requests. A node defaults to 250 pods, so size
on pods first:

```
worker nodes = ceil((11 x N + 320) / 200)
```

320 covers platform pods (RHOAI, Loki, monitoring, broker, operators); 200
rather than 250 leaves headroom for rollouts, which briefly double a seat's
pods.

| seats | worker nodes | pod slots | seat pods |
|---|---|---|---|
| 25  | 3  | 750  | 275  |
| 50  | 5  | 1250 | 550  |
| 100 | 8  | 2000 | 1100 |
| 150 | 10 | 2500 | 1650 |
| 200 | 13 | 3250 | 2200 |

**Instance type: `m6a.4xlarge` (16 vCPU, 64 GiB) or `m7a.4xlarge`.** The
workload asks for roughly 4.7 GiB per requested core. A general-purpose `m`
family gives 4 GiB/vCPU, which matches; a compute-optimised `c` family gives
2 GiB/vCPU, so you end up buying about twice the CPU you need in order to get
the memory you need. Darmstadt ran 6 x `c6a.12xlarge` + 2 x `m6a.xlarge`: it
worked comfortably, but the large nodes sat at **1-2% CPU and ~32% memory**,
and across the fleet CPU requests were 20% of capacity against 46% for memory.
Nothing ran out — it was simply the wrong shape, and more expensive than it
needed to be.

Check memory as well as pods, since it is the tighter of the two resources:
`2.7 GiB x N` plus roughly 60 GiB of platform overhead must fit in the worker
pool. At 100 seats that is ~330 GiB, comfortably inside 8 x 64 GiB.

Two caveats worth stating plainly:

- Those utilisation figures were taken with the fleet **idle** (post-event,
  heartbeat disabled). Inference runs upstream on MaaS, so the seats are mostly
  waiting on I/O rather than computing, but validate at your own seat count
  before committing to a smaller instance type.
- `set-namespace-quotas.sh` caps each seat at **8 CPU / 16 GiB requests,
  16 CPU / 32 GiB limits, 28 pods**. Those limits are far above steady-state
  use; they exist to stop one runaway seat starving the rest.

Scale the worker pool through the ROSA CLI or OpenShift Cluster Manager — a
hosted control plane does not expose worker `MachineSet` resources.

---

## A — Fresh Cluster Setup (ROSA HCP, N seats, full OCP path)

**Prerequisites**

- `oc login` as cluster-admin against the ROSA HCP cluster
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo checked out at `../../claw-operator` (public):
  ```bash
  git clone https://github.com/codeready-toolchain/claw-operator.git ../../claw-operator
  ```
  Override the location with `CLAW_OPERATOR_HOME` if you keep it elsewhere.
  `0-admin-setup.sh` reads it to install the operator.
- **An RHDP MaaS virtual key** in `../.env` as `MAAS_UPSTREAM_API_KEY`. This is
  the one credential the repo cannot provide; everything downstream is minted
  by the cluster. Without it there is no model and the agents cannot infer.
- `LOKI_OBJECT_STORE=odf` and `SITE_NAME=ocp` in `../.env`
- The `openshift-storage.noobaa.io` StorageClass and ObjectBucketClaim CRD
  available (ODF installed)
- No `clusters.csv` needed for a single cluster

On ROSA **STS**, NooBaa hangs forever waiting for a credential the Cloud
Credential Operator never mints in Manual mode, and the CredentialsRequest
reports `provisioned: true` while the secret does not exist — verify the
*secret*, not the request.

Substitute your own seat count for `100` throughout.

```bash
cd clawoperator-openclaw

# -- Phase 1: cluster + platform ---------------------------------------
USER_PREFIX=agentic-user ./0-admin-setup.sh 1 100   # operator, UWM, RBAC
oc apply -f operator-patches/rhoai-dsc-maas-mlflow.yaml   # RHOAI components
./mirror-fantaco-images.sh                          # BEFORE any large rollout
./extend-cluster.sh 100                             # bare cluster: create the seats
./deploy-observability.sh                           # Loki + Grafana + MLflow

# -- Phase 2: MaaS over MaaS -------------------------------------------
./maas-bootstrap.sh                                 # five prerequisites
./maas-publish-model.sh                             # needs MAAS_UPSTREAM_API_KEY
./maas-mint-seat-keys.sh --smoke-test               # prove inference BEFORE 100 seats

# -- Phase 3: seats -----------------------------------------------------
./1-deploy-claw.sh --create-only 1 100
./audience-reset.sh --site ocp 1 100                # long; verify it exits 0
./set-namespace-quotas.sh 1 100
./maas-mint-seat-keys.sh --apply 1 100              # per-seat keys
./6-inject-enterprise-skills.sh 1 100
./manage-heartbeat.sh disable 1 100                 # cleaner traces, no idle spend

# -- Phase 4: broker + catalog ------------------------------------------
./deploy-broker-ocp.sh
./update-broker-ocp.sh --rotate-status-key          # prints audience + status URLs
./deploy-mcp-catalog.sh                             # MCP catalog (seat 1 as exemplar)
./deploy-genai-playground.sh                        # Gen AI Playground on the demo seat

# -- Phase 5: verify ----------------------------------------------------
./demo-preflight.sh --site ocp 1 100                # expect 19/19 per seat
./demo-urls.sh --site ocp
```

**Verify by counting, never by exit code.** Several of these steps report
success while having done nothing — that is how 100 seats once ended up with
invisible skills. `demo-preflight.sh` is the arbiter.

`mirror-fantaco-images.sh` is not optional at scale: 100 namespaces pulling six
Docker Hub images exhausts the anonymous pull limit around seat 62, and it
presents as a broken demo rather than as a quota error.

Why `./maas-mint-seat-keys.sh --smoke-test` comes before the fleet: without the
label `inference.llm-d.ai/ipp-managed=true` on the upstream secret, every CR
reports Ready, `/v1/models` lists the model and keys issue fine — and only the
first *real* inference fails. The smoke test is the only thing that catches it,
and it tells you the fix if it trips.

See [HANDOFF.md](HANDOFF.md) for the failure modes behind each step.

---

## B — New Audience Reset (Subsequent Demos)

Before each subsequent demo, wipe user state (chats, memory, skills, cron),
generate new audience URLs, and re-inject everything:

```bash
./audience-reset.sh --site ocp 1 100
./6-inject-enterprise-skills.sh 1 100
./manage-heartbeat.sh disable 1 100
./update-broker-ocp.sh --rotate-status-key
./demo-preflight.sh --site ocp 1 100
./demo-urls.sh --site ocp
```

Prometheus setup (ServiceMonitor, NetworkPolicy, plugin) is handled by
`audience-reset.sh`. The MaaS chain and per-seat keys survive a reset — only
re-run Phase 2 if you rebuilt the cluster.

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

## E — Multi-Cluster Setup (2+ Clusters) — SECONDARY

> **Secondary path.** The default is a single ROSA HCP cluster sized to the
> seat count (see *Reference architecture*). Use multiple clusters only when
> one cluster cannot hold the seats you need.
>
> **The RHOAI story does not span clusters.** RHOAI, MaaS-over-MaaS, the MCP
> catalog and the MLflow trace view are all per-cluster. So with 2+ clusters
> you must either:
>
> - stand up RHOAI **and** the full MaaS-over-MaaS chain on *each* cluster —
>   Phase 1 and Phase 2 of Section A, per cluster, each with its own upstream
>   key and its own published model; or
> - accept that the RHOAI-native parts of the demo are **not available**, and
>   run the seats against a shared external model endpoint instead.
>
> There is no cross-cluster MaaS gateway, and the dashboard's model, MCP and
> trace views only ever show the cluster you are logged into. Decide which of
> the two you are doing before you build the second cluster.

The existing session broker stays on the original cluster. Each new cluster
gets its own operator, observability services, and its own seats. The broker
then combines their audience routes into one pool; do not run
`deploy-broker-ocp.sh` on the new cluster.

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

## H — AWS path: S3, Route 53, ELB — OPTIONAL

> **Optional path.** The default build needs no AWS account: Loki stores logs
> in in-cluster ODF object storage (`LOKI_OBJECT_STORE=odf`), and the broker is
> a Route on the cluster. Use this section only if you already have the AWS
> estate and specifically want S3-backed logging, the `yougetaclaw.com` domain,
> or CloudWatch trace forwarding. Nothing in the demo requires it.

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
| `extend-cluster.sh` | Create the seat namespaces on a bare cluster (no RHDP provisioning) |
| `mirror-fantaco-images.sh` | Mirror the six Docker Hub images into the cluster registry — required above ~60 seats |
| `deploy-observability.sh` | Loki + Grafana + MLflow in one step, plus the MaaS PodMonitor mirror |
| `maas-bootstrap.sh` | The five MaaS platform prerequisites (`--check` to report only) |
| `maas-publish-model.sh` | Publish the upstream RHDP model through this cluster's MaaS (`--check`, `--render`) |
| `maas-mint-seat-keys.sh` | Mint one distinct MaaS key per seat (`--smoke-test`, `--apply`, `--verify`, `--revoke`) |
| `deploy-mcp-catalog.sh` | MCP catalog + Kuadrant broker (`--check`, `--catalog-only`, `--remove`) |
| `manage-heartbeat.sh` | Muzzle the per-seat heartbeat (`status` reports whether it is really firing) |
| `demo-preflight.sh` | Pass/fail health checks across all namespaces/clusters |
| `demo-urls.sh` | Stage-ready URLs, QR code, observability links, provider info |
| `deploy-broker-ocp.sh` | One-time: build + deploy session broker on OpenShift (no AWS needed) |
| `update-broker-ocp.sh` | Inject routes into OCP broker, print share URL |
| `update-broker.sh` | Upload routes to S3 broker at yougetaclaw.com (requires AWS) |
| `set-audience-origins.sh` | Make the Control UI accept the broker's audience host (Section G) |
| `repair-gateway.sh` | Repair gateways that cannot boot, without wiping the PVC (Section G) |
| `../.env` | `MAAS_UPSTREAM_API_KEY` (required), image pin, Langfuse/GCP keys, broker config |
| `clusters.csv` | Multi-cluster config — one `cluster_id,kubeconfig_path` per line (copy from `.example`) |
| `.state/langfuse.env` | Auto-populated by `deploy-traces-langfuse.sh` |
| `.state/logging.env` | Auto-populated by `deploy-logs-loki.sh` |
| `.state/<guid>/broker.env` | Per-cluster broker state (audience code, status key) |
| `claw_plugins/langfuse-tracer/` | Custom Langfuse plugin (injected by audience-reset.sh) |
| `test_prompts.md` | Demo prompts with expected behaviors |
| `E2E_MCP_TRACING.md` | Research: distributed tracing through MCP servers |
