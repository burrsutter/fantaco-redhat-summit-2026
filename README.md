# FantaCo - AI Agent Workshop Materials

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

## Prerequisites

- **Java 21** (OpenJDK or Oracle JDK)
- **Maven 3.8+**
- **PostgreSQL 15+**
- **Python 3.11+** (for MCP servers)
- **Podman** (for container builds)
- **oc CLI** (for OpenShift deployment)

## Starting the model server

For localhost development, use [Ollama](https://ollama.com/) or you can use a remote model server such as vLLM via Model-as-a-Service solution [MaaS](https://maas.apps.prod.rhoai.rh-aiservices-bu.com/admin/applications)

```bash
ollama serve
```

Pull down your needed models. For LLM tool invocations you often need a larger model such as Qwen 14B. The way you know is to test your app/agent + model + model-server-configuration.

```bash
ollama pull llama3.2:3b
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

## MCP Servers

MCP servers provide read-only tool access to the backend services for AI agents.

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

Use `mcp-inspector` to test the MCP servers.

## Deploying to OpenShift

### Login to OpenShift

```bash
oc login --token=<your-token> --server=https://<your-cluster-api>:6443
oc project <your-namespace>
```

### Deploy a service (example: Customer)

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

This installs all services, MCP servers, and agents via Helm charts:

```bash
helm install fantaco-app ./helm/fantaco-app
helm install fantaco-mcp ./helm/fantaco-mcp
helm install fantaco-agent ./helm/fantaco-agent
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

> **Note:** Sales Policy Search uses `pgvector/pgvector:pg15` for PostgreSQL (not the RHEL image used by the Java services). This image requires the `PGDATA` env var set to a subdirectory (`/var/lib/postgresql/data/pgdata`) to work on OpenShift. The RAG service also needs 2Gi memory and a 120s route timeout annotation.

### Deploy MCP servers to OpenShift

MCP server Kubernetes manifests are in `fantaco-mcp-servers/<service>-mcp-kubernetes/`.

```bash
cd fantaco-mcp-servers/customer-mcp
podman build --arch amd64 --os linux -t docker.io/burrsutter/mcp-server-customer:1.0.0 .
podman push docker.io/burrsutter/mcp-server-customer:1.0.0

cd ../customer-mcp-kubernetes
oc apply -f mcp-server-deployment.yaml
oc apply -f mcp-server-service.yaml
oc apply -f mcp-server-route.yaml
```

## LangGraph Agent

The `agents-langgraph/` directory contains a LangGraph-based agent with FastAPI backend that connects directly to MCP servers using client-side tool execution.

```bash
cd agents-langgraph
```

Follow the [README.md](agents-langgraph/README.md) for setup and testing.

## MCP Examples

The `mcp-examples/` directory contains progressive examples showing how to use LangGraph with MCP servers:

```bash
cd mcp-examples
source .venv/bin/activate
python 5_langgraph_client_customer.py
```
