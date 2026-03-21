# MCP Server Adapter — Generative Spec

> **Purpose:** Given a REST API base URL and a list of operations to expose, generate a Python FastMCP server that wraps the API as AI-agent-callable tools. This spec is backend-agnostic — it works for wrapping any REST API (CRUD or action-based).

---

## Input Contract

To generate an MCP server adapter, provide:

| Input | Example | Required |
|-------|---------|----------|
| **Server name** | `product-mcp` | Yes |
| **FastMCP service ID** | `product-api` | Yes |
| **Backend API base URL env var** | `PRODUCT_API_BASE_URL` | Yes |
| **Default backend URL** | `http://fantaco-product-service:8083` | Yes |
| **MCP server port** | `9003` | Yes |
| **Port env var** | `PORT_FOR_PRODUCT_MCP` | Yes |
| **Host env var** | `HOST_FOR_PRODUCT_MCP` | Yes |
| **Container registry** | `quay.io/burrsutter` | Yes |
| **Tools** | See tool definition below | Yes |

### Tool Definition Format

Each tool needs:

| Property | Example |
|----------|---------|
| function_name | `search_products` |
| description | "Search for products by name or category with partial matching" |
| parameters | List of (name, type, optional, description) |
| http_method | `GET`, `POST`, `PUT`, `DELETE` |
| endpoint_path | `/api/products` |
| query_params | For GET: which parameters map to query params |
| json_body | For POST/PUT: which parameters map to JSON body fields |
| param_mapping | snake_case → camelCase mappings (e.g., `product_name` → `productName`) |

---

## Output Contract

The generator produces these exact files:

```
fantaco-mcp-servers/<server-name>/
├── <server-name-with-hyphens>-server.py    (e.g., product-api-mcp-server.py)
├── requirements.txt
└── Dockerfile
```

Plus Kubernetes manifests:

```
fantaco-mcp-servers/<server-name>-kubernetes/
├── mcp-server-deployment.yaml
├── mcp-server-service.yaml
└── mcp-server-route.yaml
```

And Helm chart additions to `helm/fantaco-mcp/`:

```
helm/fantaco-mcp/
├── values.yaml                          (add new section)
└── templates/
    ├── <server-name>-deployment.yaml    (new)
    ├── <server-name>-service.yaml       (new)
    └── <server-name>-route.yaml         (new)
```

---

## Complete Worked Example: Product Catalog MCP Server

**Input:**
- Server name: `product-mcp`
- FastMCP service ID: `product-api`
- Backend URL env var: `PRODUCT_API_BASE_URL`
- Default backend URL: `http://fantaco-product-service:8083`
- Port: `9003`
- Port env var: `PORT_FOR_PRODUCT_MCP`
- Host env var: `HOST_FOR_PRODUCT_MCP`
- Registry: `quay.io/burrsutter`

**Tools:**

1. `search_products` — GET `/api/products` with query params `productName`, `category`
2. `get_product` — GET `/api/products/{product_id}`
3. `create_product` — POST `/api/products` with JSON body
4. `update_product` — PUT `/api/products/{product_id}` with JSON body
5. `delete_product` — DELETE `/api/products/{product_id}`

---

### Generated File: `fantaco-mcp-servers/product-mcp/product-api-mcp-server.py`

