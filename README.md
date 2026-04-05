# FantaCo - AI Agent Workshop Materials

This repository demonstrates how OpenClaw can operate in a traditional enterprise setting using FantaCo as the fictional company.

FantaCo sells office supplies, furniture, and themed workplace design/construction services. The demo narrative centers on Sally Sellers, a sales representative who uses OpenClaw to work across CRM, sales orders, invoices, product catalog data, sales policy knowledge, and internal employee systems.

Important framing:

- FantaCo is not an HR benefits company.
- FantaCo does provide internal HR benefits to its employees.
- The themed workplace offerings include Enchanted Forest, Interstellar Spaceship, 1920s Speakeasy, and Serene Zen Garden.

## Services Overview

| Service | Directory | Port | Database | API Base Path |
|---------|-----------|------|----------|---------------|
| Customer | `fantaco-customer-main` | 8081 | `fantaco_customer` | `/api/customers` |
| Finance | `fantaco-finance-main` | 8082 | `fantaco_finance` | `/api/finance` |
| Product | `fantaco-product-main` | 8083 | `fantaco_product` | `/api/products` |
| Sales Order | `fantaco-sales-order-main` | 8084 | `fantaco_sales_order` | `/api/sales-orders` |
| HR Recruiting | `fantaco-hr-recruiting` | 8085 | `fantaco_hr` | `/api/jobs`, `/api/applications` |

### RAG Search Services (Python / FastAPI / pgvector)

| Service | Directory | Port | Database | API Base Path |
|---------|-----------|------|----------|---------------|
| Sales Policy Search | `fantaco-sales-policy-search` | 8090 | `fantaco_sales_policy` | `/api/sales-policy` |
| HR Policy Search | `fantaco-hr-policy-search` | 8091 | `fantaco_hr_policy` | `/api/hr-policy` |

RAG search services use a **different stack** than the Java CRUD services above:

- **Runtime:** Python 3.11 / FastAPI (not Java / Spring Boot)
- **Database:** PostgreSQL with **pgvector** extension (`pgvector/pgvector:pg15` image, not `registry.redhat.io/rhel9/postgresql-15`)
- **Embeddings:** sentence-transformers (`nomic-ai/nomic-embed-text-v1.5`), loaded into memory at runtime
- **LLM:** OpenAI-compatible API (LiteLLM / Ollama) for answer generation
- **Memory:** Requires 2Gi (embedding model + PyTorch), much more than Java services (512Mi) or MCP servers (256Mi)

The pgvector-enabled PostgreSQL image requires a `PGDATA` subdirectory workaround for OpenShift (see `deployment/kubernetes/postgres/deployment.yaml`).

| MCP Server | Directory | Port | Connects To |
|------------|-----------|------|-------------|
| Customer MCP | `fantaco-mcp-servers/customer-mcp` | 9001 | Customer (8081) |
| Finance MCP | `fantaco-mcp-servers/finance-mcp` | 9002 | Finance (8082) |
| Product MCP | `fantaco-mcp-servers/product-mcp` | 9003 | Product (8083) |
| Sales Order MCP | `fantaco-mcp-servers/sales-order-mcp` | 9004 | Sales Order (8084) |
| HR Recruiting MCP | `fantaco-mcp-servers/hr-recruiting-mcp` | 9005 | HR Recruiting (8085) |
| Sales Policy Search MCP | `fantaco-mcp-servers/sales-policy-search-mcp` | 9006 | Sales Policy Search (8090) |
| HR Policy Search MCP | `fantaco-mcp-servers/hr-policy-mcp` | 9007 | HR Policy Search (8091) |

## Demo Story

The main demo path is documented in [DEMO_SCRIPT.MD](./DEMO_SCRIPT.MD).

At a high level, Sally Sellers uses OpenClaw to:

- establish identity and memory
- discover connected skills and tools
- answer internal employee HR questions such as 401(k) policy
- find her customer accounts
- research a customer across CRM, orders, invoices, and projects
- retrieve sales policy guidance
- create and test custom skills
- monitor customer activity and alert through Telegram

For MCP-specific setup and usage guidance, see [fantaco-mcp-servers/README.md](./fantaco-mcp-servers/README.md).

## Prerequisites

- **Java 21** (OpenJDK or Oracle JDK)
- **Maven 3.8+**
- **PostgreSQL 15+**
- **Python 3.11+** (for MCP servers)
- **Podman** (for container builds)
- **oc CLI** (for OpenShift deployment)

## Starting the model server

