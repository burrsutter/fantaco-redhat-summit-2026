# preview5 / preview7 — remove the `null` rows from the MLflow Traces list

**Status: SHIPPED as `quay.io/bluesman/openclaw:2026.6.35-mlflow-preview7`
(public, linux/amd64) on 2026-11-17 after the Darmstadt event closed. It is the
default in `.env`, `.env.example`, `audience-reset.sh`, `1-deploy-claw.sh` and
`repair-gateway.sh`.**

preview5, preview6 and preview7 all come from the same `apply-preview5.py` and
differ only in `__MLFLOW_MODEL_USAGE_MODE`:

| tag | mode | outcome |
|---|---|---|
| preview5 | `reparent` | suppression works; `model.usage` still orphans |
| preview6 | `reparent-or-drop` | **failed** — dangling parent, rows still `null` |
| **preview7** | **`suppress`** | **0 null rows. Use this one.** |

Rebuild any of them by editing that one constant. See "model.usage" below for
why re-parenting cannot work.

## Verified on rosa-tztnl, 2026-11-17

A/B on identical prompts, preview4 seat vs preview5 seat:

| | preview4 (control) | preview5 |
|---|---|---|
| span types emitted | 5, incl. `openclaw.liveness.warning` | 4 |
| `liveness.warning` null row | present | **gone** |
| root-span preview coverage | 100% | 100% |

Fleet-wide after the rollout, `exec` / `liveness.warning` / `memory.pressure`
stopped appearing in new traces entirely.

**Caveat, stated plainly:** `openclaw.model.usage` only fires on
gateway-routed turns (webchat / heartbeat channel), NOT on
`node /app/dist/index.js agent --message`, which runs the embedded runner. Both
preview4 and preview5 emit zero `model.usage` spans for a CLI prompt — so the
CLI cannot be used to test it, and an absence there is a test artifact, not a
regression. The `reparent-or-drop` path has therefore **not** been observed on
a live gateway turn; it is reasoned from the code and from the preview4
measurement that `model.usage` parented 0 times in 401 traces. Re-check with
section 3 of `verify-previews.sql` after the next real demo run.

## The symptom

The MLflow Traces list shows `null` in the Request/Response columns for most
rows.

## The diagnosis

Measured read-only against the live Darmstadt cluster `rosa-tztnl`
(experiment `openclaw-traces`, 401 traces, all 100 seats on
`quay.io/bluesman/openclaw:2026.6.35-mlflow-preview4`):

| root span | traces | with preview | |
|---|---|---|---|
| `openclaw.harness.run` | 89 | 89 | 100% ✅ |
| `openclaw.message.processed` | 79 | 78 | 98.7% ✅ |
| `openclaw.model.usage` | 164 | 0 | ❌ |
| `openclaw.exec` | 61 | 0 | ❌ |
| `openclaw.liveness.warning` | 6 | 0 | ❌ |
| `openclaw.memory.pressure` | 1 | 0 | ❌ |

**preview4 is working.** Real conversation traces get their prompt. The `null`
rows are a different thing: 232 of 401 traces (58%) are *single-span,
prompt-less telemetry traces*. They have exactly one span, `parent_span_id IS
NULL`, and their own OTEL trace ID. `openclaw.exec`, for example, carries only
`exec.target`, `exec.mode`, `command_length`, `exit_code`. There is no prompt in
them to preview, so `trace_info.request_preview` is **SQL NULL**, and the
MLflow 3.12 UI renders a NULL preview as the literal string `null`.

So this is not a broken preview — it is noise drowning the list.

### Why they orphan

All four are emitted with
`parentContext: activeTrustedParentContext(evt, metadata)`, and:

```js
const trustedTraceContext = (evt, metadata) =>
    metadata.trusted ? normalizeTraceContext(evt.trace) : void 0;

const activeTrustedParentContext = (evt, metadata) => {
    const traceContext = trustedTraceContext(evt, metadata);
    const parentSpanId = traceContext?.parentSpanId;
    if (!parentSpanId) return;        // <-- bails here
    ...
};
```

When that returns `undefined`, `spanWithDuration` calls
`tracer.startSpan(name, {...}, undefined)`, OTEL falls back to
`context.active()` — root outside an async-context scope — and you get a brand
new trace ID per telemetry event.

