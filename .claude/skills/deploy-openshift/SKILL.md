---
name: deploy-openshift
description: Deploy the full Fantaco stack to OpenShift using Helm charts
argument-hint: "[namespace]"
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, AskUserQuestion, Glob
---

# Deploy Fantaco to OpenShift

Deploy the complete Fantaco Workshop stack (databases, microservices, and MCP servers) to an OpenShift cluster using the Helm charts in `helm/`.

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**, reporting the issue to the user:

```bash
oc whoami
oc project
```

If a namespace argument was provided (`$ARGUMENTS`), switch to it:
```bash
oc project $ARGUMENTS
```

## Step 2: Check for existing deployments

```bash
helm list
oc get pods
```

If Helm releases already exist (`fantaco-app`, `fantaco-mcp`), ask the user whether to:
- Upgrade existing releases (`helm upgrade`)
- Uninstall and reinstall (`helm uninstall` then `helm install`)
- Abort

## Step 3: Deploy the stack (in order)

Run both Helm installs from the `helm/` directory. These must be run **sequentially** because the MCP servers reference the app services:

**3a. Deploy databases and microservices:**
```bash
cd helm && helm install fantaco-app ./fantaco-app
```
This deploys:
- PostgreSQL for customer data (`postgres-cust:5432`)
- PostgreSQL for finance data (`postgres-fin:5432`)
- Fantaco Customer Service (`fantaco-customer-service:8081`)
- Fantaco Finance Service (`fantaco-finance-service:8082`)

**3b. Deploy MCP servers:**
```bash
helm install fantaco-mcp ./fantaco-mcp
```
This deploys:
- Customer MCP Server (`mcp-customer-service:9001`)
- Finance MCP Server (`mcp-finance-service:9002`)

## Step 4: Wait for pods and verify

Wait 30 seconds, then check all pods:

```bash
oc get pods
```

All 6 pods should reach `Running` / `1/1 Ready`:
1. `postgresql-customer`
2. `postgresql-finance`
3. `fantaco-customer-main`
4. `fantaco-finance-main`
5. `mcp-customer`
6. `mcp-finance`

## Step 5: Collect and display routes

```bash
oc get routes -o custom-columns="NAME:.metadata.name,URL:.spec.host"
```

Present the user with a summary table of all deployed routes, prefixed with `https://`:

| Service | URL |
|---------|-----|
| Customer API | `https://<route>` |
| Finance API | `https://<route>` |
| MCP Customer | `https://<route>` |
| MCP Finance | `https://<route>` |

## Step 6: Smoke test

Run a quick health check against the customer service to confirm the backend is working:

```bash
curl -sS https://<customer-route>/api/customers | jq '. | length'
```

Report the final deployment status to the user.
