# Handoff — running the OpenClaw on OpenShift demo

Written 2026-11-16 for Developer Day Darmstadt (17 Nov), from a cluster built
from scratch that day. Applies to any self-built ROSA cluster; RHDP-provisioned
clusters differ (see "Why a fresh cluster is different").

**This file contains no URLs, keys or passwords.** They live in a per-event file
(`<event>-<date>.md`, mode 600) that is gitignored because it embeds the broker
presenter key. Get it from whoever built the cluster — the repo alone is not
enough to run the demo.

## What you need before the event

| Item | Where from |
| --- | --- |
| Audience URL + audience code | per-event links file |
| Broker status-board URL (presenter key) | per-event links file |
| `oc login` for the cluster | per-event links file |
| Cluster kubeconfig (for the contest script) | your own `oc login` is enough |

## Running the skill contest

```bash
oc login <api-url> --username cluster-admin --password '<pw>'
./skill-contest.sh --full --exclude 1,2
```

- The seat range is **discovered from the cluster** — do not pass `1 50`. It used
  to default to 1-50 and silently swept half a 100-seat room, nearly crowning the
  wrong winner. The banner prints `(discovered)` or `(explicit)`; check it.
- `--full` dumps the SKILL.md bodies. Use it for real judging: descriptions alone
  flatter well-described skills and punish good terse ones.
- `--exclude 1,2` skips presenter/staff seats. Adjust to whatever you used.
- Output lands in `.state/<cluster-guid>/contest/<timestamp>/`.
- **The script only collects APPLIED skills.** Pending proposals live at
  `/home/node/.openclaw/skill-workshop/proposals/<id>/PROPOSAL.md` and are
  invisible to it. On one past run there were 211 proposals from 51 users versus
  136 applied skills from 42 — check proposals by hand before announcing.
- Judge offstage, announce fast. Running the sweep live reads badly.

Past results are in `contest-history/`; add yours as
`YYYY-MM-DD-<what>.txt` once the winner is announced.

## If something breaks on stage

**Seats look dead / `oc` says `no such host` while the web console works.**
It is the macOS resolver, not the cluster. The API hostname specifically gets a
stuck negative cache entry under heavy parallel `oc` load.

```bash
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

If it recurs, pin the API in `/etc/hosts` (the per-event file lists the IPs).
Remove the pin after the event, and remove any pin from a previous cluster.

**One seat is broken.** Re-run preflight for just that seat:
`./demo-preflight.sh <n>`. If its gateway is cycling, it is usually transient
contention — give it two minutes before intervening.

**Attendee says a skill is missing.** Verify what the *agent* can see, not what
is on disk. The file being present proves nothing:

```bash
oc exec deployment/instance -n agentic-user<N> -c gateway -- \
  node /app/dist/index.js --no-color agent --session-id check \
  --message "List the names of the skills you can use." --json
```

Re-inject with `./6-inject-enterprise-skills.sh <n> <n>` (separate arguments —
under zsh an unquoted `$range` does not word-split and the script silently falls
back to student mode).

## Why a fresh cluster is different

Two assumptions from RHDP-provisioned clusters do not hold:

1. **Seats are not pre-provisioned.** `extend-cluster.sh <count>` bootstraps from
   zero.
2. **A public registry will not serve 100 namespaces well.** The six images now
   come from `quay.io/openclawopenshift`; they used to come from Docker Hub,
   whose anonymous pull limit was hit around seat 62 and presented as a broken
   demo rather than a quota error. Quay has no equivalent limit, but mirroring
   still turns 600 public pulls into six. Run
   `./mirror-fantaco-images.sh` **before** `audience-reset.sh` — the image prefix
   is read once at startup, not per seat, so mirroring mid-run has no effect.

Also: per-seat namespace quotas (8 CPU / 10Gi) mean a Gen AI Studio playground
(12Gi) cannot fit inside a seat. Use a separate project, or raise that seat's
quota.

## Model access

Seats call **this cluster's** MaaS gateway, which re-publishes an external MaaS
model. Each seat holds its own cluster-issued `sk-oai-…` key, so no attendee can
read the token other attendees use.

Rotating the upstream provider key is transparent to the seats — patch the
`api-key` in the provider secret and nothing else changes, no restart needed.
**Keep the label `inference.llm-d.ai/ipp-managed=true` on that secret.** Without
it every resource still reports Ready and only real inference fails, with
`authType 'apikey' credentials not found`.

The subscription token limit is **fleet-wide**, not per seat, because all seats
share one MaaS identity. Size it accordingly.

## The heartbeat: why it kept coming back

**A MISSING `HEARTBEAT.md` turns the heartbeat ON.** This is inverted from
every reasonable guess, and it is why the heartbeat returned after every reset.

```
workspace/HEARTBEAT.md present, comments only -> "skipped: empty-heartbeat-file", no LLM call
workspace/HEARTBEAT.md ABSENT                 -> built-in default prompt, fires every 30 min
                                                 at ~40k tokens a poll, per seat