For localhost development, use [Ollama](https://ollama.com/) or you can use a remote model server such as vLLM via Model-as-a-Service solution [MaaS](https://maas.apps.prod.rhoai.rh-aiservices-bu.com/admin/applications)

Note: Only the RAG services use one of the small open weights models such as qwen3:14b.

```bash
ollama serve
```

Pull down your needed models. The way you know is to test your app/agent + model + model-server-configuration.

```bash
ollama pull qwen3:14b-q8_0
```

### Environment Variables

If using Ollama

```bash
export MODEL_BASE_URL=http://localhost:11434
export INFERENCE_MODEL=qwen3:14b-q8_0
export API_KEY=fake
```

If using [MaaS](https://maas.apps.prod.rhoai.rh-aiservices-bu.com/admin/applications)

```bash
export MODEL_BASE_URL=https://litellm-prod.apps.maas.redhatworkshops.io
export API_KEY=your-maas-api-key
export INFERENCE_MODEL=qwen3-14b
```

Verify model access:

```bash
curl -sS $MODEL_BASE_URL/v1/models -H "Authorization: Bearer $API_KEY" | jq
```

## Running Services Locally

All services require PostgreSQL running locally. Create the databases first:

```bash
createdb fantaco_customer
createdb fantaco_finance
createdb fantaco_product
createdb fantaco_sales_order
createdb fantaco_hr
createdb fantaco_sales_policy
createdb fantaco_hr_policy
```

### Customer Service (port 8081)

```bash
cd fantaco-customer-main
mvn clean package -DskipTests
java -jar target/fantaco-customer-main-1.0.0.jar
```

```bash
export CUST_URL=http://localhost:8081
curl -sS "$CUST_URL/api/customers?companyName=Around" | jq
open $CUST_URL/swagger-ui.html
```

### Finance Service (port 8082)

```bash
cd fantaco-finance-main
mvn clean package -DskipTests
java -jar target/fantaco-finance-main-1.0.0.jar
```

```bash
export FIN_URL=http://localhost:8082
curl -sS -X POST $FIN_URL/api/finance/invoices/history \
  -H "Content-Type: application/json" \
  -d '{"customerId": "LONEP", "limit": 10}' | jq
open $FIN_URL/swagger-ui.html
```

### Product Service (port 8083)

```bash
cd fantaco-product-main
mvn clean package -DskipTests
java -jar target/fantaco-product-main-1.0.0.jar
```

```bash
export PROD_URL=http://localhost:8083
curl -sS "$PROD_URL/api/products" | jq
open $PROD_URL/swagger-ui.html
```

### Sales Order Service (port 8084)

```bash
cd fantaco-sales-order-main
mvn clean package -DskipTests
java -jar target/fantaco-sales-order-main-1.0.0.jar
```

```bash
export SORD_URL=http://localhost:8084
curl -sS "$SORD_URL/api/sales-orders" | jq
open $SORD_URL/swagger-ui.html
```

### HR Recruiting Service (port 8085)

```bash
cd fantaco-hr-recruiting
mvn clean package -DskipTests
java -jar target/fantaco-hr-recruiting-1.0.0.jar
```

```bash
export HR_RECRUITING_URL=http://localhost:8085
curl -sS "$HR_RECRUITING_URL/api/jobs" | jq
curl -sS "$HR_RECRUITING_URL/api/applications" | jq
open $HR_RECRUITING_URL/swagger-ui.html
```

### Sales Policy Search (port 8090)

Requires PostgreSQL **with pgvector** — the standard PostgreSQL used by the Java services does not have the vector extension.

```bash
# Start pgvector-enabled PostgreSQL (different image than the other services)
podman run -d --name pgvector-local \
  -e POSTGRES_DB=fantaco_sales_policy \
  -e POSTGRES_USER=rag_user \
  -e POSTGRES_PASSWORD=rag_pass \
  -p 5432:5432 \
  pgvector/pgvector:pg15
```

```bash
cd fantaco-sales-policy-search
pip install -r requirements.txt
export DATABASE_URL="postgresql://rag_user:rag_pass@localhost:5432/fantaco_sales_policy"
export LLM_API_BASE_URL="$MODEL_BASE_URL"
export LLM_MODEL_NAME="$INFERENCE_MODEL"
export LLM_API_KEY="$API_KEY"
python app.py
```

Documents are auto-seeded on startup from `seed_documents/`. Test with:

```bash
export SPOL_URL=http://localhost:8090
curl -sS "$SPOL_URL/health" | jq
curl -sS -X POST "$SPOL_URL/api/sales-policy/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the return policy for defective tacos?"}' | jq
```

### HR Policy Search (port 8091)

Requires PostgreSQL **with pgvector** just like Sales Policy Search.

```bash
# Start pgvector-enabled PostgreSQL for HR policy search
podman run -d --name pgvector-hr-policy-local \
  -e POSTGRES_DB=fantaco_hr_policy \
  -e POSTGRES_USER=rag_user \
  -e POSTGRES_PASSWORD=rag_pass \
  -p 5433:5432 \
  pgvector/pgvector:pg15
```

```bash
cd fantaco-hr-policy-search
pip install -r requirements.txt
export DATABASE_URL="postgresql://rag_user:rag_pass@localhost:5433/fantaco_hr_policy"
export LLM_API_BASE_URL="$MODEL_BASE_URL"
export LLM_MODEL_NAME="$INFERENCE_MODEL"
export LLM_API_KEY="$API_KEY"
python app.py
```

Test with:

```bash
export HPOL_URL=http://localhost:8091
curl -sS "$HPOL_URL/health" | jq
curl -sS -X POST "$HPOL_URL/api/hr-policy/search" \
  -H "Content-Type: application/json" \
  -d '{"query": "How is the 401K handled here at FantaCo?"}' | jq
```

## MCP Servers

MCP servers provide tool access to the backend services for AI agents. Some are read-only lookup tools, while others also support operational or admin actions.

### Customer MCP (port 9001)

```bash
cd fantaco-mcp-servers/customer-mcp
source .venv/bin/activate
python customer-api-mcp-server.py
```

### Finance MCP (port 9002)

```bash
cd fantaco-mcp-servers/finance-mcp
source .venv/bin/activate
python finance-api-mcp-server.py
```

### Product MCP (port 9003)

```bash
cd fantaco-mcp-servers/product-mcp
source .venv/bin/activate
python product-api-mcp-server.py
```

### Sales Order MCP (port 9004)

```bash
cd fantaco-mcp-servers/sales-order-mcp
source .venv/bin/activate
python sales-order-api-mcp-server.py
```

### HR Recruiting MCP (port 9005)

```bash
cd fantaco-mcp-servers/hr-recruiting-mcp
source .venv/bin/activate
python hr-recruiting-api-mcp-server.py
```

### Sales Policy Search MCP (port 9006)

```bash
cd fantaco-mcp-servers/sales-policy-search-mcp
source .venv/bin/activate
python sales-policy-search-api-mcp-server.py
```

### HR Policy Search MCP (port 9007)

```bash
cd fantaco-mcp-servers/hr-policy-mcp
source .venv/bin/activate
python hr-policy-search-api-mcp-server.py
```

Use `mcp-inspector` to test the MCP servers.

## Deploying to OpenShift

### Login to OpenShift

```bash
oc login --token=<your-token> --server=https://<your-cluster-api>:6443
oc project <your-namespace>
```


### Deployment to OpenShift via Claude Code Skills

Deployment of the backend, mcp servers and openclaw is very involved therefore we have a bunch of steps and Skills to make it more repeatable. 

1.  `git clone https://github.com/burrsutter/fantaco-redhat-summit-2026`

2.  `cd fantaco-redhat-summit-2026`

3.  `oc login`

Note: This works with a user having namespace admin, does not require cluster admin

4. `claude`

5. `/plugin install fantaco`

6. `/preflight` — Validates CLI tools, OpenShift login, `.env` keys, endpoint reachability, registry auth

7. `/deploy-openshift` — Deploys all backends + MCP servers via Helm (`fantaco-app` then `fantaco-mcp`)

8. `/deploy-openclaw` — Deploys the OpenClaw AI agent gateway (secrets, configmap, PVC, deployment, route)

9. **`/inject-mcp-openclaw`** — **Vital** — registers the MCP servers with OpenClaw so agents can use them. Without this step OpenClaw is running but has no tools connected.

10. `/openclaw-workspace-viewer` — Adds a file browser so you can see into the OpenClaw workspace

> **Important:** Step 4 is not optional. OpenClaw deploys with an empty MCP config. You must inject the MCP server URLs so the gateway can route agent tool calls to the backend services.

11. Find the OpenClaw Gateway Console Route

```
oc get route openclaw-route -o jsonpath='{.spec.host}'
```

12. Find the OpenClaw Gateway Token

```
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])"
```

Open the route in your browser, apply the token, click the *Connect* button

![OpenClaw Gateway - Pairing Required](images/openclaw-gateway-pairing-required.png)


13. `/openclaw-gateway-pairing` - helps you through the tricky gateway pairing



### Deploy a single service (example: Customer)

Each service follows the same deployment pattern. Replace `customer` with the service name.

**Step 1: Build and push the container image**

```bash
cd fantaco-customer-main
./rebuild.sh
```

This runs `mvn clean compile package`, builds the container image with Podman, and pushes to `docker.io/burrsutter/<service-name>:1.0.0`. Make sure the docker.io repository is public.

**Step 2: Deploy PostgreSQL**

```bash
oc apply -f deployment/kubernetes/postgres/deployment.yaml
oc apply -f deployment/kubernetes/postgres/service.yaml
oc rollout status deployment/postgresql-customer --timeout=60s
```

**Step 3: Deploy the application**

```bash
oc apply -f deployment/kubernetes/application/configmap.yaml
oc apply -f deployment/kubernetes/application/secret.yaml
oc apply -f deployment/kubernetes/application/deployment.yaml
oc apply -f deployment/kubernetes/application/service.yaml
oc apply -f deployment/kubernetes/application/route.yaml
oc rollout status deployment/fantaco-customer-main --timeout=120s
```

Or use the redeploy script (skips postgres, restarts pods):

```bash
./redeploy.sh
```

**Step 4: Get the route and test**

```bash
export CUST_URL=https://$(oc get route fantaco-customer-service -o jsonpath='{.spec.host}')
curl -sk "$CUST_URL/api/customers" | jq
open "$CUST_URL/swagger-ui.html"
```

### Deploy all services with Helm

```bash
./install-fantaco.sh
```

This installs all services and MCP servers via Helm charts:

```bash
helm install fantaco-app ./helm/fantaco-app
helm install fantaco-mcp ./helm/fantaco-mcp
```

### Service-specific deployment details

| Service | Postgres Deployment | Postgres Service | App Deployment | Container Image |
|---------|-------------------|-----------------|----------------|-----------------|
| Customer | `postgresql-customer` | `postgres-cust` | `fantaco-customer-main` | `docker.io/burrsutter/fantaco-customer-main:1.0.0` |
| Finance | `postgresql-finance` | `postgres-fin` | `fantaco-finance-main` | `docker.io/burrsutter/fantaco-finance-main:1.0.0` |
| Product | `postgresql-product` | `postgres-prod` | `fantaco-product-main` | `docker.io/burrsutter/fantaco-product-main:1.0.0` |
| Sales Order | `postgresql-sales-order` | `postgres-sord` | `fantaco-sales-order-main` | `docker.io/burrsutter/fantaco-sales-order-main:1.0.0` |
| HR Recruiting | `postgresql-hr-recruiting` | `postgres-hr-recruiting` | `fantaco-hr-recruiting` | `docker.io/burrsutter/fantaco-hr-recruiting:1.0.0` |
| Sales Policy Search | `fantaco-sales-policy-search-db` | `fantaco-sales-policy-search-db` | `fantaco-sales-policy-search` | `docker.io/burrsutter/fantaco-sales-policy-search:1.0.0` |
| HR Policy Search | `fantaco-hr-policy-search-db` | `fantaco-hr-policy-search-db` | `fantaco-hr-policy-search` | `docker.io/burrsutter/fantaco-hr-policy-search:1.0.0` |

> **Note:** Sales Policy Search and HR Policy Search use `pgvector/pgvector:pg15` for PostgreSQL (not the RHEL image used by the Java services). These services require the `PGDATA` env var set to a subdirectory (`/var/lib/postgresql/data/pgdata`) to work on OpenShift. The RAG services also need higher memory than the Java APIs and longer route timeouts.

### Deploy MCP servers to OpenShift

MCP server Kubernetes manifests are in `fantaco-mcp-servers/<service>-mcp-kubernetes/`.

For the Sally demo, prioritize these MCP servers:

- `customer-mcp-kubernetes`
- `sales-order-mcp-kubernetes`
- `finance-mcp-kubernetes`
- `sales-policy-search-mcp-kubernetes`
- `hr-policy-mcp-kubernetes`

Optional:

- `product-mcp-kubernetes`
- `hr-recruiting-mcp-kubernetes`

```bash
cd fantaco-mcp-servers/customer-mcp
podman build --arch amd64 --os linux -t docker.io/burrsutter/mcp-server-customer:1.0.0 .
podman push docker.io/burrsutter/mcp-server-customer:1.0.0

cd ../customer-mcp-kubernetes
oc apply -f mcp-server-deployment.yaml
oc apply -f mcp-server-service.yaml
oc apply -f mcp-server-route.yaml
```

