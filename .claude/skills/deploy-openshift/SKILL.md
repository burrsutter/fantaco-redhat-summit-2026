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

## Step 2.5: Load LLM_API_KEY from .env

The policy-search RAG services require an LLM API key to function. Source the project `.env` file and check for a valid key:

```bash
if [ -f .env ]; then
  source .env
fi
echo "LLM_API_KEY=${LLM_API_KEY:-<not set>}"
```

If `LLM_API_KEY` is unset, empty, or still the placeholder `sk-placeholder-change-me`, warn the user:

> **Warning:** `LLM_API_KEY` is not configured. The sales-policy-search and hr-policy-search RAG services will deploy but will not be able to answer queries. Set `LLM_API_KEY` in your `.env` file and re-run, or provide the key now.

Ask the user whether to continue without the key or provide one. Store the resolved value for use in Step 3c.

## Step 3: Deploy the stack (in order)

Run both Helm installs from the `helm/` directory. These must be run **sequentially** because the MCP servers reference the app services:

**3a. Deploy databases and microservices:**
```bash
cd helm && helm install fantaco-app ./fantaco-app
```
This deploys:
- PostgreSQL for customer data (`postgres-cust:5432`)
- PostgreSQL for finance data (`postgres-fin:5432`)
- PostgreSQL for product data (`postgres-prod:5432`)
- PostgreSQL for sales-order data (`postgres-sord:5432`)
- PostgreSQL for hr-recruiting data (`postgres-hr-recruiting:5432`)
- PostgreSQL for sales-policy-search data (`fantaco-sales-policy-search-db:5432` — pgvector)
- PostgreSQL for hr-policy-search data (`fantaco-hr-policy-search-db:5432` — pgvector)
- Fantaco Customer Service (`fantaco-customer-service:8081`)
- Fantaco Finance Service (`fantaco-finance-service:8082`)
- Fantaco Product Service (`fantaco-product-service:8083`)
- Fantaco Sales Order Service (`fantaco-sales-order-service:8084`)
- Fantaco HR Recruiting Service (`fantaco-hr-recruiting-service:8085`)
- Fantaco Sales Policy Search Service (`fantaco-sales-policy-search-service:8090` — Python RAG)
- Fantaco HR Policy Search Service (`fantaco-hr-policy-search-service:8091` — Python RAG)

**3b. Deploy MCP servers:**
```bash
helm install fantaco-mcp ./fantaco-mcp
```
This deploys:
- Customer MCP Server (`mcp-customer-service:9001`)
- Finance MCP Server (`mcp-finance-service:9002`)
- Product MCP Server (`mcp-product-service:9003`)
- Sales Order MCP Server (`mcp-sales-order-service:9004`)
- HR Recruiting MCP Server (`mcp-hr-recruiting-service:9005`)
- Sales Policy Search MCP Server (`mcp-sales-policy-search-service:9006`)
- HR Policy MCP Server (`mcp-hr-policy-service:9007`)

**3c. Patch LLM_API_KEY secrets:**

If a valid `LLM_API_KEY` was resolved in Step 2.5, patch the secrets so the RAG services pick up the real key:

```bash
oc patch secret fantaco-sales-policy-search-secret --type merge \
  -p "{\"stringData\":{\"LLM_API_KEY\":\"${LLM_API_KEY}\"}}"
oc patch secret fantaco-hr-policy-search-secret --type merge \
  -p "{\"stringData\":{\"LLM_API_KEY\":\"${LLM_API_KEY}\"}}"
```

Then restart the RAG pods so they pick up the updated secret:

```bash
oc rollout restart deployment/fantaco-sales-policy-search
oc rollout restart deployment/fantaco-hr-policy-search
```

## Step 4: Wait for pods and verify

Wait 30 seconds, then check all pods:

```bash
oc get pods
```

All 21 pods should reach `Running` / `1/1 Ready`:

**Databases (7):**
1. `postgres-cust`
2. `postgres-fin`
3. `postgres-prod`
4. `postgres-sord`
5. `postgres-hr-recruiting`
6. `fantaco-sales-policy-search-db`
7. `fantaco-hr-policy-search-db`

**Backend services (7):**
8. `fantaco-customer-main`
9. `fantaco-finance-main`
10. `fantaco-product-main`
11. `fantaco-sales-order-main`
12. `fantaco-hr-recruiting`
13. `fantaco-sales-policy-search`
14. `fantaco-hr-policy-search`

**MCP servers (7):**
15. `mcp-customer`
16. `mcp-finance`
17. `mcp-product`
18. `mcp-sales-order`
19. `mcp-hr-recruiting`
20. `mcp-sales-policy-search`
21. `mcp-hr-policy`

## Step 5: Collect and display routes

```bash
oc get routes -o custom-columns="NAME:.metadata.name,URL:.spec.host"
```

Present the user with a summary table of all deployed routes, prefixed with `https://`:

| Service | URL |
|---------|-----|
| Customer API | `https://<route>` |
| Finance API | `https://<route>` |
| Product API | `https://<route>` |
| Sales Order API | `https://<route>` |
| HR Recruiting API | `https://<route>` |
| Sales Policy Search API | `https://<route>` |
| HR Policy Search API | `https://<route>` |
| MCP Customer | `https://<route>` |
| MCP Finance | `https://<route>` |
| MCP Product | `https://<route>` |
| MCP Sales Order | `https://<route>` |
| MCP HR Recruiting | `https://<route>` |
| MCP Sales Policy Search | `https://<route>` |
| MCP HR Policy | `https://<route>` |

## Step 6: Smoke test

Run per-service health checks to verify the entire stack. Collect the route URLs from Step 5 and run:

**Java backends** — check Spring Boot actuator:
```bash
for route in <customer-route> <finance-route> <product-route> <sales-order-route> <hr-recruiting-route>; do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "https://${route}/actuator/health/liveness")
  echo "${route}: ${STATUS}"
done
```

**Python RAG backends** — check `/health` endpoint:
```bash
for route in <sales-policy-search-route> <hr-policy-search-route>; do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "https://${route}/health")
  echo "${route}: ${STATUS}"
done
```

**MCP servers** — send JSON-RPC initialize:
```bash
for route in <mcp-customer-route> <mcp-finance-route> <mcp-product-route> <mcp-sales-order-route> <mcp-hr-recruiting-route> <mcp-sales-policy-search-route> <mcp-hr-policy-route>; do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "https://${route}/mcp" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0.0"}}}')
  echo "${route}: ${STATUS}"
done
```

Present results as a summary table:

| Service | Endpoint | Status |
|---------|----------|--------|
| Customer API | `/actuator/health/liveness` | 200 |
| Finance API | `/actuator/health/liveness` | 200 |
| ... | ... | ... |

Report the final deployment status to the user. All services should return `200`.
