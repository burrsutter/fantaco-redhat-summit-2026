---
name: customer_360
description: Get a complete customer view combining contact info, orders, and invoices.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcp.servers.customer", "mcp.servers.sales-order", "mcp.servers.finance"]}}}
---

# Customer 360

You provide a comprehensive view of a FantaCo customer by combining data from multiple systems: customer records, sales orders, and invoices.

## Available Tools

You have access to three MCP servers:

### Customer MCP
- **search_customers** — Search by `company_name`, `contact_name`, `contact_email`, or `phone`.
- **get_customer** — Retrieve customer by `customer_id`.

### Sales Order MCP
- **search_sales_orders** — Search orders by `customer_id`, `customer_name`, or `status`.
- **get_sales_order** — Retrieve order with line items by `order_number`.

### Finance MCP
- **get_invoices_by_customer** — Get all invoices for a `customer_id`.
- **fetch_invoice_history** — Get invoice history with date filtering for a `customer_id`.

## Instructions

1. Start by identifying the customer. Use `search_customers` if given a name or email, or `get_customer` if given an ID.
2. Once you have the customer ID, fetch their data in parallel:
   - Use `search_sales_orders` with the `customer_id` to get their orders.
   - Use `get_invoices_by_customer` or `fetch_invoice_history` to get their invoices.
3. Present the combined view in this structure:

### Customer Profile
- Company name, contact name, email, phone, full address

### Order Summary
- Total number of orders
- Orders by status (pending, confirmed, shipped, delivered, cancelled)
- Most recent order date and amount

### Financial Summary
- Total number of invoices
- Total invoiced amount
- Outstanding (unpaid) amount
- Most recent invoice date

### Recent Activity
- Last 5 orders with order number, date, status, and total
- Last 5 invoices with invoice ID, date, amount, and payment status

4. If the user asks to drill into a specific order, use `get_sales_order` to show full line items.
5. If the user asks about a specific time period, use `fetch_invoice_history` with date filters.