```

Measured on rosa-tztnl 2026-11-17: 8 of 8 seats correlated exactly.

The loop that kept re-arming it:

1. `audience-reset.sh` **deleted** `HEARTBEAT.md`, on a code comment's
   assumption that "OpenClaw rescaffolds it on next start". It does not.
2. Deleting it therefore armed the heartbeat rather than clearing it.
3. `audience-reset.sh` then called `manage-heartbeat.sh disable`, but the CLI
   writes only `state/openclaw.sqlite` — which step 1's wipe had just removed,
   and which the next reset removes again.
4. `manage-heartbeat.sh status` read `agents.defaults.heartbeat` from
   `openclaw.json`. **That key is null on every seat, enabled or not** — the
   real config path is `channels.defaults.heartbeat`. So status reported
   "disabled" unconditionally and the regression was invisible.

Fixed in all four places: `audience-reset.sh`, `reset-openclaw.sh` and
`soft-reset-user-state.sh` now re-seed the comments-only template after wiping;
`manage-heartbeat.sh disable` writes the file (and `enable` removes it) rather
than relying on the CLI alone; `status` now reports ground truth from
`system heartbeat last`. `demo-preflight.sh` check 17 asserts the file is
present and comments-only, so a silent regression fails the preflight.

```bash
./manage-heartbeat.sh status 1 100     # FIRING vs quiet, with age of last beat
```

## Project-scoped dashboard pages

Several RHOAI pages (External models, AI asset endpoints, playground) are
scoped to a **Project** selector, and they show nothing when the wrong project
is selected — with no hint that that is why.

`extend-cluster.sh` used to create every seat with
`--display-name="Workspace"`, so all 100 seats appeared as **100 identical
"Workspace" entries** in that selector, with `models-as-a-service` lost among
them. On 2026-11-17 the External models tab looked empty for exactly this
reason; the model was Ready the whole time.

Fixed: the script now uses `--display-name="$NS"`, and the 100 existing
namespaces were backfilled, so each seat shows as `agentic-user<N>`. Check for
a regression with:

```bash
oc get ns -o json | python3 -c '
import json,sys,collections
c=collections.Counter()
for it in json.load(sys.stdin)["items"]:
    dn=(it["metadata"].get("annotations") or {}).get("openshift.io/display-name")
    if dn: c[dn]+=1
print({k:v for k,v in c.items() if v>1} or "no duplicates")'
```

**On stage: the MaaS model lives in `models-as-a-service`, not in a seat.**

## RHOAI MLflow: traces cannot go there. Do not retry the obvious way.

Probed end to end on rosa-tztnl 2026-11-17. Recording it so nobody spends the
afternoon again — the standalone MLflow in the `mlflow` namespace remains the
trace backend, and that is a deliberate decision, not an omission.

**The CR works now.** The earlier bootstrap failure was SQLite. On PostgreSQL:

- The CR **must be named literally `mlflow`** — it is a singleton, any other
  name is rejected with *"MLflow resource name must be 'mlflow'"*.
- Use `backendStoreUriFrom` (a secret ref), never inline `backendStoreUri` —
  the API rejects specs that set both.
- The operator **requires SSL on the backend store**, and OpenShift's stock
  `postgresql` image does not serve it. The migration Job fails with
  `server does not support SSL, but SSL was required`. **Appending
  `?sslmode=disable` to the URI in the secret is respected** and the migration
  completes in about 55 seconds.
- Force a re-run by deleting the Job and annotating the CR with
  `mlflow.opendatahub.io/force-migrate=<anything>`.

With that it reaches `Available=True`, v3.14.0, at
`https://mlflow.redhat-ods-applications.svc:8443/mlflow`.

