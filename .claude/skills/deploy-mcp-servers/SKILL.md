---
name: deploy-mcp-servers
description: Deploy FantaCo MCP servers to OpenShift using raw Kubernetes manifests
argument-hint: "[all | customer | finance | product | sales-order | sales-policy-search | hr-policy]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Deploy FantaCo MCP Servers

Deploy one or more FantaCo MCP servers to the current OpenShift namespace. Each MCP server is a FastMCP Python service that provides tool-based access to a backend microservice.

## Prerequisites

The backend microservices must already be running. If not, run `/deploy-backends` first.

## Available MCP Servers

| Key          | Directory (under fantaco-mcp-servers/) | Port | Backend Dependency              |
|--------------|----------------------------------------|------|---------------------------------|
| customer     | customer-mcp-kubernetes                | 9001 | fantaco-customer-service:8081   |
| finance      | finance-mcp-kubernetes                 | 9002 | fantaco-finance-service:8082    |
| product      | product-mcp-kubernetes                 | 9003 | fantaco-product-service:8083    |
| sales-order  | sales-order-mcp-kubernetes             | 9004 | fantaco-sales-order-service:8084|
| sales-policy-search | sales-policy-search-mcp-kubernetes | 9006 | fantaco-sales-policy-search-service:8090 |
| hr-policy  | hr-policy-mcp-kubernetes             | 9007 | fantaco-hr-policy-search-service:8091 |

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

Report the current user and namespace to the user.

## Step 2: Determine which MCP servers to deploy

Parse `$ARGUMENTS`:

- If `$ARGUMENTS` is empty or `all` — deploy all 6 MCP servers
- If `$ARGUMENTS` contains one or more keys (space-separated) — deploy only those
- Valid keys: `customer`, `finance`, `product`, `sales-order`, `sales-policy-search`, `hr-policy`
- If an invalid key is provided, report the error and list valid keys

Map keys to Kubernetes manifest directories:
- `customer` → `fantaco-mcp-servers/customer-mcp-kubernetes`
- `finance` → `fantaco-mcp-servers/finance-mcp-kubernetes`
- `product` → `fantaco-mcp-servers/product-mcp-kubernetes`
- `sales-order` → `fantaco-mcp-servers/sales-order-mcp-kubernetes`
- `sales-policy-search` → `fantaco-mcp-servers/sales-policy-search-mcp-kubernetes`
- `hr-policy` → `fantaco-mcp-servers/hr-policy-mcp-kubernetes`

## Step 3: Verify backend services are running

For each selected MCP server, check that its backend service exists:

```bash
oc get svc fantaco-customer-service    # for customer
oc get svc fantaco-finance-service     # for finance
oc get svc fantaco-product-service     # for product
oc get svc fantaco-sales-order-service # for sales-order
oc get svc fantaco-sales-policy-search-service # for sales-policy-search
oc get svc fantaco-hr-policy-search-service # for hr-policy
```

Only check services for the selected MCP servers. If a backend service is missing, warn the user and ask whether to continue or abort.

## Step 4: Deploy MCP servers

For each selected MCP server, first check if the deployment already exists:

```bash
oc get deployment mcp-<server> -o name 2>/dev/null
```

Then apply all three Kubernetes manifests from its directory:

```bash
cd fantaco-mcp-servers/<server>-mcp-kubernetes
oc apply -f mcp-server-deployment.yaml
oc apply -f mcp-server-service.yaml
oc apply -f mcp-server-route.yaml
```

**Only if the deployment already existed before the apply**, restart the pod to pick up config changes:

```bash
oc delete pod -l app=mcp-<server> --ignore-not-found
```

Do NOT delete the pod on a fresh first-time deploy — `oc apply` already creates a new pod and deleting it just wastes time.

Where `<server>` is: `customer`, `finance`, `product`, `sales-order`, `sales-policy-search`, or `hr-policy`.

## Step 5: Wait and verify pods

Wait 15 seconds, then check MCP pod status:

```bash
oc get pods -l 'app in (mcp-customer,mcp-finance,mcp-product,mcp-sales-order,mcp-sales-policy-search,mcp-hr-policy)'
```

Only check pods for the selected MCP servers. For any pod not in Running/Ready state, show the last 20 lines of logs:

```bash
oc logs deployment/mcp-<server> --tail=20
```

## Step 6: Display routes

Show the routes for all deployed MCP servers:

```bash
oc get routes -o custom-columns="NAME:.metadata.name,URL:.spec.host" | grep mcp
```

Present a summary table with `https://` prefixed URLs. Remind the user that the MCP endpoint path is `/mcp` (e.g. `https://<route-host>/mcp`).

## Step 7: Smoke test

For each deployed MCP server, send a JSON-RPC initialize request to verify the server is responding:

```bash
ROUTE_HOST=$(oc get route mcp-<server>-route -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w "%{http_code}" \
  -X POST "https://${ROUTE_HOST}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}'
```

Route names:
- `mcp-customer-route`
- `mcp-finance-route`
- `mcp-product-route`
- `mcp-sales-order-route`
- `mcp-sales-policy-search-route`
- `mcp-hr-policy-route`

Expected: HTTP 200. Present results as a summary table:

| MCP Server   | Port | Init | Route URL |
|--------------|------|------|-----------|
| customer     | 9001 | PASS | https://... |
| finance      | 9002 | PASS | https://... |
| product      | 9003 | PASS | https://... |
| sales-order  | 9004 | PASS | https://... |
| sales-policy-search | 9006 | PASS | https://... |
| hr-policy    | 9007 | PASS | https://... |
