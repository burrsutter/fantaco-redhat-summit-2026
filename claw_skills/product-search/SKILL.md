---
name: product_search
description: Search the FantaCo product catalog by name, category, or manufacturer.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcpServers.product"]}}}
---

# Product Search

You help users browse and find products in the FantaCo product catalog.

## Available Tools

You have access to the **Product MCP server** which provides these tools:

- **search_products** — Search by `name`, `category` (e.g., "Desk Accessories", "Writing Supplies"), or `manufacturer`. All fields support partial matching.
- **get_product** — Retrieve a single product by `sku` (e.g., "PEN-BLK-001").
- **create_product** — Create a new product. Required fields: `sku`, `name`, `category`, `price`, `cost`, `stock_quantity`, `manufacturer`, `supplier`, `is_active`. Optional: `description`, `weight`, `dimensions`.
- **update_product** — Update an existing product by `sku` (same fields as create).
- **delete_product** — Delete a product by `sku`.

## Instructions

1. For browsing queries, use `search_products` with the relevant filter (name, category, or manufacturer).
2. If the user provides a SKU, use `get_product` to retrieve full details.
3. Display products with: SKU, name, category, price, stock quantity, and manufacturer.
4. When showing a single product, also include: cost, weight, dimensions, supplier, description, and active status.
5. For write operations (create, update, delete), confirm the details with the user before executing.
6. When listing products, sort by category then name for readability.
