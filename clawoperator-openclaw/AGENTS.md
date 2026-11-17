# clawoperator-openclaw — agent orientation

This directory holds the tooling that stands up the OpenClaw-on-OpenShift demo
for an audience. It is operations, not application development: almost
everything here talks to a live cluster.

**Deliberately a pointer, not a copy.** The orientation lives in three files
and duplicating it here would guarantee drift:

| read | for |
|---|---|
| [`QUICKSTART.md`](QUICKSTART.md) | the reference architecture, cluster sizing, and **Section A: the verified order of operations**. Start here. |
| [`HANDOFF.md`](HANDOFF.md) | why each step exists — the failure mode behind it. Read before changing one. |
| [`../AGENTS.md`](../AGENTS.md) | repo-wide conventions, and the short list of traps that have each cost real time. |

## Before you run anything

- **Do not infer an install order from the script names.** Several steps report
  success while having done nothing, and two of them (`mirror-fantaco-images.sh`,
  `maas-mint-seat-keys.sh --smoke-test`) are cheap to skip and expensive to
  miss. Use QUICKSTART Section A.
- **You need an RHDP MaaS virtual key** in `../.env` as `MAAS_UPSTREAM_API_KEY`.
  It is the only credential the repo cannot provide for you.
- **Verify by counting, never by exit code.** `./demo-preflight.sh 1 <N>` is
  the arbiter and expects 19/19 per seat.

## Conventions in this directory

- Most scripts take a seat range: `./script.sh <start> <end>`. Ranges are
  inclusive and default conservatively — check the header comment rather than
  assuming they cover the whole fleet.
- The state-changing ones support `--check` (report, change nothing). Prefer it
  first: `maas-bootstrap.sh`, `maas-publish-model.sh`, `deploy-mcp-catalog.sh`,
  `manage-heartbeat.sh status`.
- `.state/` is gitignored scratch, one subdirectory per cluster GUID. It holds
  live credentials (seat API keys, broker keys) — never commit it, and never
  paste its contents anywhere.
- Script headers carry the reasoning, often with the date and cluster a
  behaviour was measured on. If you change a behaviour, update the header in
  the same edit.

## If you are about to change a script

Check whether the behaviour is also documented in `HANDOFF.md` or
`QUICKSTART.md`. A convention recorded in only one place is worse than one
recorded nowhere, because the two then disagree with equal confidence.
