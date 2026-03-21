---
name: deploy-openshift
description: Deploy the full Fantaco AI Agent stack to OpenShift using Helm charts
argument-hint: "[namespace]"
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, AskUserQuestion, Glob
---

# Deploy Fantaco to OpenShift

Deploy the complete Fantaco AI Agent Workshop stack (databases, microservices, MCP servers, LangGraph agent, and chat UI) to an OpenShift cluster using the Helm charts in `helm/`.

## Step 0: Gather required configuration

Before doing anything else, use AskUserQuestion to collect the following from the user in a single prompt:

**Question 1 — "Model Server URL"**
Ask: "What is the MODEL_BASE_URL for your OpenAI-compatible model server? (e.g. https://litellm-prod.apps.example.com)"
Options (let user pick or type their own):
- `https://litellm-prod.apps.maas.redhatworkshops.io`
- `http://ollama:11434`

**Question 2 — "API Key"**
Ask: "What is the API_KEY for the model server? (enter 'fake' if none is required)"
Options:
- `fake`

After receiving answers, store them as `MODEL_BASE_URL` and `API_KEY` for use in Step 4.

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

## Step 2: Verify model server is reachable

Test connectivity to the model server using the URL and key from Step 0:

```bash
curl -sS <MODEL_BASE_URL>/v1/models -H "Authorization: Bearer <API_KEY>" | jq .
```

If this fails, warn the user and ask whether to proceed anyway (the agent pod will crash-loop until the model server is available).

## Step 3: Check for existing deployments

```bash
helm list
oc get pods
```

If Helm releases already exist (`fantaco-app`, `fantaco-mcp`, `fantaco-agent`), ask the user whether to:
- Upgrade existing releases (`helm upgrade`)
- Uninstall and reinstall (`helm uninstall` then `helm install`)
- Abort

## Step 4: Update Helm values with user configuration

Before installing, update `helm/fantaco-agent/values.yaml` with the MODEL_BASE_URL and API_KEY collected in Step 0. Edit these fields:

```yaml
langgraphFastapi:
  env:
    modelBaseUrl: <MODEL_BASE_URL>
    apiKey: <API_KEY>
```

Also ensure the image repository points to the correct, publicly accessible image:

```yaml
langgraphFastapi:
  image:
    repository: docker.io/burrsutter/langgraph-fastapi
```

## Step 5: Deploy the stack (in order)

Run all three Helm installs from the `helm/` directory. These must be run **sequentially** because the MCP servers reference the app services and the agent references the MCP services:

**5a. Deploy databases and microservices:**
```bash
cd helm && helm install fantaco-app ./fantaco-app
```
This deploys:
- PostgreSQL for customer data (`postgres-cust:5432`)
- PostgreSQL for finance data (`postgres-fin:5432`)
- Fantaco Customer Service (`fantaco-customer-service:8081`)
- Fantaco Finance Service (`fantaco-finance-service:8082`)

**5b. Deploy MCP servers:**
```bash
helm install fantaco-mcp ./fantaco-mcp
```
This deploys:
- Customer MCP Server (`mcp-customer-service:9001`)
- Finance MCP Server (`mcp-finance-service:9002`)

**5c. Deploy LangGraph agent and chat UI:**
```bash
helm install fantaco-agent ./fantaco-agent
```
This deploys:
- LangGraph FastAPI Agent (`langgraph-fastapi:8000`)
- Simple Agent Chat UI (`simple-agent-chat-ui:3000`)

## Step 6: Wait for pods and verify

Wait 30 seconds, then check all pods:

```bash
oc get pods
```

All 8 pods should reach `Running` / `1/1 Ready`:
1. `postgresql-customer`
2. `postgresql-finance`
3. `fantaco-customer-main`
4. `fantaco-finance-main`
5. `mcp-customer`
6. `mcp-finance`
7. `langgraph-fastapi`
8. `simple-agent-chat-ui`

If `langgraph-fastapi` is in `Error` or `CrashLoopBackOff`, check its logs:
```bash
oc logs deployment/langgraph-fastapi --tail=30
```

Common issues:
- **"Request URL is missing an 'http://' or 'https://' protocol"** — MODEL_BASE_URL env var is not set or empty
- **"404 - Not Found" on `/responses`** — The container image needs `use_responses_api=False` in ChatOpenAI. Rebuild from source in `agents-langgraph/langgraph-fastapi/`
- **Connection error to model server** — The model server URL is unreachable from inside the cluster
- **ErrImagePull / unauthorized** — The container image registry is private. Make it public or create an image pull secret

## Step 7: Collect and display routes

```bash
oc get routes -o custom-columns="NAME:.metadata.name,URL:.spec.host"
```

Present the user with a summary table of all deployed routes, prefixed with `https://`:

| Service | URL |
|---------|-----|
| Chat UI | `https://<route>` |
| LangGraph API | `https://<route>` |
| Customer API | `https://<route>` |
| Finance API | `https://<route>` |
| MCP Customer | `https://<route>` |
| MCP Finance | `https://<route>` |

## Step 8: Smoke test

Run a quick health check against the customer service to confirm the backend is working:

```bash
curl -sS https://<customer-route>/api/customers | jq '. | length'
```

Report the final deployment status to the user.

## Step 9: Present sample queries

After deployment, tell the user to open the **Chat UI** route in their browser and provide these sample queries to try. There are 3 test customers pre-loaded with orders, invoices, disputes, and receipts:

| Customer ID | Company | Contact | Orders | Invoices | Disputes |
|-------------|---------|---------|--------|----------|----------|
| LONEP | Lonesome Pine Restaurant | Fran Wilson | 3 | 3 | 2 (billing error, duplicate charge) |
| AROUT | Around the Horn | Thomas Hardy | 3 | 3 | 1 (product not received) |
| THECR | The Cracker Box | Liu Wong | 2 | 2 | 0 |

**Sample prompts to try in the Chat UI:**

1. "What orders does Lonesome Pine Restaurant have?"
2. "Show me invoices for Around the Horn"
3. "Does customer LONEP have any open disputes?"
4. "Find the customer Thomas Hardy and show their order history"
5. "What is the status of order ORD-003?"
6. "Which invoices are still unpaid for LONEP?"
7. "Tell me about The Cracker Box — who is the contact and what have they ordered?"
