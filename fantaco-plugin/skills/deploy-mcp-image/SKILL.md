---
name: deploy-mcp-image
description: Build, push, and deploy an MCP server container image to OpenShift
argument-hint: "<mcp-server-key> [customer | finance | product | sales-order | sales-policy-search | hr-policy]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Build, Push & Deploy MCP Server Image

Rebuild a FantaCo MCP server container image and deploy it to the current OpenShift cluster in one step. Handles the full cycle: build (amd64), push to Docker Hub, restart the pod, and verify the tools are live.

## MCP Server Registry

| Key                 | Source Dir (under fantaco-mcp-servers/) | Image                                          | K8s Dir                              | Pod Label        |
|---------------------|----------------------------------------|-------------------------------------------------|--------------------------------------|------------------|
| customer            | customer-mcp                           | docker.io/burrsutter/mcp-server-customer:1.0.0  | customer-mcp-kubernetes              | mcp-customer     |
| finance             | finance-mcp                            | docker.io/burrsutter/mcp-server-finance:1.0.0   | finance-mcp-kubernetes               | mcp-finance      |
| product             | product-mcp                            | docker.io/burrsutter/mcp-server-product:1.0.0   | product-mcp-kubernetes               | mcp-product      |
| sales-order         | sales-order-mcp                        | docker.io/burrsutter/mcp-server-sales-order:1.0.0| sales-order-mcp-kubernetes           | mcp-sales-order  |
| sales-policy-search | sales-policy-search-mcp                | docker.io/burrsutter/mcp-server-sales-policy-search:1.0.0 | sales-policy-search-mcp-kubernetes | mcp-sales-policy-search |
| hr-policy           | hr-policy-mcp                          | docker.io/burrsutter/mcp-server-hr-policy:1.0.0 | hr-policy-mcp-kubernetes             | mcp-hr-policy    |

## Step 1: Parse arguments

`$ARGUMENTS` should contain one MCP server key from the table above. If empty or invalid, list the valid keys and ask the user which one to deploy.

Set these variables from the table:
- `SOURCE_DIR` — path to the Python source + Dockerfile
- `IMAGE` — full Docker Hub image reference
- `POD_LABEL` — the `app=` label for the pod

## Step 2: Verify prerequisites

```bash
oc whoami && oc project -q
podman --version
```

Stop if either fails.

## Step 3: Build the image

**CRITICAL: Always use `--platform linux/amd64`.** macOS Apple Silicon builds arm64 images that crash with `Exec format error` on OpenShift.

```bash
podman build --platform linux/amd64 -t <IMAGE> fantaco-mcp-servers/<SOURCE_DIR>/
```

If the build fails, show the error and stop.

## Step 4: Push to Docker Hub

```bash
podman push <IMAGE>
```

If push fails (auth issue), suggest `podman login docker.io` and stop.

## Step 5: Restart the pod on OpenShift

The deployment uses `imagePullPolicy: Always`, so deleting the pod forces a pull of the new image:

```bash
oc delete pod -l app=<POD_LABEL> --ignore-not-found
```

Wait 15 seconds, then verify:

```bash
oc get pods -l app=<POD_LABEL>
```

If the pod is not `Running/Ready`, show the last 20 lines of logs:

```bash
oc logs deployment/<POD_LABEL> --tail=20
```

## Step 6: Smoke test — verify tools

Send a JSON-RPC `initialize` + `tools/list` to the live route and count the tools:

```bash
ROUTE_HOST=$(oc get route <POD_LABEL>-route -o jsonpath='{.spec.host}')

# Initialize to get session ID
SESSION_ID=$(curl -sD - -X POST "https://${ROUTE_HOST}/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"deploy-verify","version":"1.0"}}}' \
  | grep -i mcp-session-id | awk '{print $2}' | tr -d '\r')

# List tools
curl -s -X POST "https://${ROUTE_HOST}/mcp" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Step 7: Report

Present a summary:
- Image built and pushed: `<IMAGE>`
- Platform: `linux/amd64`
- Pod restarted: `<POD_LABEL>`
- Tools count: N tools live
- Route URL: `https://<ROUTE_HOST>/mcp`