It is specifically `activeTrustedParentContext` that is too strict: it requires
`metadata.trusted` **and** a `parentSpanId`. The sibling helper
`activeInternalOrTrustedContext` also accepts `metadata.internal`, tries
`spanId` before `parentSpanId`, and falls back to
`internalOrTrustedParentContext`.

Evidence that the call site, not the helper, is the variable: `tool.execution`
(193/193), `run` (168/168) and `context.assembled` (168/168) use the *same*
helper and parent correctly every time. `model.usage` parents **zero** times
out of 401 traces.

## The two changes

### 1. Suppress three metric-free noise spans — zero risk

`openclaw.exec`, `openclaw.liveness.warning`, `openclaw.memory.pressure`.

In each `record*` function every counter and histogram is recorded **above** the
existing `if (!tracesEnabled) return;` guard. preview5 hooks exactly that guard,
so suppressing the span provably loses no metric — `memoryPressureCounter`,
`livenessWarningCounter`, `execProcessDurationHistogram` and the event-loop
histograms all still fire. Same mechanism preview4 used for
`openclaw.diagnostic.phase`.

Removes 68 of 232 noise rows.

### 2. `openclaw.model.usage` — re-parent, do **not** reflexively suppress

This is 164 of the 232 rows, so it is tempting to add it to the suppression
list. **Don't.** It is the sole carrier of MLflow-side token accounting:

```
openclaw.model.usage | metadata:mlflow.trace.tokenUsage      | 164
openclaw.model.usage | METRIC:input_tokens/output_tokens/total_tokens | 164 each
```

Dropping the span zeroes every token and cost figure in MLflow. (Prometheus
counters survive either way — they are recorded before the trace guard.)

preview5 instead widens the parent lookup, flag-gated via
`__MLFLOW_MODEL_USAGE_MODE`:

- `"off"` — preview4 behaviour.
- `"reparent"` *(default)* — `activeTrustedParentContext(...) ??
  activeInternalOrTrustedContext(...)`, span always emitted. Cannot lose data.
- `"reparent-or-drop"` — widened lookup, and drop the span only if it is *still*
  orphaned. Guarantees the null rows go, costs token accounting only for calls
  that genuinely could not be parented.

**Decision (2026-11-17): default is `"suppress"` = preview7.**

I tried re-parenting first and it does not work. Recording the dead end so
nobody repeats it:

- preview6 shipped `"reparent-or-drop"`. On a live fleet the emitted
  `model.usage` span came out WITH a `parent_span_id` — pointing at a span
  **that is never exported**. Measured directly:
  ```
  trace_id  tr-1c0c6073…   parent_span_id 8311999a7c9bae44   parent_span_exists 0
  ```
  So the span lands in its own **rootless** trace, MLflow finds no root, and
  the row still reads `null`. Worse, the dangling context is *truthy*, so the
  `-or-drop` guard never fires.
- A/B on the identical prompt: preview6 produced 2 rootless `model.usage` null
  rows, preview7 produced **0**.
- `model.usage` had already parented 0 times in 401 traces under preview4, so
  there was never evidence the widened lookup would resolve.

Why suppressing is safe: the only consumer of token/cost figures is
`extract-metrics.sh`, and it queries **Thanos/Prometheus, not MLflow**. The
Prometheus counters (`tokensCounter`, `costCounter`, `durationHistogram`) are
all recorded *above* the `if (!tracesEnabled) return;` guard, so they survive.
What is lost is MLflow's per-trace `mlflow.trace.tokenUsage`, which nothing
reads.

Set `__MLFLOW_MODEL_USAGE_MODE` to `"reparent"` and rebuild if you would rather
keep every orphan visible in MLflow at the cost of the null rows; `"off"`
restores preview4 behaviour exactly.

Probe, section 3 of `verify-previews.sql`:

```sql
SELECT count(*) AS model_usage_spans,
       count(*) FILTER (WHERE parent_span_id IS NULL)     AS as_root,
       count(*) FILTER (WHERE parent_span_id IS NOT NULL) AS as_child
FROM spans WHERE name = 'openclaw.model.usage';
```

`as_child > 0` → the widened lookup works, done. `as_child` still 0 → escalate
to `"reparent-or-drop"`, accepting the documented trade-off.

## Build

```bash
cd .state/otel-patch
python3 -I preview5/apply-preview5.py index.js preview5/index.js
node --check preview5/index.js

cd preview5
podman build --platform linux/amd64 \
  -t quay.io/bluesman/openclaw:2026.6.35-mlflow-preview7 .
podman push quay.io/bluesman/openclaw:2026.6.35-mlflow-preview7
```

