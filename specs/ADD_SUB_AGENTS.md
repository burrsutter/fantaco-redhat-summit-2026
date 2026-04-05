# Spec: Add Sub-Agents, create_project Tool, and Demo Script Updates

## Decisions Made

1. **Telegram routing:** All sub-agents share the **same Telegram bot token** configured at the gateway level in `channels.telegram`. Heartbeat alerts from Account Watchdog and Finance Monitor arrive in the **same DM** as Sally's interactive chat with FantaBot. No second bot needed.

2. **Heartbeat interval:** Set to **2 minutes** (`"every": "2m"`) for both sub-agents so alerts appear quickly during live demos. Production would use longer intervals (15m, 4h).

3. **Gap analysis:** The demo script only exercises 4 of 7 MCP servers. Finance, Product, and HR Recruiting are never used. Adding sub-agents and new demo steps fills the Finance and Product gaps naturally.

4. **Project creation:** The backend `POST /api/customers/{customerId}/projects` endpoint exists but the Customer MCP server has no `create_project` tool. Adding it removes the "Risk" listed in the demo script.

---

## Change 1: Add `create_project` tool to Customer MCP

**File:** `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py`

Add a new `@mcp.tool()` function following the same pattern as `update_project_status`. Calls `POST /api/customers/{customer_id}/projects` on the backend.

Parameters:
- `customer_id` (str, required)
- `project_name` (str, required)
- `description` (str, required)
- `pod_theme` (str, required) — one of: ENCHANTED_FOREST, INTERSTELLAR_SPACESHIP, SPEAKEASY_1920S, ZEN_GARDEN, CUSTOM
- `status` (str, optional, default "PROPOSAL")
- `site_address` (str, optional)
- `estimated_start_date` (str, optional)
- `estimated_end_date` (str, optional)
- `estimated_budget` (float, optional)

The backend accepts this JSON body:
```json
{
  "projectName": "string",
  "description": "string",
  "podTheme": "ENCHANTED_FOREST",
  "status": "PROPOSAL",
  "siteAddress": "string (optional)",
  "estimatedStartDate": "date (optional)",
  "estimatedEndDate": "date (optional)",
  "estimatedBudget": "number (optional)"
}
```

---

## Change 2: Add sub-agents to `setup-openclaw.sh`

**File:** `scripts/setup-openclaw.sh`

In the Python block that builds `new_config['agents']` (lines 211-220), expand `agents.list` from one entry to three. Also rename the default agent from `'OpenClaw Assistant'` to `'FantaBot'`.

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

Key points:
- Each sub-agent gets its own workspace directory to maintain independent state
- `isolatedSession: True` — each heartbeat runs in its own session, not polluting Sally's conversation
- `lightContext: True` — keeps heartbeat context small for faster execution
- `target: 'telegram'` — references the shared `channels.telegram` config (same bot token)

---

## Change 3: Update DEMO_SCRIPT.MD

**File:** `DEMO_SCRIPT.MD`

### New steps to insert:

**Step 5a** (after Step 5 — account research):
```text
Does Tech Solutions have any outstanding invoices?
```
- Exercises Finance MCP (currently unused in demo)
- Natural follow-up during account research

**Step 5b:**
```text
What products do we have for the Enchanted Forest theme?
```
- Exercises Product MCP (currently unused in demo)
- Sets up the project creation in Step 12

**Step 6a** (after Step 6 — scheduled task):
```text
Also create a scheduled task, every 4 hours, check if any of my customers have overdue invoices and alert me via Telegram
```
- Extends the monitoring pattern to Finance MCP
- Shows multiple scheduled tasks covering different concerns

**Step 11a** (after Step 11 — find contact):
```text
Give me a full account briefing for NovaSpark AI Labs — contacts, recent orders, invoices, and any projects
```
- Forces multi-server orchestration across Customer + Sales Order + Finance MCP servers
- Demonstrates cross-system intelligence in a single answer

**Step 12a** (after Step 12 — new project):
```text
Show me my active agents
```
Then:
```text
What has the Account Watchdog found recently?
```
- Demonstrates pre-configured sub-agents with autonomous background work
- Shows agent specialization and heartbeat-driven monitoring

### Updates to existing content:

- **Step 12 presenter note:** Remove the risk caveat — project creation now works via `create_project` tool
- **Demo Setup section:** Add "Account Watchdog and Finance Monitor agents are pre-configured in the OpenClaw gateway"
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

1. **create_project tool:** Read the customer MCP code to confirm the new tool follows existing patterns (`update_project_status` is the model). Verify the POST endpoint path matches the backend routes.
2. **setup-openclaw.sh:** Run `bash -n scripts/setup-openclaw.sh` to syntax-check. Review the Python block to confirm it outputs valid JSON with all 3 agents in `agents.list`.
3. **Demo script:** Read through the updated flow for narrative coherence — Finance/Product steps should feel natural in Sally's account research arc, and the sub-agent step should be a satisfying reveal near the end.