```python
#!/usr/bin/env python3
"""
FastMCP server for Fantaco Product API
Provides tools to use the Fantaco Product Service API
Based on OpenAPI specification v0

Server Configuration:
    - Transport: streamable HTTP
    - Port: Configurable via PORT_FOR_PRODUCT_MCP (default: 9003)
    - Host: Configurable via HOST_FOR_PRODUCT_MCP (default: 0.0.0.0)

Environment Variables:
    PRODUCT_API_BASE_URL: Base URL for the Product API
    PORT_FOR_PRODUCT_MCP: Port number for the MCP server (default: 9003)
    HOST_FOR_PRODUCT_MCP: Host address to bind to (default: 0.0.0.0)
"""

from fastmcp import FastMCP
from dotenv import load_dotenv
import asyncio
import httpx
import os
import logging
from typing import Optional, Dict, Any

# Initialize FastMCP server
mcp = FastMCP("product-api")

# Load environment variables from .env file
load_dotenv()

# Configuration
port = int(os.getenv("PORT_FOR_PRODUCT_MCP", "9003"))
host = os.getenv("HOST_FOR_PRODUCT_MCP", "0.0.0.0")
BASE_URL = os.getenv("PRODUCT_API_BASE_URL")

# HTTP client for API calls
http_client: Optional[httpx.AsyncClient] = None


async def get_http_client() -> httpx.AsyncClient:
    """Get or create HTTP client."""
    global http_client
    if http_client is None:
        http_client = httpx.AsyncClient(base_url=BASE_URL, timeout=30.0)
    return http_client


async def handle_response(response: httpx.Response) -> Dict[str, Any]:
    """Handle HTTP response and return JSON or error message"""
    try:
        response.raise_for_status()
        if response.content:
            data = response.json()
            # MCP requires dict responses, so wrap lists in a dict
            if isinstance(data, list):
                return {"results": data}
            return data
        return {"status": "success", "status_code": response.status_code}
    except httpx.HTTPStatusError as e:
        error_detail = ""
        try:
            error_detail = e.response.json()
        except:
            error_detail = e.response.text
        return {
            "error": f"HTTP {e.response.status_code}",
            "detail": error_detail,
            "status_code": e.response.status_code
        }
    except Exception as e:
        return {"error": str(e)}


@mcp.tool()
async def search_products(
    product_name: Optional[str] = None,
    category: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for products by various fields with partial matching

    Args:
        product_name: Filter by product name (partial matching, optional)
        category: Filter by category (partial matching, optional)

    Returns:
        List of products matching the search criteria
    """
    params = {}

    if product_name:
        params["productName"] = product_name
    if category:
        params["category"] = category

    client = await get_http_client()
    response = await client.get("/api/products", params=params)
    return await handle_response(response)


@mcp.tool()
async def get_product(product_id: str) -> Dict[str, Any]:
    """
    Get product by ID

    Retrieves a single product record by its unique identifier

    Args:
        product_id: The unique 5-character identifier of the product

    Returns:
        Product details including productId, productName, category, price,
        inStock, description, createdAt, and updatedAt
    """
    client = await get_http_client()
    response = await client.get(f"/api/products/{product_id}")
    return await handle_response(response)


@mcp.tool()
async def create_product(
    product_id: str,
    product_name: str,
    category: str,
    price: float,
    in_stock: bool,
    description: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new product

    Creates a new product record with the provided information

    Args:
        product_id: Unique 5-character product identifier (e.g., "PRD01")
        product_name: Name of the product
        category: Product category
        price: Product price (must be > 0)
        in_stock: Whether the product is currently in stock
        description: Optional product description

    Returns:
        The created product details
    """
    payload = {
        "productId": product_id,
        "productName": product_name,
        "category": category,
        "price": price,
        "inStock": in_stock,
    }
    if description:
        payload["description"] = description

    client = await get_http_client()
    response = await client.post("/api/products", json=payload)
    return await handle_response(response)


@mcp.tool()
async def update_product(
    product_id: str,
    product_name: str,
    category: str,
    price: float,
    in_stock: bool,
    description: Optional[str] = None
) -> Dict[str, Any]:
    """
    Update an existing product

    Updates all fields of an existing product record

    Args:
        product_id: The product ID to update (path parameter)
        product_name: Updated product name
        category: Updated category
        price: Updated price (must be > 0)
        in_stock: Updated stock status
        description: Updated description (optional)

    Returns:
        The updated product details
    """
    payload = {
        "productName": product_name,
        "category": category,
        "price": price,
        "inStock": in_stock,
    }
    if description:
        payload["description"] = description

    client = await get_http_client()
    response = await client.put(f"/api/products/{product_id}", json=payload)
    return await handle_response(response)


@mcp.tool()
async def delete_product(product_id: str) -> Dict[str, Any]:
    """
    Delete a product

    Permanently deletes a product record

    Args:
        product_id: The unique identifier of the product to delete

    Returns:
        Confirmation of deletion
    """
    client = await get_http_client()
    response = await client.delete(f"/api/products/{product_id}")
    return await handle_response(response)


async def cleanup():
    """Cleanup resources."""
    global http_client
    if http_client:
        await http_client.aclose()
        http_client = None


if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)

    # Log configuration
    logger.info("=" * 60)
    logger.info("Product MCP Server Configuration:")
    logger.info(f"  PRODUCT_API_BASE_URL: {BASE_URL}")
    logger.info(f"  PORT_FOR_PRODUCT_MCP: {port}")
    logger.info(f"  HOST_FOR_PRODUCT_MCP: {host}")
    logger.info("=" * 60)

    try:
        mcp.run(transport="http", port=port, host=host)
    finally:
        asyncio.run(cleanup())
```

