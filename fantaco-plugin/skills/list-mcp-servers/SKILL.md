---
name: list-mcp-servers
description: List MCP services in the current OpenShift namespace with direct URLs and OpenClaw proxy status
argument-hint: "[--json]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# List MCP Servers

Summarize every `mcp-*-service` in the current namespace: service name, port, in-cluster MCP URL, and whether `openclaw-proxy-config` already defines a matching nginx location. Run this **right after** `/fantaco:deploy-mcp-servers` (or after Helm MCP install) and again after `/fantaco:openclaw-inject-mcp-servers` if you use the proxy.

Implementation lives in `scripts/list-mcp-servers.sh` (run from the repository root).

## Step 1: Verify OpenShift connectivity

```bash
oc whoami
oc project -q
```

**Stop** if not logged in or no project is selected.

## Step 2: Run the list script from the repository root

From the FantaCo repo root:

```bash
./scripts/list-mcp-servers.sh
```

If `$ARGUMENTS` contains `--json` or `-j`, use machine-readable output:

```bash
./scripts/list-mcp-servers.sh --json
```

If the script is not found, `cd` to the workspace root that contains this repository first, then retry.

## Step 3: Interpret and report

- **Table / direct URLs:** Each MCP is reachable inside the cluster at `http://mcp-<key>-service:<port>/mcp`.
- **Proxy column:** A check mark means `openclaw-proxy-config` includes `location /mcp-<key>/`; cross means run `/fantaco:openclaw-inject-mcp-servers` (or re-run it) before OpenClaw can reach that MCP through the proxy.
- If no MCP services are found, say the namespace may not have MCP deployments yet.

Remind the user: external clients and the OpenClaw dashboard typically use **HTTPS routes** (`https://<route-host>/mcp`); this script focuses on in-cluster URLs and proxy wiring.
