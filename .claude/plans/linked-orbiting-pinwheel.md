# Plan: Add Sub-Agents, create_project Tool, and Update Demo Script

## Context

The demo script exercises only 4 of 7 MCP servers (Finance, Product, HR Recruiting are absent), project creation is listed as a risk, and there's no demonstration of OpenClaw's multi-agent capabilities. This plan adds two heartbeat sub-agents (Account Watchdog, Finance Monitor), a `create_project` MCP tool, and new demo steps to fill the gaps. All heartbeats set to **2 minutes** for live demo pacing. All agents share the **same Telegram bot** — alerts arrive in the same DM as interactive chat.

---

## Change 1: Add `create_project` tool to Customer MCP

**File:** `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py`

Add a new `@mcp.tool()` function following the same pattern as existing tools like `update_project_status`. Calls `POST /api/customers/{customer_id}/projects`.

Parameters:
- `customer_id` (str, required)
- `project_name` (str, required)
- `description` (str, required)
- `pod_theme` (str, required) — ENCHANTED_FOREST, INTERSTELLAR_SPACESHIP, SPEAKEASY_1920S, ZEN_GARDEN, CUSTOM
- `status` (str, optional, default "PROPOSAL")
- `site_address`, `estimated_start_date`, `estimated_end_date` (str, optional)
- `estimated_budget` (float, optional)

## Change 2: Add sub-agents to `setup-openclaw.sh`

**File:** `scripts/setup-openclaw.sh`

In the Python block that builds `new_config['agents']` (lines 211-220), expand `agents.list` from one entry to three:

```python
'list': [
    {'id': 'default', 'name': 'FantaBot', 'default': True, 'workspace': '~/.openclaw/workspace/fantabot'},
    {
        'id': 'account-watchdog',
        'name': 'Account Watchdog',
        'workspace': '~/.openclaw/workspace/watchdog',
        'heartbeat': {
            'every': '2m',
            'target': 'telegram',
            'isolatedSession': True,
            'lightContext': True
        }
    },
    {
        'id': 'finance-monitor',
        'name': 'Finance Monitor',
        'workspace': '~/.openclaw/workspace/finance',
        'heartbeat': {
            'every': '2m',
            'target': 'telegram',
            'isolatedSession': True,
            'lightContext': True
        }
    }
]
```

Also rename the default agent from `'OpenClaw Assistant'` to `'FantaBot'` to match the demo persona.

## Change 3: Update DEMO_SCRIPT.MD

**File:** `DEMO_SCRIPT.MD`

### New steps to add:

**Step 5a** (after Step 5 — account research):
```text
Does Tech Solutions have any outstanding invoices?
```
Exercises Finance MCP. Natural for a sales rep researching an account.

**Step 5b:**
```text
What products do we have for the Enchanted Forest theme?
```
Exercises Product MCP. Sets up the project creation in Step 12.

**Step 6a** (after Step 6 — scheduled task):
```text
Also create a scheduled task, every 4 hours, check if any of my customers have overdue invoices and alert me via Telegram
```
Extends the monitoring pattern to Finance MCP.

**Step 11a** (after Step 11 — find contact):
```text
Give me a full account briefing for NovaSpark AI Labs — contacts, recent orders, invoices, and any projects
```
Forces multi-server orchestration (Customer + Sales Order + Finance).

**Step 12a** (after Step 12 — new project):
```text
Show me my active agents
```
Then:
```text
What has the Account Watchdog found recently?
```
Demonstrates pre-configured sub-agents with autonomous background work.

### Updates to existing content:

- **Step 12 presenter note:** Remove the risk caveat about project creation — it now works via `create_project` tool
- **Demo Setup section:** Add "Account Watchdog and Finance Monitor agents are pre-configured"
- **Demo Risks and Gaps:** Remove project creation risk; remove mention of missing Finance/Product coverage
- **Narrative Arc:** Add entries for finance research, product browsing, multi-server orchestration, and sub-agents

---

## Files Modified

| File | Change |
|------|--------|
| `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py` | Add `create_project` tool |
| `scripts/setup-openclaw.sh` | Add Account Watchdog + Finance Monitor to `agents.list`, rename default to FantaBot |
| `DEMO_SCRIPT.MD` | Add steps 5a, 5b, 6a, 11a, 12a; update step 12, setup, risks |

## Verification

1. **create_project tool:** Read the customer MCP server code to confirm the new tool follows existing patterns and the POST endpoint path is correct
2. **setup-openclaw.sh:** Run `bash -n scripts/setup-openclaw.sh` to syntax-check, then review the Python block outputs valid JSON with all 3 agents
3. **Demo script:** Read through the updated flow for narrative coherence — each new step should feel natural in Sally's story