---

### Generated File: `fantaco-mcp-servers/product-mcp/requirements.txt`

```
fastmcp==2.13.3
python-dotenv==1.2.1
```

---

### Generated File: `fantaco-mcp-servers/product-mcp/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY product-api-mcp-server.py .

# Run the MCP server
CMD ["python", "product-api-mcp-server.py"]
```

---

### Generated File: `fantaco-mcp-servers/product-mcp-kubernetes/mcp-server-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-product
  labels:
    app: mcp-product
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-product
  template:
    metadata:
      labels:
        app: mcp-product
    spec:
      containers:
      - name: mcp-server
        image: quay.io/burrsutter/mcp-server-product:1.0.0
        imagePullPolicy: Always
        env:
        - name: PRODUCT_API_BASE_URL
          value: http://fantaco-product-service:8083
        ports:
        - containerPort: 9003
          name: http
          protocol: TCP
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
```

---

### Generated File: `fantaco-mcp-servers/product-mcp-kubernetes/mcp-server-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mcp-product-service
  labels:
    app: mcp-product
spec:
  type: ClusterIP
  selector:
    app: mcp-product
  ports:
  - port: 9003
    targetPort: 9003
    protocol: TCP
    name: http
```

---

### Generated File: `fantaco-mcp-servers/product-mcp-kubernetes/mcp-server-route.yaml`

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: mcp-product-route
  labels:
    app: mcp-product
spec:
  to:
    kind: Service
    name: mcp-product-service
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

---

### Helm Chart Integration

Add a new section to `helm/fantaco-mcp/values.yaml`:

```yaml
product:
  enabled: true
  name: mcp-product
  replicas: 1
  image:
    repository: quay.io/burrsutter/mcp-server-product
    tag: 1.0.0
    pullPolicy: Always
  service:
    name: mcp-product-service
    port: 9003
    targetPort: 9003
  route:
    enabled: true
    name: mcp-product-route
    tls:
      termination: edge
      insecureEdgeTerminationPolicy: Redirect
  env:
    productApiBaseUrl: http://fantaco-product-service:8083
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 500m
```

Add these Helm templates:

**`helm/fantaco-mcp/templates/product-deployment.yaml`**

```yaml
{{- if .Values.product.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.product.name }}
  labels:
    app: {{ .Values.product.name }}
spec:
  replicas: {{ .Values.product.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.product.name }}
  template:
    metadata:
      labels:
        app: {{ .Values.product.name }}
    spec:
      containers:
      - name: mcp-server
        image: {{ .Values.product.image.repository }}:{{ .Values.product.image.tag }}
        imagePullPolicy: {{ .Values.product.image.pullPolicy }}
        env:
        - name: PRODUCT_API_BASE_URL
          value: {{ .Values.product.env.productApiBaseUrl | quote }}
        ports:
        - containerPort: {{ .Values.product.service.port }}
          name: http
          protocol: TCP
        resources:
          requests:
            memory: {{ .Values.product.resources.requests.memory }}
            cpu: {{ .Values.product.resources.requests.cpu }}
          limits:
            memory: {{ .Values.product.resources.limits.memory }}
            cpu: {{ .Values.product.resources.limits.cpu }}
{{- end }}
```

**`helm/fantaco-mcp/templates/product-service.yaml`**

```yaml
{{- if .Values.product.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.product.service.name }}
  labels:
    app: {{ .Values.product.name }}