**But there is no OTLP ingestion endpoint.** With a valid bearer token *and* a
valid workspace, `/mlflow/v1/traces` and `/mlflow/otlp/v1/traces` both return
`404 ENDPOINT_NOT_FOUND`. An unauthenticated probe returns 401, which looks
like the route exists — it does not; the auth gate rejects before routing.
**Do not read a 401 as evidence of a route.** The standalone MLflow 3.12
accepts OTLP at `/v1/traces` and had ingested 584 traces, so this is an RHOAI
packaging difference, not a client problem.

OpenClaw's `diagnostics-otel` posts OTLP, so it cannot target RHOAI MLflow
directly. Getting there needs either an OTLP→MLflow-API translator in front,
or OpenClaw emitting via the MLflow tracing SDK instead of OTLP — a producer
change, not a dist patch.

Also worth knowing if you do stand it up: **it is workspace-scoped.** API calls
need `X-MLflow-Workspace: <namespace>` or they fail with
`400 "Workspace context is required"`, and workspaces come from
`spec.workspaceLabelSelector`. Setting that selector makes the dashboard's
Prompts and Experiments pages workspace-aware, and any namespace not matching
it then errors with *"Workspace '<ns>' not found"* — seat namespaces are not
dashboard-labelled, so expect that unless you label them.

## Known-not-working (cosmetic, safe to ignore)

- ~~**MCP catalog** needs an MCP gateway instance~~ — **FIXED 2026-11-17** via
  `./deploy-mcp-catalog.sh`.

  **The AI hub → MCP servers nav item needs `modelregistry: Managed`.** From
  the dashboard bundle:
  ```js
  [MCP_CATALOG]: { featureFlags: ["mcpCatalog"], requiredComponents: [MODEL_REGISTRY] }
  ```
  So `mcpCatalog: true` in OdhDashboardConfig is **not sufficient** — the
  `modelregistry` component must also be `Managed` in the DataScienceCluster,
  or AI hub shows only "Models". The same rule hides AI hub → Catalog
  (`MODEL_CATALOG` has identical `requiredComponents`). Both flags were already
  `true` on rosa-tztnl and the nav was still missing purely because
  `modelregistry` was `Removed`. `deploy-mcp-catalog.sh` now asserts and fixes
  this; a **browser refresh** is needed afterwards.

  **The dashboard MCP catalog is driven by a ConfigMap, NOT by the MCP CRDs.**
  That statement above was wrong and cost real time. Gen AI studio reads
  `gen-ai-aa-mcp-servers` in `redhat-ods-applications`; until it exists the BFF
  logs `failed to get ConfigMap "gen-ai-aa-mcp-servers"` and the catalog stays
  empty no matter how many `MCPServerRegistration`s are Ready.
  - It is **platform-level** — one list cluster-wide, served regardless of the
    selected project. So in-cluster URLs must be **fully qualified**
    (`svc.cluster.local`), not bare service names.
  - **Per-namespace copies are never read.** This cluster already had a
    `gen-ai-aa-mcp-servers` in `agentic-user1` that had never done anything.
  - Schema per key: unique case-sensitive name, value is JSON with `url` and
    `description`. The BFF fills in transport and probes status itself.
  - Verify: `curl .../gen-ai/api/v1/aaa/mcps?namespace=<any>` → `"status": "healthy"`.
  - `./deploy-mcp-catalog.sh --catalog-only` does just this part.

  The script *also* stands up the separate Kuadrant MCP gateway/broker
  (`MCPGatewayExtension` + `MCPServerRegistration`), which aggregates the three
  servers behind one endpoint — verified 3/3 Ready, 23 tools,
  `healthyServers=3`. Useful, but it does **not** feed the dashboard catalog.
  Its three traps, all of which cost time:
  1. **A `ReferenceGrant` in `openshift-ingress` is mandatory** when the
     `MCPGatewayExtension` and the Gateway are in different namespaces, or the
     extension sits forever at `Ready=False / ReferenceGrantRequired`. This is
     what killed the earlier attempt — the controller log shows an extension
     created 2026-11-16 21:35:48 and deleted 21:36:52.
  2. **`spec.prefix` takes underscores, not hyphens** (`^[a-z0-9][a-z0-9_]*$`).
     `sales-order` is rejected; `sales_order` works. The HTTPRoute path can
     keep the hyphen.
  3. The MCP servers speak streamable HTTP on **`/mcp`**. A plain `GET /mcp`
     returns **406**, which means the server is UP, not broken.