The apply script refuses to run unless the input is the exact preview4 bundle
(`sha256 b32a758f…`), so it cannot be applied twice or to a stock bundle.

Still upstream 2026.6.35 → no `meta.lastTouchedVersion` migration gate.
Keep the image **public** and **linux/amd64**.

## Roll out (after the event)

Patch the **Claw CR**, never the Deployment — the operator reconciles Deployment
edits away. A restart re-seeds `openclaw.json`, hence the repatch step; both are
already handled by the existing driver:

```bash
export PATCHED_IMAGE=quay.io/bluesman/openclaw:2026.6.35-mlflow-preview7
CONCURRENCY=4 /opt/homebrew/bin/bash .state/img-rollout-driver.sh 2 100 20
```

`img-rollout-driver.sh` now takes `START END BATCH` (default `2 100 20`) instead
of a hardcoded `RANGES=("2 20" … "141 160")`, and refuses to start if the
endpoints of the range are not real namespaces — on a 100-seat cluster the old
version silently churned through 60 that did not exist. It also requires
`PATCHED_IMAGE` to be set.

Seat 1 is excluded by design: patch it by hand first and smoke-test it before
committing the fleet.

Keep `CONCURRENCY=4`: the macOS resolver wedges above that.

## Verify

```bash
PG=$(oc get pod -n mlflow -l name=postgresql -o name | head -1 | cut -d/ -f2)
oc exec -i -n mlflow "$PG" -- \
  bash -lc 'psql -U "$POSTGRESQL_USER" -d "$POSTGRESQL_DATABASE" -f - -P pager=off' \
  < .state/otel-patch/preview5/verify-previews.sql
```

Expected afterwards: sections 1–2 show only `harness.run` /
`message.processed` roots at ~100% and `pct_null` near zero for *new* traces;
section 4 still shows token metadata and metrics; section 5 shows no new
`exec` / `liveness.warning` / `memory.pressure` spans.

Historical traces keep their NULL previews — the preview is computed at
ingestion and is not backfilled. Judge the result on traces created *after* the
rollout.

## Rollback

```bash
export PATCHED_IMAGE=quay.io/bluesman/openclaw:2026.6.35-mlflow-preview4
CONCURRENCY=4 /opt/homebrew/bin/bash .state/img-rollout-driver.sh
```

## Known leftovers

- One `message.processed` trace in 79 had a NULL preview
  (`tr-6516f14f…`, 202s, 59 spans). Known preview4 behaviour: a trace shows no
  preview until its root span closes, and a long-running harness run absorbs
  later activity. Not addressed here.
- Still no session tag (`mlflow.trace.session`), which would let the Traces view
  group by seat across namespaces. Still the main gap vs RHOAI MLflow.
- This remains a `dist` patch and **will not survive an OpenClaw version bump**.
  The real fix belongs upstream in
  `extensions/diagnostics-otel/src/service.ts` — the orphaned-telemetry-span
  behaviour is a genuine upstream bug worth filing.

---

## Rebuilding from a clean checkout

Only the generator and docs are version-controlled here. The 2.4 MB bundles
(`index.js`, `index.js.orig`) are NOT — they are derived, and live in the
gitignored `.state/otel-patch/` scratch dir on whoever's machine built them.

To rebuild the image from nothing but this directory:

```bash
# 1. extract the preview4 bundle from the published image (the patch input)
mkdir -p .state/otel-patch && cd .state/otel-patch
podman create --name p4 quay.io/bluesman/openclaw:2026.6.35-mlflow-preview4
podman cp p4:/app/dist/extensions/diagnostics-otel/index.js ./index.js
podman rm p4
shasum -a 256 index.js   # must be b32a758f5728cc34290892fc78ce10ee521a4706a81dc7d33073e381c759fdee

# 2. generate preview7 and build
cd ../..
python3 -I otel-patch/apply-preview5.py .state/otel-patch/index.js .state/otel-patch/index.js.new
node --check .state/otel-patch/index.js.new
cp .state/otel-patch/index.js.new otel-patch/index.js
podman build --platform linux/amd64 \
  -t quay.io/bluesman/openclaw:2026.6.35-mlflow-preview7 otel-patch/
rm otel-patch/index.js
```

`apply-preview5.py` refuses any input whose sha256 is not the preview4 bundle,
so a wrong or double-applied input fails loudly rather than producing a
subtly broken image.
