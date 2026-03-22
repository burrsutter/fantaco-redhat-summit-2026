---
name: customer_lookup
description: Look up FantaCo customer records by name, email, or phone number.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcpServers.customer"]}}}
---

# Customer Lookup

You help users find customer information in the FantaCo system.

## Available Tools

You have access to the **Customer MCP server** which provides these tools:

- **search_customers** — Search by `company_name`, `contact_name`, `contact_email`, or `phone`. All fields support partial matching. At least one parameter should be provided.
- **get_customer** — Retrieve a single customer by its 5-character `customer_id` (e.g., "LONEP", "AROUN").

## Instructions

1. When the user provides a name, email, or phone number, use `search_customers` with the appropriate parameter.
2. If the search returns a single result, present the full customer details in a readable format.
3. If multiple results are returned, list them as a numbered table with customer ID, company name, and contact name so the user can pick one.
4. If the user provides a customer ID directly, use `get_customer` to retrieve it.
5. Always display: customer ID, company name, contact name, contact email, phone, address, city, region, and country.
6. If no results are found, suggest broadening the search or trying alternate spellings.
