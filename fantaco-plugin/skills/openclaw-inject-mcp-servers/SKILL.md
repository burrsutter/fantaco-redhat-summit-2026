---
name: openclaw-inject-mcp-servers
description: Inject MCP server entries into a running OpenClaw deployment config
argument-hint: "[server-key or 'all']"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Inject MCP Servers into OpenClaw Config

Register MCP servers directly in the `openclaw-config` ConfigMap so the OpenClaw gateway can reach FantaCo MCP services via in-cluster URLs (streamable-http transport).

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

Report the current user and namespace to the user.

## Step 2: Find OpenClaw pod

Verify OpenClaw is running:

```bash
oc get pods -l app=openclaw -o name
```

If no running OpenClaw pods are found, stop with an error: "No running OpenClaw pods found. Deploy OpenClaw first with `/fantaco:deploy-openclaw`."

Save the pod name — it will be used later for verification curls.

## Step 3: Discover MCP services

Find all services matching the `mcp-*-service` naming convention:

```bash
oc get svc -o json
```

Parse the JSON output to find services whose name matches the regex `^mcp-(.+)-service$`. For each matching service, extract:
- **server_key**: the captured group (e.g., `customer`, `finance`, `sales-order`)
- **service_name**: the full service name (e.g., `mcp-customer-service`)
- **port**: the first port number from the service spec
- **direct_url**: `http://<service_name>:<port>/mcp`

If no MCP services are found, stop with an error: "No MCP services found in the current namespace."

Display the discovered MCP services in a table.

## Step 4: Select which MCP servers to inject

Determine which servers to inject based on `$ARGUMENTS`:

- If `$ARGUMENTS` is `all` or empty/not provided → inject **all** discovered MCP servers
- If `$ARGUMENTS` matches a specific server key (e.g., `customer`) → inject only that one
- Otherwise, use `AskUserQuestion` with `multiSelect: true` to let the user pick which MCP servers to inject. List each discovered server as an option with its service name and URL.

For each selected server, the in-cluster URL will be: `http://<service_name>.<namespace>.svc.cluster.local:<port>/mcp`

## Step 5: Check NetworkPolicy

Verify the OpenClaw egress NetworkPolicy allows in-cluster traffic:

```bash
oc get networkpolicy openclaw-egress -o json
```

Check if the egress rules allow traffic to MCP services (either allow-all `[{}]` or a `podSelector: {}` rule). If yes, report "NetworkPolicy already allows egress — no patch needed." and move on.

If egress is restricted and doesn't allow in-cluster traffic, patch it:

```bash
oc patch networkpolicy openclaw-egress --type=json \
  -p '[{"op":"add","path":"/spec/egress/-","value":{"to":[{"podSelector":{}}]}}]'
```

## Step 6: Inject MCP servers into OpenClaw ConfigMap

Get the current `openclaw-config` ConfigMap and add MCP server entries under `mcp.servers`:

```bash
oc get configmap openclaw-config -o jsonpath='{.data.openclaw\.json}'
```

For each selected MCP server, check if an entry with that key already exists in `mcp.servers`. If it does, report it's already configured and skip it.

If not, add an entry:

```json
{
  "<server_key>": {
    "transport": "streamable-http",
    "url": "http://<service_name>.<namespace>.svc.cluster.local:<port>/mcp"
  }
}
```

The URL must use the fully-qualified in-cluster hostname (`<service_name>.<namespace>.svc.cluster.local`) for reliable DNS resolution.

Apply the patched config:

```bash
oc patch configmap openclaw-config --type merge -p '{"data":{"openclaw.json":"<escaped-json>"}}'
```

Report which servers were added and which were already present.

## Step 7: Restart OpenClaw pod

Delete the OpenClaw pod so the deployment controller creates a new one with the updated config (the init container copies the ConfigMap to the PVC on startup):

```bash
oc delete pod -l app=openclaw
oc rollout status deployment/openclaw --timeout=120s
```

Report when OpenClaw is ready.

## Step 8: Verify and report

For each injected MCP server, run a test curl from the OpenClaw pod to verify connectivity:

```bash
oc exec deployment/openclaw -c gateway -- curl -s -o /dev/null -w "%{http_code}" \
  --connect-timeout 5 --max-time 10 \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
  http://<service_name>:<port>/mcp
```

Report a summary table:

| MCP Server | URL | Status |
|------------|-----|--------|
| customer | `http://mcp-customer-service:9001/mcp` | 200 OK |
| finance | `http://mcp-finance-service:9002/mcp` | 200 OK |
| ... | ... | ... |

If any server returns a non-200 status, flag it as a warning but do not fail — the backend service may still be starting up or the MCP pod may not be deployed yet.

Tell the user: "MCP injection complete. Run `/fantaco:list-mcp-servers` to see all MCP services and proxy wiring."
