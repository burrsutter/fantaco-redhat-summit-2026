# FantaCo OpenClaw Skills

Skills for [OpenClaw](https://docs.openclaw.ai) that provide guided agent behaviors on top of the FantaCo MCP servers.

## Skills

| Skill | Slash Command | MCP Servers Used | Description |
|-------|---------------|------------------|-------------|
| `customer-lookup` | `/customer_lookup` | Customer | Search and retrieve customer records |
| `order-status` | `/order_status` | Sales Order | Check order status and line items |
| `invoice-lookup` | `/invoice_lookup` | Finance | Find invoices by customer, order, or date range |
| `product-search` | `/product_search` | Product | Browse and manage the product catalog |
| `customer-360` | `/customer_360` | Customer + Sales Order + Finance | Comprehensive customer view across all systems |

## Prerequisites

The corresponding MCP servers must be configured in OpenClaw's `openclaw.json` before these skills will activate. Each skill declares its required MCP servers via `metadata.openclaw.requires.config`.

Example `openclaw.json` MCP server entries (in-cluster URLs):

```json
{
  "mcpServers": {
    "customer": {
      "transport": "streamable-http",
      "url": "http://mcp-customer-service:9001/mcp"
    },
    "finance": {
      "transport": "streamable-http",
      "url": "http://mcp-finance-service:9002/mcp"
    },
    "product": {
      "transport": "streamable-http",
      "url": "http://mcp-product-service:9003/mcp"
    },
    "sales-order": {
      "transport": "streamable-http",
      "url": "http://mcp-sales-order-service:9004/mcp"
    }
  }
}
```

Use `inject-mcp-openclaw.sh` at the repo root to add MCP servers to a running OpenClaw pod interactively.

## Loading Skills into OpenClaw

### Option 1: Copy into the pod

```bash
OPENCLAW_POD=$(oc get pods -l app=openclaw -o jsonpath='{.items[0].metadata.name}')

# Copy all skills
oc cp skills/ $OPENCLAW_POD:/home/node/.openclaw/workspace/skills/

# Restart the pod to pick up changes
oc delete pod $OPENCLAW_POD
```

### Option 2: Mount via ConfigMap

```bash
# Create a ConfigMap from the skills folder
oc create configmap fantaco-skills \
  --from-file=customer-lookup/SKILL.md=skills/customer-lookup/SKILL.md \
  --from-file=order-status/SKILL.md=skills/order-status/SKILL.md \
  --from-file=invoice-lookup/SKILL.md=skills/invoice-lookup/SKILL.md \
  --from-file=product-search/SKILL.md=skills/product-search/SKILL.md \
  --from-file=customer-360/SKILL.md=skills/customer-360/SKILL.md
```

Then mount the ConfigMap into the OpenClaw deployment at `/home/node/.openclaw/workspace/skills/`.

### Option 3: Extra dirs in openclaw.json

Point OpenClaw at a custom path without moving files:

```json
{
  "skills": {
    "load": {
      "extraDirs": ["/opt/fantaco/skills"]
    }
  }
}
```
