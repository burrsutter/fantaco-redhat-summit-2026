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

## RHOAI MLflow: deployed for prompts, but traces still cannot go there

**Deployed 2026-11-18 by `./deploy-rhoai-mlflow.sh`.** It backs Gen AI studio's
prompt registry and nothing else. The standalone MLflow in the `mlflow`
namespace remains the trace backend — that is a deliberate split, not an
omission, and the two run side by side with separate databases.

**Without the CR, "Save prompt" in the Playground fails with "Service
Unavailable".** `mlflowoperator: Managed` gives you the operator and the
`mlflow-ui` pod but *no CR*, and nothing else in the install creates one. The
symptom is in `oc logs -n redhat-ods-applications deploy/mlflow-ui`, every 30s:

```
MLflow CR auto-discovery failed, MLflow endpoints will return 503
MLflow endpoint called but MLflow is not configured  uri="/api/v1/prompts?workspace=agentic-user1"
```

```bash
./deploy-rhoai-mlflow.sh              # deploy + label seats 1..100
./deploy-rhoai-mlflow.sh --check      # report only
./deploy-rhoai-mlflow.sh --smoke-test # create, list and delete a real prompt
```

It gives RHOAI MLflow **its own PostgreSQL** (`rhoai-mlflow-db` in
`redhat-ods-applications`) precisely so the trace store is never touched.

**Seats must be labelled or saving still fails**, with
`Workspace '<ns>' not found`. The script applies
`mlflow.opendatahub.io/workspace=true` to each seat. A dedicated label is used
rather than `opendatahub.io/dashboard` so that labelling 100 namespaces does not
also turn them all into RHOAI Data Science Projects. Verified behaviour:

| request | result |
|---|---|
| labelled namespace + `X-MLflow-Workspace` | 200 |
| unlabelled namespace | `RESOURCE_DOES_NOT_EXIST`, and the message names the selector |
| no workspace header | 400 `Workspace context is required` |

The CR details, all still true:

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

So the split stands: **prompts go to RHOAI MLflow, traces go to the standalone
one.** Do not try to consolidate them without building that translator first.

## Seat identities: there are none by default, and on ROSA HCP `oc` cannot add them

Measured on rosa-wv5l4 2026-11-18: the cluster had **two users**
(`cluster-admin`, `backplane-cluster-admin`) and an **empty `oauth/cluster`
spec**. Attendees reach their claw through the audience Route and the broker,
so they never `oc login` and no per-seat identity has ever existed. The note in
a previous cluster's state file says the same: *"no htpasswd, no `agentic-userN`
users"*.

**`0-admin-setup.sh` already binds `claw-user` to a user named
`agentic-user<N>` in every seat namespace.** Those bindings have always pointed
at identities that do not exist. They are harmless but do nothing.

Two things follow, and both surprised us:

1. **The MaaS Usage dashboard cannot attribute traffic per seat.** The `user`
   dimension records *who minted the key*, not who called. Every seat key is
   minted by whoever ran `maas-mint-seat-keys.sh`, so all 100 collapse to one
   row. Verified by driving traffic from seats 1, 2 and 3 and reading
   `authorized_hits_total`: every series came back `user="cluster-admin"`.
   `captureUser: true` does not change this — it is an identity problem.
2. **Per-seat token quota is impossible for the same reason.** One identity,
   one subscription, one fleet-wide budget.

**On ROSA HCP you cannot fix this with `oc`.** `oauth/cluster` is immutable
from inside the guest cluster; a ValidatingAdmissionPolicy rejects the write:

```
The oauths "cluster" is invalid: ValidatingAdmissionPolicy 'config' with
binding 'config-binding' denied request: This resource cannot be created,
updated, or deleted. Please ask your administrator to modify the resource in
the HostedCluster object.
```

Identity providers live on the **HostedCluster**, so they must be created with
the `rosa` CLI (or OCM) from a host that has it — the bastion — not from the
cluster. Creating an htpasswd Secret in `openshift-config` on HCP does nothing
at all; delete it rather than leaving a misleading artifact.

`./create-seat-users.sh` handles both topologies. It detects HCP via
`infrastructure/cluster .status.controlPlaneTopology == External`; on HCP it
writes the bcrypt htpasswd file to `.state/<guid>/seat-users.htpasswd` and
prints the exact `rosa create idp` command instead of failing, then applies
everything that *does* work in-cluster:

- `admin` on the seat's own namespace (namespace-scoped, seats cannot see each
  other) plus `claw-user`
- `opendatahub.io/dashboard=true` on the namespace, which is what lists the
  seat as an **AI project** in the RHOAI dashboard — no seat had this label

Passwords go to `.state/<guid>/seat-users.csv`, mode 600, and the script
refuses to run if that directory is not gitignored. They are never printed.
RoleBindings to a username work before the User object exists; users appear in
`oc get users` only after each one logs in once.

## "The model feels slow" — measured baseline, do not raise an RHDP ticket

Measured 2026-11-18 on rosa-wv5l4 against the RHDP MaaS endpoint
(`qwen3-235b-a22b`, the only model it serves). The endpoint is healthy on every
axis; the investigation is recorded so it is not repeated.

