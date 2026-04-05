# FantaCo MCP Servers

This directory contains the MCP servers that expose FantaCo backend capabilities to agentic clients such as OpenClaw.

These servers let a user like Sally Sellers move across customer CRM, sales orders, invoices, product catalog data, sales policy knowledge, and internal employee systems using a consistent MCP interface.

## MCP Server Overview

| MCP Server | Directory | Default Port | Backend / Purpose |
|---|---|---:|---|
| Customer MCP | `customer-mcp` | 9001 | Customer CRM plus customer project data |
| Finance MCP | `finance-mcp` | 9002 | Invoice lookup and billing history |
| Product MCP | `product-mcp` | 9003 | Product catalog and Imagination Pod theme-aware catalog management |
| Sales Order MCP | `sales-order-mcp` | 9004 | Sales order lookup |
| HR Recruiting MCP | `hr-recruiting-mcp` | 9005 | Internal recruiting jobs and applications |
| Sales Policy Search MCP | `sales-policy-search-mcp` | 9006 | RAG search over sales policy documents |
| HR Policy Search MCP | `hr-policy-mcp` | 9007 | RAG search over employee HR policy documents |

## Demo-Oriented Usage

These MCP servers are designed to support a workflow like the one in `DEMO_SCRIPT.MD`.

Examples:

- `Who are my customers?`
  - Customer MCP
- `What are Tech Solutions recent orders?`
  - Customer MCP to resolve the account
  - Sales Order MCP to inspect orders
- `Who are the contacts?`
  - Customer MCP
- `Any notes associated with Tech Solutions?`
  - Customer MCP
- `Any projects for Tech Solutions?`
  - Customer MCP
- `What is our return sales policy?`
  - Sales Policy Search MCP
- `How is the 401K handled here at FantaCo?`
  - HR Policy Search MCP

Important framing:

- FantaCo is not an HR benefits company.
- HR policy and recruiting MCP servers are for internal employee and recruiting workflows.
- Customer-facing and sales-facing demo flows should usually center on Customer, Sales Order, Finance, Product, and Sales Policy Search MCP servers.

## Server Capabilities

### Customer MCP

Directory: `customer-mcp`

Best for:

- Resolving a customer account by name
- Finding Sally Sellers' assigned customers
- Looking up contacts, CRM notes, and assigned sales reps
- Exploring customer projects, project notes, milestones, statuses, and themes

Example questions:

- `Who are my customers?`
- `Who are the contacts for Tech Solutions?`
- `Any notes associated with Tech Solutions?`
- `Any projects for Tech Solutions?`
- `Which projects are on hold?`

### Finance MCP

Directory: `finance-mcp`

Best for:

- Listing invoices
- Looking up invoices for a customer
- Looking up invoices tied to a sales order
- Retrieving recent invoice history

Example questions:

- `Show recent invoices for Tech Solutions`
- `Has order ORD-2025-0001 been invoiced?`

### Product MCP

Directory: `product-mcp`

Best for:

- Searching the catalog
- Looking up products by SKU
- Managing product records
- Understanding valid Imagination Pod theme tokens

Example questions:

- `Show products for the Enchanted Forest theme`
- `What themes are valid for Imagination Pod products?`

### Sales Order MCP

Directory: `sales-order-mcp`

Best for:

- Searching sales orders by customer or status
- Retrieving a specific order with line items

Example questions:

- `What are Tech Solutions recent orders?`
- `Show order ORD-2025-0001`

### Sales Policy Search MCP

Directory: `sales-policy-search-mcp`

Best for:

- Natural-language policy questions
- Reviewing sales policy knowledge-base contents
- Maintaining the sales policy RAG corpus

Example questions:

- `What is our return sales policy?`
- `What discount rules apply to service projects?`

### HR Policy Search MCP

Directory: `hr-policy-mcp`

Best for:

- Internal employee HR policy questions
- Reviewing HR policy knowledge-base contents
- Maintaining the HR policy RAG corpus

Example questions:

- `How is the 401K handled here at FantaCo?`
- `How many vacation days do I get?`

### HR Recruiting MCP

Directory: `hr-recruiting-mcp`

Best for:

- Internal recruiting workflows
- Managing jobs and applications

Example questions:

- `What open jobs do we have?`
- `Show applications for job-001`

## Local Setup Pattern

Each MCP server follows the same basic pattern:

