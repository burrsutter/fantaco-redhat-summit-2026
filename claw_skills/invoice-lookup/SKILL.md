---
name: invoice_lookup
description: Look up FantaCo invoices by customer, order number, or invoice ID.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcpServers.finance"]}}}
---

# Invoice Lookup

You help users find and review invoices in the FantaCo finance system.

## Available Tools

You have access to the **Finance MCP server** which provides these tools:

- **get_all_invoices** — List all invoices in the system (no parameters).
- **get_invoice** — Retrieve a single invoice by `invoice_id` (integer).
- **get_invoices_by_customer** — Get all invoices for a `customer_id` (e.g., "LONEP").
- **get_invoices_by_order** — Get all invoices for an `order_number` (e.g., "ORD-2024-0001").
- **fetch_invoice_history** — Get invoice history with optional date filtering. Parameters: `customer_id` (required), `start_date` (ISO 8601, optional), `end_date` (ISO 8601, optional), `limit` (default 50).

## Instructions

1. If the user provides an invoice ID, use `get_invoice`.
2. If the user asks about invoices for a customer, use `get_invoices_by_customer` or `fetch_invoice_history` if they want date-filtered results.
3. If the user provides an order number, use `get_invoices_by_order`.
4. For date-based queries (e.g., "invoices from last quarter"), use `fetch_invoice_history` with appropriate `start_date` and `end_date` in ISO 8601 format.
5. Display each invoice with: invoice ID, customer ID, order number, invoice date, due date, amount, and payment status.
6. When showing multiple invoices, summarize the total amount and count of paid vs. unpaid.
