---
name: watchlist_manager
description: Add, remove, or list projects being monitored by the Account Watchdog.
user-invocable: true
metadata: {"openclaw": {"requires": {"config": ["mcp.servers.customer"]}}}
---

# Watchlist Manager

Manage the Account Watchdog's project watchlist. You can add projects to be monitored, remove them, or list what's currently being watched.

## Watchlist Location

The watchdog's watchlist file is at:

```
/home/node/.openclaw/workspace/watchdog/watchlist.json
```

This is a JSON array of watch entries. Each entry has this format:

```json
{
  "customerId": "CUST003",
  "customerName": "Tech Solutions Ltd",
  "projectId": 1,
  "projectName": "Enchanted Forest Pod",
  "addedAt": "2026-04-06T14:30:00Z",
  "addedBy": "Sally Sellers"
}
```

## Available Tools

### Customer MCP
- **search_customers** — Search by `company_name`, `contact_name`, `contact_email`, or `phone`.
- **get_customer** — Retrieve customer by `customer_id`.
- **get_customer_projects** — List projects for a customer, with optional `status` filter.

### File Operations
- **Read** the watchlist file to see current entries.
- **Write** the watchlist file to add or remove entries.

## Instructions

Parse the user's message to determine the action: **add**, **remove**, or **list**.

### Detecting the Action

| User says | Action |
|-----------|--------|
| "watch", "monitor", "add to watchlist", "keep an eye on" | **ADD** |
| "stop watching", "unwatch", "remove from watchlist", "stop monitoring" | **REMOVE** |
| "what are you watching", "show watchlist", "list watched", "watchlist" | **LIST** |

### ADD — Watch a project

1. Extract the customer name and project reference from the user's message.
2. Use `search_customers` to resolve the customer. If multiple matches, ask the user to pick one.
3. Use `get_customer_projects` to list the customer's projects. If the user specified a project by name or number, match it. If there are multiple projects and the user didn't specify, list them and ask.
4. Read the current watchlist from `/home/node/.openclaw/workspace/watchdog/watchlist.json`.
5. Check if this customer+project combination is already in the watchlist. If so, tell the user: "Already watching {projectName} for {customerName}."
6. Append a new entry with the current timestamp and `"addedBy": "Sally Sellers"`.
7. Write the updated array back to the watchlist file.
8. Confirm: "Now watching **{projectName}** for **{customerName}**. The Account Watchdog will check it every 2 minutes and alert you on Telegram if anything changes."

### REMOVE — Stop watching a project

1. Read the current watchlist.
2. If empty, tell the user: "The watchlist is empty — nothing to remove."
3. Match the user's request against existing entries by customer name and/or project name. Be flexible with matching (case-insensitive, partial matches).
4. If multiple entries could match, list them and ask which to remove.
5. Remove the matching entry from the array.
6. Write the updated array back to the watchlist file.
7. Confirm: "Stopped watching **{projectName}** for **{customerName}**."

### LIST — Show the watchlist

1. Read the current watchlist.
2. If empty: "The watchlist is empty. Tell me to watch a project and the Account Watchdog will monitor it for you."
3. Otherwise, display a table:

| Customer | Project | Watching Since |
|----------|---------|---------------|
| {customerName} | {projectName} | {addedAt formatted} |
