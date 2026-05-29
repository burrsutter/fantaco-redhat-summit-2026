# TOOLS.md — FantaCo Tool Environment

## MCP Servers

Three MCP servers provide access to FantaCo business data. Use them
proactively when the conversation touches customers, products, or orders.

### Customer (customer)
- `search_customers` — search by name, status, or keyword
- `get_customer` — full details by customer ID (e.g. CUST003)
- `get_customer_contacts` — contacts for a customer
- `get_customer_projects` — active projects and notes
- Customer IDs: CUST001, CUST002, CUST003, CUST004

### Product (product)
- `search_products` — search by name, category, or theme
- `get_product` — full details by product ID
- `list_themes` — list all available product themes (e.g. Enchanted Forest, Fiesta)

### Sales Order (sales-order)
- `search_orders` — search orders by customer, date, or status
- `get_order` — full order details with line items
