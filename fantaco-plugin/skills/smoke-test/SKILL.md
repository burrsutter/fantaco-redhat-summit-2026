---
name: smoke-test
description: Run smoke tests against all deployed FantaCo services on OpenShift
argument-hint: "[all | backends | mcp | openclaw]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Smoke Test FantaCo Services

Discover deployed FantaCo services via OpenShift routes and verify they are healthy.

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

Report the current user and namespace to the user.

## Step 2: Determine what to test

Parse `$ARGUMENTS`:

- If `$ARGUMENTS` is empty or `all` — test everything (backends + MCP + OpenClaw)
- `backends` — test only REST API backends
- `mcp` — test only MCP servers
- `openclaw` — test only OpenClaw
- If an invalid argument is provided, report the error and list valid options

## Step 3: Discover deployed routes

Get all routes in the current namespace:

```bash
oc get routes -o custom-columns="NAME:.metadata.name,HOST:.spec.host" --no-headers
```

Use this output to determine which services are actually deployed. Do **not** assume all services exist — only test routes that are present.

## Step 4: Test REST API backends

**Skip this step** if the user requested `mcp` or `openclaw` only.

For each of these routes **that exist** in the output from Step 3, curl the data endpoint and report the HTTP status and record count:

| Route Name | Data Path | Expected |
|---|---|---|
| fantaco-customer-service | /api/customers | JSON array |
| fantaco-finance-service | /api/finance/invoices | JSON (data array) |
| fantaco-hr-recruiting-service | /api/jobs | JSON array |
| fantaco-product-service | /api/products | JSON array |
| fantaco-sales-order-service | /api/sales-orders | JSON array |
| fantaco-hr-policy-search-service | /api/hr-policy/documents | JSON array |

For each found route, run:

```bash
ROUTE_HOST=$(oc get route <route-name> -o jsonpath='{.spec.host}')
RESPONSE=$(curl -sk -w "\n%{http_code}" "https://${ROUTE_HOST}<data-path>")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
```

- If HTTP 200, count the records. The response may be a plain JSON array or a wrapped object with a `"data"` array. Use: `echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else len(d.get('data',d)))"` and report the count.
- Otherwise report the HTTP status code as a failure.

## Step 5: Test MCP servers

**Skip this step** if the user requested `backends` or `openclaw` only.

For each of these routes **that exist** in the output from Step 3, send a JSON-RPC `initialize` request:

| Route Name |
|---|
| mcp-customer-route |
| mcp-finance-route |
| mcp-hr-recruiting-route |
| mcp-product-route |
| mcp-sales-order-route |
| mcp-sales-policy-search-route |
| mcp-hr-policy-route |

For each found route, run:

```bash
ROUTE_HOST=$(oc get route <route-name> -o jsonpath='{.spec.host}')
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
  -X POST "https://${ROUTE_HOST}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}')
```

- HTTP 200 = PASS
- Anything else = FAIL (report the status code)

## Step 6: Test OpenClaw

**Skip this step** if the user requested `backends` or `mcp` only.

If `openclaw-route` exists in the output from Step 3:

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${ROUTE_HOST}/")
```

- Any non-5xx status (1xx, 2xx, 3xx, 4xx) = PASS
- 5xx = FAIL

If the route does not exist, report "not deployed" instead of FAIL.

## Step 7: Retrieve live OpenClaw gateway token

**Skip this step** if `openclaw-route` was not found in Step 3.

The gateway regenerates its auth token on every pod restart. Since earlier deployment steps (MCP injection, sub-agent injection, workspace viewer) each restart the pod, any token read earlier in the process is stale. Always read the token **here**, as the last retrieval, so the reported value matches the running pod.

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('gateway',{}).get('auth',{}).get('token','(no token found)'))"
```

Store the result — it will be displayed in the summary.

## Step 8: Report summary

Present a single summary table with all tested services:

```
| Service                      | Type     | Status | Details            |
|------------------------------|----------|--------|--------------------|
| fantaco-customer-service     | Backend  | PASS   | 12 customers       |
| fantaco-finance-service      | Backend  | PASS   | 8 invoices         |
| mcp-customer-route           | MCP      | PASS   | HTTP 200           |
| mcp-finance-route            | MCP      | FAIL   | HTTP 503           |
| openclaw-route               | OpenClaw | PASS   | HTTP 200           |
```

At the bottom, show a one-line summary: `X/Y services passed`.

If any services from the known inventory were not found as routes, list them under a "Not deployed" section so the user knows what's missing.

**If backends were tested**, display clickable frontend UI URLs for services that have web UIs:

| Route Name | UI Path |
|---|---|
| fantaco-customer-service | /customers/index.html |
| fantaco-product-service | /catalog/index.html |

Only include rows for routes that were found in Step 3. Display as full `https://` URLs:

```
Frontend UIs
  Customers: https://<customer-route-host>/customers/index.html
  Catalog:   https://<product-route-host>/catalog/index.html
```

**If `openclaw-filebrowser-route` was found in Step 3**, display the file browser connection info:

```
Workspace File Browser
  URL:      https://<filebrowser-route-host>
  Username: admin
  Password: openclaw-demo
```

**If OpenClaw was tested**, always display the gateway connection info last:

```
OpenClaw Gateway
  URL:   https://<route-host>
  Token: <live-token-from-step-7>
```

This ensures the token shown is always from the currently running pod, regardless of how many restarts occurred during deployment.