| axis | measured |
|---|---|
| tiny prompt (26 tok) round trip | 0.8 s |
| 8k prompt, 200 out | TTFT 1.7–2.0 s, total 3.6–4.4 s |
| 27k prompt, 8 out | med 3.0 s, p95 6.9 s |
| decode throughput | med 68 tok/s (60–111) |
| concurrency 1 → 20 | **no degradation**; 20 in parallel finished in 4.6 s wall |
| this cluster's MaaS gateway vs direct upstream | indistinguishable |

Concurrency flatness is the important one for a 100-seat room: RHDP batches
twenty simultaneous requests with no queueing penalty, so seats will not
contend.

A real agent turn is **two LLM round trips** (1.6–4.0 s each) plus under a
second of agent overhead — 6.1–7.4 s end to end, fully accounted for by
per-call latency at the agent's ~27k-token context. Tool/MCP time is
negligible.

**The only lever is context size, and it is ours.** Prefill dominates: 26 tok
→ 0.8 s, 8k → ~1.9 s, 27k → ~3 s. Trimming the system prompt (seeded skills and
MCP tool definitions) is the only change that would shorten turns.

Three things that produced wrong answers during this investigation:

- **Thinking is already off.** Two completion tokens for "what is 2+2", no
  `reasoning_content`. `enable_thinking: false` changes nothing and the
  `/no_think` prefix measured *slower*. Do not chase it.
- **Counting SSE chunks is not counting tokens.** The stream packs many tokens
  into one `data:` frame, which made decode look like 6.5 tok/s when it is ~68.
  Compute throughput from `usage.completion_tokens`, never from frame counts.
- **A small trace sample is all cold starts.** Four traces averaged 11.1 s and
  started this whole investigation; two of them were 45 s and 23 s first
  contacts. Steady state is ~7 s. Take at least a dozen.

Querying the standalone MLflow 3.12 for this:
`GET /api/2.0/mlflow/traces?experiment_ids=1&max_results=N` for the list, and
`GET /ajax-api/2.0/mlflow/get-trace-artifact?request_id=…` for spans. The
MLflow-3-style `POST /api/2.0/mlflow/traces/search` returns **405** here. Spans
carry no token usage, so read counts from the API response instead.

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
./enable-dashboard-features.sh                 # Gen AI studio etc — ALL default false
./deploy-rhoai-observability.sh                # Observe & monitor (needs 3 operators)
./deploy-rhoai-mlflow.sh                       # prompt registry, or Save prompt 503s
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

### Per-user attribution: use `--as-seat`

The `user` dimension in `authorized_hits_total` / `authorized_calls_total`
records **who minted the key**, not who called it. Minted the default way every
key belongs to whoever ran the script, so all 100 seats collapse into a single
`user="cluster-admin"` row in the MaaS Usage dashboard. `captureUser: true`
does not help — it is an identity problem, not a telemetry one.

`./maas-mint-seat-keys.sh --as-seat` logs in as each seat (credentials from
`.state/<guid>/seat-users.csv`, written by `create-seat-users.sh`) and mints
that seat's key as that seat. Proven on rosa-wv5l4 2026-11-18: a key minted as
`agentic-user1` reports `user="agentic-user1"` as a series distinct from
`cluster-admin`. It fails loudly if a seat login fails rather than quietly
falling back to admin, because that fallback would silently reproduce the bug.

**Two traps in this script, both of which cost real time:**

- **`--remint` used to ignore the seat range.** `--remint 1 2` revoked **49
  live keys** — whichever the 50-row search returned first, in practice seats
  52-100 — leaving them on HTTP 403 with nothing reporting it. Fixed:
  `revoke_prefix` now takes a range and the `--remint` path passes it.
  `--revoke` remains deliberately fleet-wide and warns first.
- **Do not run `demo-preflight.sh` until the fleet has settled after a key
  apply.** Run during the 100-proxy rollout it reported `20/1898 FAILED`, and
  every single failure was transient. Re-tested individually afterwards, all
  the flagged seats passed 19/19. The three symptoms, one cause:
  - `Admin URL: HTTP 000` (16 seats) — curl could not connect. This is the
    macOS resolver under parallel load, not the cluster; all returned 200
    serially after `sudo dscacheutil -flushcache && sudo killall -HUP
    mDNSResponder`. See "If something breaks on stage" above.
  - `could not read openclaw.json` (4 checks on one seat) — read while that
    seat's instance pod was restarting. The file was present the whole time.
  - `McpServersConfigured: not set` (3 seats) — the Claw CR condition was
    `True` when checked a minute later.

  Wait for `oc get pods -A | grep agentic-user | grep -v Running` to come back
  empty first, then preflight once. A preflight run during churn produces
  failures you will waste an hour chasing.
- **`set-user-api-keys.sh` is all-or-nothing, and one transient timeout blocks
  the whole fleet.** A single seat returning *"no response from endpoint"*
  aborts with *"1 of 100 token(s) failed validation. Nothing was applied."*
  That is the right default, but the key is usually fine — re-test that one
  key by hand and just re-run the apply; do not re-mint.

Per-seat keys are distinct *strings* sharing one subscription and one
**fleet-wide** token budget — unless minted with `--as-seat`.
The benefit is blast radius: students can read secrets in their own namespace,
so one shared token would expose everyone's. Per-seat quota would need one
OpenShift identity and group per seat.

The files in `operator-patches/` are templates (`{{MAAS_MODEL}}` etc.) rendered
from `.env`, so the scripts and the YAML cannot drift. Read them with
`./maas-publish-model.sh --render`.
