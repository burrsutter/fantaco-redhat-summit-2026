# AI Agent Workshop Materials

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

## Start Customer Backend

Assumes Postgres is up and running with appropriate database pre-created. See the deeper dive README.MD

```bash
cd fantaco-customer-main
open README.md
```

Run the Customer REST API

```bash
java -jar target/fantaco-customer-main-1.0.0.jar
```

### Quick test of Customer REST API

```bash
curl -sS -L "$CUST_URL/api/customers?companyName=Around" | jq
```

## Start Finance Backend

```bash
cd fantaco-finance-main
open README.md
```

Run the Finance REST API

```bash
java -jar target/fantaco-finance-main-1.0.0.jar
```

### Quick test for Finance REST API

```bash
curl -sS -X POST $FIN_URL/api/finance/orders/history \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "AROUT",
    "limit": 10
  }' | jq
```

## Customer MCP

```bash
cd fantaco-mcp-servers/customer-mcp
source .venv/bin/activate
```

```bash
python customer-api-mcp-server.py
```

## Finance MCP

```bash
cd fantaco-mcp-servers/finance-mcp
source .venv/bin/activate
```

```bash
python finance-api-mcp-server.py
```

Using `mcp-inspector` to test the MCP Servers

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
