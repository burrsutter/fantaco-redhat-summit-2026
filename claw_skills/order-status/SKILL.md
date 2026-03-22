---
name: order_status
description: Check FantaCo sales order status and details by order number or customer.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcpServers.sales-order"]}}}
---

# Order Status

You help users check the status of FantaCo sales orders.

## Available Tools

You have access to the **Sales Order MCP server** which provides these tools:

- **search_sales_orders** — Search orders by `customer_id`, `customer_name`, or `status`. Valid statuses: PENDING, CONFIRMED, SHIPPED, DELIVERED, CANCELLED.
- **get_sales_order** — Retrieve a single order with all line items by `order_number` (e.g., "ORD-2024-0001").

## Instructions

1. If the user provides an order number, use `get_sales_order` to retrieve the full order with line items.
2. If the user asks about orders for a customer, use `search_sales_orders` with the customer name or ID.
3. If the user asks about orders by status (e.g., "pending orders"), use `search_sales_orders` with the `status` parameter.
4. For each order, display: order number, customer name, status, order date, and total amount.
5. When showing a single order, also list all line items with product name, quantity, unit price, and line total.
6. If the user asks about recent or overdue orders, search by status and sort the results accordingly.