spec:
  type: ClusterIP
  selector:
    app: {{ .Values.product.name }}
  ports:
  - port: {{ .Values.product.service.port }}
    targetPort: {{ .Values.product.service.targetPort }}
    protocol: TCP
    name: http
{{- end }}
```

**`helm/fantaco-mcp/templates/product-route.yaml`**

```yaml
{{- if and .Values.product.enabled .Values.product.route.enabled }}
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {{ .Values.product.route.name }}
  labels:
    app: {{ .Values.product.name }}
spec:
  to:
    kind: Service
    name: {{ .Values.product.service.name }}
  port:
    targetPort: http
  tls:
    termination: {{ .Values.product.route.tls.termination }}
    insecureEdgeTerminationPolicy: {{ .Values.product.route.tls.insecureEdgeTerminationPolicy }}
{{- end }}
```

---

## Template Rules (How to Generalize)

### Tool Function Pattern for CRUD APIs (GET with query params)

```python
@mcp.tool()
async def search_<entities>(
    <snake_case_param1>: Optional[str] = None,
    <snake_case_param2>: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for <entities> by various fields with partial matching

    Args:
        <snake_case_param1>: Filter by <field> (partial matching, optional)
        <snake_case_param2>: Filter by <field> (partial matching, optional)

    Returns:
        List of <entities> matching the search criteria
    """
    params = {}
    if <snake_case_param1>:
        params["<camelCaseParam1>"] = <snake_case_param1>
    if <snake_case_param2>:
        params["<camelCaseParam2>"] = <snake_case_param2>

    client = await get_http_client()
    response = await client.get("/api/<entities>", params=params)
    return await handle_response(response)
```

### Tool Function Pattern for CRUD APIs (GET by ID)

```python
@mcp.tool()
async def get_<entity>(<entity_id>: str) -> Dict[str, Any]:
    """
    Get <entity> by ID

    Args:
        <entity_id>: The unique identifier of the <entity>

    Returns:
        <Entity> details
    """
    client = await get_http_client()
    response = await client.get(f"/api/<entities>/{<entity_id>}")
    return await handle_response(response)
```

### Tool Function Pattern for CRUD APIs (POST create)

```python
@mcp.tool()
async def create_<entity>(
    <snake_field1>: str,
    <snake_field2>: str,
    <optional_field>: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new <entity>

    Args:
        <snake_field1>: ...
        <snake_field2>: ...

    Returns:
        The created <entity> details
    """
    payload = {
        "<camelField1>": <snake_field1>,
        "<camelField2>": <snake_field2>,
    }
    if <optional_field>:
        payload["<camelOptionalField>"] = <optional_field>

    client = await get_http_client()
    response = await client.post("/api/<entities>", json=payload)
    return await handle_response(response)
```

### Tool Function Pattern for Action APIs (POST action)

```python
@mcp.tool()
async def <action_name>(
    <snake_param1>: str,
    <snake_param2>: Optional[str] = None
) -> Dict[str, Any]:
    """
    <Action description>

    Args:
        <snake_param1>: ...
        <snake_param2>: ...

    Returns:
        Dictionary with success, message, and data
    """
    payload = {
        "<camelParam1>": <snake_param1>,
    }
    if <snake_param2>:
        payload["<camelParam2>"] = <snake_param2>

    client = await get_http_client()
    response = await client.post("/api/<domain>/<action-path>", json=payload)
    return await handle_response(response)
```

---

## Key Patterns

### snake_case to camelCase Mapping

MCP tool parameters use Python `snake_case`, but the REST API expects `camelCase`. Always map:

| MCP parameter | REST API field |
|---------------|---------------|
| `product_name` | `productName` |
| `company_name` | `companyName` |
| `contact_email` | `contactEmail` |
| `customer_id` | `customerId` |
| `start_date` | `startDate` |
| `in_stock` | `inStock` |

### List Wrapping for MCP Compatibility

MCP tools must return `Dict[str, Any]`, not raw lists. The `handle_response` function wraps list responses:

```python
if isinstance(data, list):
    return {"results": data}
```

### Lazy HTTP Client

The HTTP client is created lazily on first use and reused for all subsequent calls:

```python
http_client: Optional[httpx.AsyncClient] = None

async def get_http_client() -> httpx.AsyncClient:
    global http_client
    if http_client is None:
        http_client = httpx.AsyncClient(base_url=BASE_URL, timeout=30.0)
    return http_client
```

### Cleanup on Shutdown

Always close the HTTP client on shutdown:

```python
async def cleanup():
    global http_client
    if http_client:
        await http_client.aclose()
        http_client = None
```

### Environment Variable Naming

| Variable | Format | Example |
|----------|--------|---------|
| Backend URL | `<SERVICE>_API_BASE_URL` | `PRODUCT_API_BASE_URL` |
| MCP port | `PORT_FOR_<SERVICE>_MCP` | `PORT_FOR_PRODUCT_MCP` |
| MCP host | `HOST_FOR_<SERVICE>_MCP` | `HOST_FOR_PRODUCT_MCP` |

---

## Port Assignment Convention

MCP servers use ports starting at 9001:

| MCP Server | Port |
|------------|------|
| Customer MCP | 9001 |
| Finance MCP | 9002 |
| (next MCP) | 9003 |
| (next MCP) | 9004 |

---

## Conventions Checklist

- [ ] Single Python file named `<service>-api-mcp-server.py`
- [ ] FastMCP with `transport="http"` (not stdio)
- [ ] `httpx.AsyncClient` with `base_url` and `timeout=30.0`
- [ ] All tools decorated with `@mcp.tool()`
- [ ] Full docstrings with Args/Returns on every tool
- [ ] `handle_response` wraps lists in `{"results": data}`
- [ ] `handle_response` catches `HTTPStatusError` and generic exceptions
- [ ] `Optional[str] = None` for optional parameters
- [ ] snake_case parameters mapped to camelCase in API payloads
- [ ] `load_dotenv()` for local `.env` file support
- [ ] Startup logging with configuration details
- [ ] `requirements.txt` with pinned versions: `fastmcp==2.13.3`, `python-dotenv==1.2.1`
- [ ] `python:3.11-slim` Docker base image
- [ ] K8s: Deployment + Service (ClusterIP) + Route (edge TLS)
- [ ] K8s: Backend URL passed as environment variable in deployment
- [ ] K8s resources: 128Mi/100m requests, 256Mi/500m limits
- [ ] Helm: values.yaml section with `enabled` toggle, image, service, route, env, resources
- [ ] Helm: conditional templates with `{{- if .Values.<service>.enabled }}`

---

## Wrapping Action-Based APIs

When wrapping an action-based API (REST_ACTION_SPEC), the tools call POST endpoints and pass JSON bodies. Example for the Finance service:

```python
@mcp.tool()
async def fetch_order_history(
    customer_id: str,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    limit: int = 50
) -> Dict[str, Any]:
    """
    Get order history for a customer.

    Args:
        customer_id: Unique identifier for the customer (e.g., "CUST-12345")
        start_date: Start date in ISO 8601 format (optional)
        end_date: End date in ISO 8601 format (optional)
        limit: Maximum number of orders to return (default: 50)

    Returns:
        Dictionary with success, message, data (list of orders), and count
    """
    payload = {
        "customerId": customer_id,
        "limit": limit
    }
    if start_date:
        payload["startDate"] = start_date
    if end_date:
        payload["endDate"] = end_date

    client = await get_http_client()
    response = await client.post("/api/finance/orders/history", json=payload)
    return await handle_response(response)
```

The key differences from CRUD wrapping:
- All tools use `client.post()` instead of `client.get()`
- Parameters go in JSON body, not query params
- Responses are already wrapped in `{ success, message, data }` by the backend