- ~~**Observe & monitor → Usage** shows zeros~~ — **FIXED 2026-11-17.** The MaaS
  operator publishes its PodMonitors in `monitoring.coreos.com`; the dashboard's
  MonitoringStack Prometheus watches `monitoring.rhobs`, so nothing was scraped.
  The namespaces were never the problem (the stack's selector already allowed
  them) — only the API group. `operator-patches/maas-podmonitors-rhobs.yaml`
  mirrors the two PodMonitors into `monitoring.rhobs`; `deploy-observability.sh`
  applies it. Verify by confirming the jobs exist in the generated config:
  ```bash
  oc get secret prometheus-data-science-monitoringstack -n redhat-ods-monitoring \
    -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | grep job_name | grep maas
  ```
- If dashboards vanish entirely with "No dashboards were found", Perses has
  corrupted its own project file: delete
  `/perses/projects/<ns>.yaml` inside the Perses pod and restart it.

## Order of operations, start to finish

```bash
./mirror-fantaco-images.sh                     # BEFORE audience-reset
./extend-cluster.sh 100                        # bare cluster only
./deploy-observability.sh                      # Loki + Grafana + MLflow
./maas-bootstrap.sh                            # five prerequisites, see script
./maas-publish-model.sh                        # needs MAAS_UPSTREAM_API_KEY in .env
./maas-mint-seat-keys.sh --smoke-test          # proves inference BEFORE 100 seats
./1-deploy-claw.sh --create-only 1 100
./audience-reset.sh --site ocp 1 100           # long; verify it exits 0
./maas-mint-seat-keys.sh --apply 1 100         # per-seat keys; after namespaces exist
./6-inject-enterprise-skills.sh 1 100
./deploy-mcp-catalog.sh                        # MCP catalog entries (seat 1 as exemplar)
./deploy-genai-playground.sh                   # Gen AI Playground on the demo seat
./manage-heartbeat.sh disable 1 100            # cleaner traces, no idle spend
./deploy-broker-ocp.sh
./update-broker-ocp.sh --rotate-status-key     # prints audience + status URLs
./demo-preflight.sh 1 100                      # expect 19/19 per seat
```

Verify by counting, never by exit code. Several steps here report success while
having done nothing — that is how 100 seats ended up with invisible skills.

## MaaS over MaaS, in three steps

Put your RHDP virtual key in `.env` as `MAAS_UPSTREAM_API_KEY` before you
start — it is the one credential you must already hold. Everything downstream
is minted by the cluster.

| | What it does |
|---|---|
| `./maas-bootstrap.sh` | the five platform prerequisites. `--check` reports without changing anything. |
| `./maas-publish-model.sh` | upstream secret **+ the `ipp-managed` label**, the ExternalProvider → ExternalModel → MaaSModelRef chain, and the subscription + auth policy. `--check` to report, `--render` to print the YAML. |
| `./maas-mint-seat-keys.sh` | mints one distinct key per seat into a gitignored CSV, then hands it to `set-user-api-keys.sh`. `--smoke-test` mints one key, calls the model, and revokes it. |

Run `--smoke-test` **before** minting 100 keys. "Ready" is not evidence here:
without the `inference.llm-d.ai/ipp-managed=true` label every CR reports Ready
and only real inference fails. The smoke test is the only thing that catches it,
and it tells you the fix if it trips.

Per-seat keys are distinct *strings* sharing one subscription and one
**fleet-wide** token budget — they are minted under whoever runs the script.
The benefit is blast radius: students can read secrets in their own namespace,
so one shared token would expose everyone's. Per-seat quota would need one
OpenShift identity and group per seat.

The files in `operator-patches/` are templates (`{{MAAS_MODEL}}` etc.) rendered
from `.env`, so the scripts and the YAML cannot drift. Read them with
`./maas-publish-model.sh --render`.
