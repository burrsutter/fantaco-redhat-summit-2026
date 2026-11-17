#!/usr/bin/env python3
"""
preview5: cut the null-preview noise out of the MLflow Traces list.

Input : a preview4-patched diagnostics-otel bundle (index.js, 2448051 bytes)
Output: a preview5 bundle

Background
----------
preview4 made real conversation traces show their prompt (verified on
rosa-tztnl during Darmstadt: openclaw.harness.run 89/89 and
openclaw.message.processed 78/79 have a request_preview).

But 58% of the rows in the Traces list are single-span, prompt-less traces
that MLflow renders as the literal text "null", because trace_info.
request_preview is SQL NULL:

    root span                    traces   with_preview
    openclaw.model.usage            164              0
    openclaw.exec                    61              0
    openclaw.liveness.warning         6              0
    openclaw.memory.pressure          1              0

These are orphans: each is emitted with
`parentContext: activeTrustedParentContext(evt, metadata)`, that helper
returns undefined for these events, and `spanWithDuration` then calls
`tracer.startSpan(name, {...}, undefined)` which falls back to
`context.active()` == root => a brand new trace ID per telemetry event.

Two independent changes, separately flagged.
"""

import argparse
import hashlib
import pathlib
import sys

PREVIEW4_SHA256 = "b32a758f5728cc34290892fc78ce10ee521a4706a81dc7d33073e381c759fdee"

# --------------------------------------------------------------------------
# Change 1 -- flag block, appended next to preview4's existing flags.
# --------------------------------------------------------------------------
FLAG_ANCHOR = 'const __MLFLOW_SUPPRESS_DIAGNOSTIC_PHASE = true;'

FLAG_BLOCK = FLAG_ANCHOR + '''
// --- preview5 ---------------------------------------------------------
// Drop metric-free telemetry spans that MLflow lists as "null" rows.
// SAFE: in all three record functions below, every counter/histogram is
// recorded ABOVE the `if (!tracesEnabled) return;` guard we hook into, so
// suppressing the span loses no metric.
const __MLFLOW_SUPPRESS_NOISE_SPANS = true;
// openclaw.model.usage is NOT metric-free on the MLflow side: it is the sole
// carrier of mlflow.trace.tokenUsage and the input/output/total_tokens trace
// metrics (164/164 of them). So prefer re-parenting it into the conversation
// trace over dropping it. Modes:
//   "off"             - preview4 behaviour, unchanged
//   "reparent"        - widened parent lookup, span always emitted. Cannot
//                       lose data; removes null rows only insofar as the
//                       widened lookup actually resolves a parent. (default)
//   "reparent-or-drop"- widened parent lookup, and drop the span if it is
//                       STILL orphaned. Guarantees the null rows disappear.
//                       Costs MLflow token accounting only for those calls
//                       that could not be parented; Prometheus token
//                       counters are recorded earlier and always survive.
// DEFAULT IS "suppress", decided 2026-11-17 after measuring preview6 on a
// live fleet. "reparent-or-drop" DOES NOT WORK for this span, because
// activeInternalOrTrustedContext resolves a DANGLING parent: the returned
// spanContext refers to a span that is never exported. Measured directly —
// the emitted model.usage span carries a parent_span_id whose target does not
// exist (`parent_span_exists = 0`), so it lands in its own rootless trace,
// MLflow finds no root, and the row still reads "null". A parent being found
// is therefore not evidence the span will be nested, and the "-or-drop" guard
// never fires because the dangling context is truthy.
//
// Older reasoning, still valid for why dropping is safe:
//   - openclaw.model.usage parented 0 times out of 401 traces under preview4,
//     so assuming the widened lookup will resolve is not safe;
//   - the ONLY consumer of token/cost numbers is extract-metrics.sh, and it
//     queries Thanos/Prometheus, NOT MLflow. The Prometheus counters
//     (tokensCounter, costCounter, durationHistogram) are all recorded ABOVE
//     the `if (!tracesEnabled) return;` guard, so they survive regardless.
// So dropping an orphan costs nothing anyone reads, and guarantees the Traces
// list has no "null" rows. If the widened lookup DOES resolve, the span is
// kept as a child and MLflow token accounting is preserved too — strictly
// better. Either way the user-visible requirement ("no null in MLflow") holds.
const __MLFLOW_MODEL_USAGE_MODE = "suppress";
// ----------------------------------------------------------------------'''

