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
2. **Docker Hub will not serve 100 namespaces.** The anonymous pull limit is hit
   around seat 62 and presents as a broken demo, not a quota error. Run
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

## Known-not-working (cosmetic, safe to ignore)

- **MCP catalog** in the dashboard: needs an MCP gateway instance, not just the
  operator. Not used by the demo.
- **Observe & monitor → Usage**: renders but shows zeros. The MaaS PodMonitors
  are `monitoring.coreos.com`, while the dashboard's Prometheus discovers
  `monitoring.rhobs` — so no MaaS metrics reach it. Use Grafana instead.
- If dashboards vanish entirely with "No dashboards were found", Perses has
  corrupted its own project file: delete
  `/perses/projects/<ns>.yaml` inside the Perses pod and restart it.

## Order of operations, start to finish

```bash
./mirror-fantaco-images.sh                     # BEFORE audience-reset
./extend-cluster.sh 100                        # bare cluster only
./deploy-observability.sh                      # Loki + Grafana + MLflow
./maas-bootstrap.sh                            # five prerequisites, see script
./1-deploy-claw.sh --create-only 1 100
./audience-reset.sh --site ocp 1 100           # long; verify it exits 0
./6-inject-enterprise-skills.sh 1 100
./manage-heartbeat.sh disable 1 100            # cleaner traces, no idle spend
./deploy-broker-ocp.sh
./update-broker-ocp.sh --rotate-status-key     # prints audience + status URLs
./demo-preflight.sh 1 100                      # expect 18/18 per seat
```

Verify by counting, never by exit code. Several steps here report success while
having done nothing — that is how 100 seats ended up with invisible skills.
