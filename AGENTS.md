# Repository Guidelines

This file created due to the use of Codex CLI

## Project Structure & Module Organization
- `fantaco-customer-main/`: Spring Boot Customer API (Java 21, Maven, PostgreSQL).
- `fantaco-finance-main/`: Spring Boot Finance API (Java 21, Maven, PostgreSQL).
- `fantaco-mcp-servers/`: Python MCP servers for customer and finance APIs.
- `helm/`: Helm charts for deploying apps and MCP servers.

## Build, Test, and Development Commands
- Customer API build/run:
  - `mvn clean package` (build JAR)
  - `mvn spring-boot:run` (run locally)
  - `java -jar target/fantaco-customer-main-1.0.0.jar`
- Finance API build/run:
  - `mvn clean package`
  - `mvn spring-boot:run` or `java -jar target/fantaco-finance-main-1.0.0.jar`
- MCP servers (examples):
  - `python fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py`
  - `python fantaco-mcp-servers/finance-mcp/finance-api-mcp-server.py`

## Coding Style & Naming Conventions
- Java: 4-space indentation, `PascalCase` classes, `camelCase` methods/fields, package names like `com.customer` or `com.fantaco.finance`.
- Python: 4-space indentation, `snake_case` functions/variables, `PascalCase` classes.
- YAML/JSON: 2-space indentation; keep keys lowercase with hyphens where possible.
- No enforced formatter in-repo; keep edits minimal and consistent with neighboring files.

## Testing Guidelines
- Java modules use Maven: `mvn test` (runs unit/integration tests when present under `src/test/java`).
- Python demo modules are typically run as scripts; add targeted tests only when adding logic with clear expected behavior.

## Commit & Pull Request Guidelines
- No formal commit convention in history; use short, imperative summaries (e.g., "add finance MCP docs").
- PRs should describe the module(s) affected, include commands run, and note any new configuration or deployment steps.

## Configuration & Secrets
- Local DB settings live in `fantaco-*/src/main/resources/application.properties`.
- Common env vars: `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`.
- RAG / model server env vars: `MODEL_BASE_URL`, `INFERENCE_MODEL`, `API_KEY`.

## Pending OpenClaw Cluster Expansion
- When the user reconnects this workspace to one or two new OpenShift clusters, carry out the OCP + ODF add-a-cluster runbook in `clawoperator-openclaw/QUICKSTART.md`, Section E. The user has already asked for the deployment and broker sync; do not stop after describing the steps.
- The existing 50-user cluster and shared `session-broker` are on GUID `jzsjx`. Each new cluster needs its own `agentic-user1` through `agentic-user50` namespaces and users, operator, Loki on ODF, Grafana, MLflow, Langfuse, OpenClaw instances, and quotas. Do not deploy another broker on a new cluster.
- The root `.env` is local and gitignored. It is configured for `SITE_NAME=ocp`, `LOKI_OBJECT_STORE=odf`, and LiteLLM model `qwen3-235b-bedrock`; verify its settings and cluster credentials before running scripts. Never copy its API token into tracked files or tool output.
- Put the existing and new GUIDs with absolute, logged-in kubeconfig paths into the gitignored `clawoperator-openclaw/clusters.csv` (see `clusters.csv.example`). After setting `KUBECONFIG` back to the broker cluster, run `update-broker-ocp.sh --rotate-status-key`, then `demo-preflight.sh --site ocp 1 50` and `demo-urls.sh --site ocp`. Do not use `--reset` when adding capacity; it wipes assignments.
- Confirm live cluster identity and prerequisites before mutations, and use the actual new GUIDs supplied by the new API hostnames. The runbook has the exact per-cluster command order and explains that broker reload preserves existing assignments.

## Skill Contest — running and judging it

Harness-neutral note: this duplicates per-user memory on purpose, so any
assistant (Claude Code, opencode, …) reaches the same verdict. Keep both in
sync if the procedure changes.

**Two pools, both required.**
`skill-contest.sh` collects only **applied** skills. `skill_workshop
action=create` files a *proposal* that becomes a skill only on explicit
approval, under `/home/node/.openclaw/skill-workshop/proposals/<id>/PROPOSAL.md`
— invisible to `skill-contest.sh`. Use `.state/collect-proposals.sh` as well.
The pending pool is routinely the larger one, and has twice contained the
winner (2026-09-29, and 2026-11-10 Red Hat Summit).

