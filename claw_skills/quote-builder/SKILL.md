---
name: quote_builder
description: Build a themed project quote for a customer with products, pricing, and a project summary.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcp.servers.customer", "mcp.servers.product", "mcp.servers.sales-order"]}}}
---

# Quote Builder

You build themed Imagination Pod project quotes for FantaCo customers. Given a customer name and a theme, you assemble a draft proposal with recommended products, pricing, and a ready-to-create project summary.

## Available Tools

You have access to three MCP servers:

### Customer MCP
- **search_customers** — Search by `company_name`, `contact_name`, `contact_email`, or `phone`.
- **get_customer** — Retrieve customer by `customer_id`.
- **get_customer_detail** — Get full CRM view including notes, contacts, and sales reps.
- **get_customer_contacts** — Get all contacts at a customer account.
- **get_customer_projects** — List projects with optional `status` and `theme` filtering.
- **create_project** — Create a new Imagination Pod project for a customer.

### Product MCP
- **search_products** — Search catalog by `name`, `category`, `manufacturer`, or `theme`.
- **list_pod_themes** — List valid Imagination Pod theme tokens.

### Sales Order MCP
- **search_sales_orders** — Search orders by `customer_id`, `customer_name`, or `status`.

## Instructions

### 1. Parse the Input

The user will invoke this skill as: `/quote_builder <customer>, <theme>`

Extract two parts:
- **Customer** — a company name, contact name, or customer ID (everything before the first comma)
- **Theme** — an Imagination Pod theme (everything after the first comma)

Valid themes: `ENCHANTED_FOREST`, `INTERSTELLAR_SPACESHIP`, `SPEAKEASY_1920S`, `ZEN_GARDEN`, `CUSTOM`.

If the theme is missing, ambiguous, or doesn't match a known theme, call `list_pod_themes` and ask the user to pick one.

### 2. Resolve the Customer

Use `search_customers` with the customer name. If the search returns multiple results, list them and ask the user to pick one. Once you have the customer ID, use `get_customer_detail` to get the full profile.

### 3. Gather Data in Parallel

Fetch all of the following at the same time:
- `search_products` filtered by the selected `theme` — these are the products to include in the quote.
- `get_customer_projects` for this customer — check if they already have a project with the same theme.
- `search_sales_orders` by `customer_id` — get recent order history for spending context.

### 4. Check for Duplicate Projects

If the customer already has an active project with the same theme (status is not CANCELLED or COMPLETED), warn the user:

> **Heads up:** {customer} already has an active {theme} project ({project ID}, status: {status}). Do you still want to build a new quote for this theme?

Wait for confirmation before continuing.

### 5. Present the Draft Quote

Format the quote as follows:

---

**DRAFT QUOTE — {Theme} Imagination Pod**

**Customer:** {company name}
**Primary Contact:** {contact name} ({email})
**Theme:** {theme display name}

**Recommended Products:**

| SKU | Product | Unit Price | Suggested Qty | Line Total |
|-----|---------|-----------|---------------|------------|
| ... | ...     | ...       | ...           | ...        |

**Estimated Total:** ${sum of all line totals}

**Recent Order History** (spending context):

| Order # | Date | Status | Total |
|---------|------|--------|-------|
| ...     | ...  | ...    | ...   |

**Next Steps:** Say **"approve"** to create this as a new Imagination Pod project for {customer}, or ask me to adjust quantities or swap products.

---

#### Product quantity guidelines:
- Set suggested quantity to **1** for each product unless the product category or name suggests bulk use (e.g., decorations, supplies), in which case suggest **2–5**.
- Show all matching products from the theme — the user can adjust before approving.

### 6. Handle Approval

If the user says "approve" (or similar confirmation):

1. Use `create_project` on the Customer MCP to create a new Imagination Pod project with:
   - The customer ID
   - The selected theme
   - A project name like "{Theme} Imagination Pod for {Company Name}"
   - Status: PLANNING
2. Confirm the project was created and display the new project ID.
3. Suggest the user can now use `/customer_360 {customer}` to see the full updated view.

### 7. Handle Adjustments

If the user asks to change quantities, add/remove products, or switch themes:
- Update the quote accordingly.
- Re-display the updated draft quote.
- Wait for approval again.