# --------------------------------------------------------------------------
# Change 2 -- suppress the three metric-free noise spans.
#
# Each entry hooks the existing `if (!tracesEnabled) return;` guard, anchored
# on the last metric recorded immediately before it so the match is unique.
# --------------------------------------------------------------------------
GUARD = 'if (!tracesEnabled) return;'
NEW_GUARD = 'if (!tracesEnabled || __MLFLOW_SUPPRESS_NOISE_SPANS) return;'

NOISE_SPANS = [
    ('openclaw.memory.pressure',
     '\t\t\t\trecordMemoryUsageMetrics(evt, attrs);\n\t\t\t\t' + GUARD),
    ('openclaw.exec',
     '\t\t\t\texecProcessDurationHistogram.record(evt.durationMs, attrs);\n\t\t\t\t' + GUARD),
    ('openclaw.liveness.warning',
     'livenessCpuCoreRatioHistogram.record(evt.cpuCoreRatio, attrs);\n\t\t\t\t' + GUARD),
]

# --------------------------------------------------------------------------
# Change 3 -- openclaw.model.usage: re-parent, or optionally suppress.
#
# activeTrustedParentContext() requires metadata.trusted AND a
# traceContext.parentSpanId. activeInternalOrTrustedContext() also accepts
# metadata.internal, tries spanId before parentSpanId, and falls back to
# internalOrTrustedParentContext(). Both are already defined in this closure,
# above the call site (index.js:61515-61555 vs :61705).
# --------------------------------------------------------------------------
USAGE_OLD = '''\t\t\t\tspanWithDuration("openclaw.model.usage", spanAttrs, evt.durationMs, {
\t\t\t\t\tparentContext: activeTrustedParentContext(evt, metadata),
\t\t\t\t\tendTimeMs: evt.ts
\t\t\t\t}).end(evt.ts);'''

USAGE_NEW = '''\t\t\t\tif (__MLFLOW_MODEL_USAGE_MODE !== "suppress") {
\t\t\t\t\tconst __mlflowUsageWiden = __MLFLOW_MODEL_USAGE_MODE === "reparent" || __MLFLOW_MODEL_USAGE_MODE === "reparent-or-drop";
\t\t\t\t\tconst __mlflowUsageParent = __mlflowUsageWiden
\t\t\t\t\t\t? activeTrustedParentContext(evt, metadata) ?? activeInternalOrTrustedContext(evt, metadata)
\t\t\t\t\t\t: activeTrustedParentContext(evt, metadata);
\t\t\t\t\tif (__mlflowUsageParent || __MLFLOW_MODEL_USAGE_MODE !== "reparent-or-drop") spanWithDuration("openclaw.model.usage", spanAttrs, evt.durationMs, {
\t\t\t\t\t\tparentContext: __mlflowUsageParent,
\t\t\t\t\t\tendTimeMs: evt.ts
\t\t\t\t\t}).end(evt.ts);
\t\t\t\t}'''


def sub_once(src: str, old: str, new: str, label: str) -> str:
    n = src.count(old)
    if n != 1:
        sys.exit(f"ERROR: anchor for [{label}] matched {n} times, expected 1. "
                 f"Input is probably not a preview4 bundle.")
    print(f"  patched: {label}")
    return src.replace(old, new, 1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=pathlib.Path, help="preview4 index.js")
    ap.add_argument("dst", type=pathlib.Path, help="preview5 index.js to write")
    ap.add_argument("--force", action="store_true",
                    help="skip the preview4 checksum check")
    args = ap.parse_args()

    src = args.src.read_text(encoding="utf-8")
    digest = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if digest != PREVIEW4_SHA256 and not args.force:
        sys.exit(f"ERROR: input sha256 {digest}\n"
                 f"       expected      {PREVIEW4_SHA256} (preview4)\n"
                 f"       re-run with --force if you know what you are doing.")

    print(f"preview5: patching {args.src} ({len(src)} bytes)")
    src = sub_once(src, FLAG_ANCHOR, FLAG_BLOCK, "flag block")
    for name, anchor in NOISE_SPANS:
        src = sub_once(src, anchor, anchor.replace(GUARD, NEW_GUARD),
                       f"suppress {name}")
    src = sub_once(src, USAGE_OLD, USAGE_NEW, "re-parent openclaw.model.usage")

    args.dst.write_text(src, encoding="utf-8")
    out = hashlib.sha256(src.encode("utf-8")).hexdigest()
    print(f"preview5: wrote {args.dst} ({len(src)} bytes)\n  sha256 {out}")
    print("\nNow syntax-check it:\n  node --check " + str(args.dst))


if __name__ == "__main__":
    main()