**Both scripts have range defaults that are wrong for a large event.**
`skill-contest.sh` hardcodes `RANGE_START=1 / RANGE_END=50` despite its usage
text claiming "all agentic-user*", and reports the partial sweep as complete.
`collect-proposals.sh` defaults to 240. Always pass the real range.

For a 180-seat event, run the wrapper that pins both:

```bash
.state/<cluster-guid>/contest-collect-all.sh      # ~5 min at 180 seats
```

**Rubric** (carried from the July 2026 judging, see
`clawoperator-openclaw/contest-history/README.md`): CREATIVE, USEFUL,
DATA-DRIVEN, COMPLETE. Judge from SKILL.md **bodies**, not descriptions —
descriptions flatter whoever writes good copy. `user1` is staff and is excluded
by default. Volume is a tiebreak only. Winners have consistently imported a
pattern from *outside* enterprise software; repeated themes (account briefing,
360 customer view, sales summary) are common and have never won. Check
`contest-history/*.txt` so a past winner's idea is not re-awarded.

**Announcing.** Judge offstage and write the verdict into
`.state/<cluster-guid>/elect-winner.sh`, which prints a pre-baked banner in
about a second with only a short, fallback-guarded call for the live seat
count. The on-stage request must never trigger a fleet scan.

Developer Day Stockholm 2026 result and full reasoning:
`clawoperator-openclaw/.state/rosa-r6wdp/contest/RANKING.md`.

### Langfuse: dropped for time-critical builds

Langfuse brings **11 pods** — web, worker, postgres, 3x clickhouse, redis,
s3/minio, 3x zookeeper (see `clawoperator-openclaw/langfuse-values.yaml`). That
is one seat's worth of capacity, so it is not a resource decision; it is a risk
decision. The 3-node ClickHouse on a 3-node ZooKeeper quorum is the slowest and
flappiest part of the stack, and `langfuse-tracer` injection is what crashlooped
9 gateways on 2026-11-05 via a half-finished `oc cp`.

For a build with under ~90 minutes of runway, skip it. MLflow carries the
prompt-preview demo. Both `audience-reset.sh` and `post-restart-repatch.sh`
gate `langfuse-tracer` on `.state/<guid>/langfuse.env` *and* the `langfuse`
route existing, so simply not running `deploy-traces-langfuse.sh` makes the
plugin injection skip cleanly — seats come up with 9 plugins instead of 10.

Re-enable by running `deploy-traces-langfuse.sh` and then
`post-restart-repatch.sh` over the fleet.

## Verify seeded skills after every audience-reset

`6-inject-enterprise-skills.sh` copies `quote-builder` into
`/home/node/.openclaw/workspace/skills/` on each seat, and the copy **silently
fails on roughly 2.5% of seats**. Measured 2026-11-11 on `rosa-7s2hf`: 5 of 200
(seats 46, 49, 50, 91, 92), on a build with zero DNS errors — so this is
injection flakiness, not a network artifact.

Nothing reports it. The seat is healthy, pods Running, metrics up, and
**`demo-preflight.sh` does not check skills at all** — it passed 3240/3240 on
2026-11-10 while the presenter's own seat had no `/quote`, which was then
discovered live on stage.

Check every seat (about 90 seconds at 200 seats, 12-wide):

```bash
seq 1 200 | xargs -P 12 -I{} bash -c '
  n={}
  r=$(oc exec -n "agentic-user$n" deploy/instance -c gateway -- \
      sh -c "ls /home/node/.openclaw/workspace/skills/quote-builder/SKILL.md 2>/dev/null | wc -l" 2>/dev/null | tr -d " \r")
  echo "$n:${r:-ERR}"' | grep -v ':1$'
```

Any line printed is a seat to repair with `./6-inject-enterprise-skills.sh <n> <n>`
(instant, no pod restart). **Re-verify after repairing** — and pass the range as
two explicit arguments: `set -- $range` does not word-split under zsh, so a
loop built that way silently sends `"46 46"` as one argument and the script
falls back to student mode while still reporting success.

General rule this is an instance of: **anything copied into a pod after
creation lands unreliably at fleet scale** — seeded skills, the npm install of
`diagnostics-prometheus` (~10% miss), the `langfuse-tracer` plugin (half-copies
crashloop the gateway). Verify each by counting cluster-side, never by exit
code.