```bash
cd fantaco-mcp-servers/<server-directory>
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python <server-entrypoint>.py
```

Then use:

```bash
mcp-inspector
```

Example inspector image:

![mcp inspector customer](./images/mcp-inspector-customer-1.png)

## Environment Variables

Each server expects a backend base URL and optional host/port overrides.

### Customer MCP

```env
CUSTOMER_API_BASE_URL=http://localhost:8081
PORT_FOR_CUSTOMER_MCP=9001
HOST_FOR_CUSTOMER_MCP=0.0.0.0
```

### Finance MCP

```env
FINANCE_API_BASE_URL=http://localhost:8082
PORT_FOR_FINANCE_MCP=9002
HOST_FOR_FINANCE_MCP=0.0.0.0
```

### Product MCP

```env
PRODUCT_API_BASE_URL=http://localhost:8083
PORT_FOR_PRODUCT_MCP=9003
HOST_FOR_PRODUCT_MCP=0.0.0.0
```

### Sales Order MCP

```env
SALES_ORDER_API_BASE_URL=http://localhost:8084
PORT_FOR_SALES_ORDER_MCP=9004
HOST_FOR_SALES_ORDER_MCP=0.0.0.0
```

### HR Recruiting MCP

```env
HR_RECRUITING_API_BASE_URL=http://localhost:8085
PORT_FOR_HR_RECRUITING_MCP=9005
HOST_FOR_HR_RECRUITING_MCP=0.0.0.0
```

### Sales Policy Search MCP

```env
SALES_POLICY_SEARCH_API_BASE_URL=http://localhost:8090
PORT_FOR_SALES_POLICY_SEARCH_MCP=9006
HOST_FOR_SALES_POLICY_SEARCH_MCP=0.0.0.0
```

### HR Policy Search MCP

```env
HR_POLICY_SEARCH_API_BASE_URL=http://localhost:8091
PORT_FOR_HR_POLICY_MCP=9007
HOST_FOR_HR_POLICY_MCP=0.0.0.0
```

## Quick Start Examples

### Customer MCP

```bash
cd fantaco-mcp-servers/customer-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export CUSTOMER_API_BASE_URL=http://localhost:8081
python customer-api-mcp-server.py
```

### Finance MCP

```bash
cd fantaco-mcp-servers/finance-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export FINANCE_API_BASE_URL=http://localhost:8082
python finance-api-mcp-server.py
```

### Product MCP

```bash
cd fantaco-mcp-servers/product-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export PRODUCT_API_BASE_URL=http://localhost:8083
python product-api-mcp-server.py
```

### Sales Order MCP

```bash
cd fantaco-mcp-servers/sales-order-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export SALES_ORDER_API_BASE_URL=http://localhost:8084
python sales-order-api-mcp-server.py
```

### HR Recruiting MCP

```bash
cd fantaco-mcp-servers/hr-recruiting-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export HR_RECRUITING_API_BASE_URL=http://localhost:8085
python hr-recruiting-api-mcp-server.py
```

### Sales Policy Search MCP

```bash
cd fantaco-mcp-servers/sales-policy-search-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export SALES_POLICY_SEARCH_API_BASE_URL=http://localhost:8090
python sales-policy-search-api-mcp-server.py
```

### HR Policy Search MCP

```bash
cd fantaco-mcp-servers/hr-policy-mcp
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export HR_POLICY_SEARCH_API_BASE_URL=http://localhost:8091
python hr-policy-search-api-mcp-server.py
```

## Kubernetes / OpenShift Manifests

This repo also includes Kubernetes/OpenShift manifests for each MCP server:

- `customer-mcp-kubernetes/`
- `finance-mcp-kubernetes/`
- `product-mcp-kubernetes/`
- `sales-order-mcp-kubernetes/`
- `sales-policy-search-mcp-kubernetes/`
- `hr-policy-mcp-kubernetes/`
- `hr-recruiting-mcp-kubernetes/`

Typical deployment pattern:

```bash
kubectl apply -f <server-kubernetes-directory>/
```

The exact route/host value will depend on your cluster and manifest configuration.

## Notes

- The tool descriptions inside each server file were written to help an agent choose the right tool for a user prompt, not just to describe the raw backend API.
- Customer project lookup and update flows are exposed today.
- If your demo requires project creation through MCP, confirm the backend and MCP tool surface support that workflow before the live run.
