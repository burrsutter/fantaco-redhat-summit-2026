# Token Usage Analysis — Performance Tuning Reference

**Cluster:** ql7rg (agentic-user1)
**Date:** 2026-06-02
**Observed avg prompt tokens/call:** ~24,800
**Token estimation:** ~4 chars per token (rough heuristic)

---

## 1. Platform Skill (Operator-Managed)

| File | Bytes | Est. Tokens | Source |
|---|---|---|---|
| `skills/platform/SKILL.md` | 22,474 | **~5,620** | claw-operator (`~/ai-projects/claw-operator`) |

**Local copy:** `/tmp/platform-skill.md`
**In-pod path:** `/home/node/.openclaw/workspace/skills/platform/SKILL.md`

This file is **65% of all workspace content**. It's injected by the claw-operator and documents proxy rules, credential handling, MCP config, channels, web search, and Kubernetes constraints. Trimming requires changes upstream in the operator repo.

---

## 2. MCP Tool Schemas

Tool schemas are sent to the LLM as function definitions on every call. Each tool includes its name, description, and full JSON Schema for parameters.

### Customer MCP (15 tools, ~2,845 tokens)

| Tool | Params | Schema | Description |
|---|---|---|---|
| `search_customers` | 4 | 1,073 chars | Search by company/contact fields |
| `search_customers_by_salesperson` | 1 | 611 chars | Find customers by sales rep |
| `get_customer` | 1 | 572 chars | Base customer record by ID |
| `get_customer_detail` | 1 | 666 chars | Full CRM view for a customer |
| `get_customer_notes` | 1 | 400 chars | CRM notes for a customer |
| `get_customer_contacts` | 1 | 393 chars | All contacts for a customer |
| `get_customer_salespersons` | 1 | 401 chars | Sales reps assigned to customer |
| `get_customer_projects` | 3 | 713 chars | Projects with optional filtering |
| `get_project_detail` | 2 | 487 chars | Full detail for a single project |
| `search_projects_by_status` | 1 | 447 chars | Projects by status across portfolio |
| `search_projects_by_theme` | 1 | 461 chars | Projects by theme across portfolio |
| `add_project_note` | 5 | 664 chars | Add a project note |
| `create_project` | 9 | 1,242 chars | Create new Imagination Pod project |
| `update_project_status` | 13 | 2,015 chars | Update project status + fields |
| `update_milestone_status` | 9 | 1,238 chars | Update a project milestone |
| **Total** | | **11,383 chars** | **~2,845 tokens** |

**Source:** `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py` (25,839 bytes)

**Candidates for removal (demo):** `update_project_status`, `update_milestone_status`, `add_project_note` — these are write-heavy admin tools rarely used in demos. Removing them saves ~980 tokens.

### Product MCP (6 tools, ~1,070 tokens)

| Tool | Params | Schema | Description |
|---|---|---|---|
| `search_products` | 4 | 958 chars | Search by name/category/manufacturer/theme |
| `list_pod_themes` | 0 | 174 chars | List valid pod theme tokens |
| `get_product` | 1 | 394 chars | Get product by SKU |
| `create_product` | 13 | 1,321 chars | Create new catalog entry |
| `update_product` | 13 | 1,201 chars | Update catalog entry |
| `delete_product` | 1 | 239 chars | Delete product by SKU |
| **Total** | | **4,287 chars** | **~1,070 tokens** |

**Source:** `fantaco-mcp-servers/product-mcp/product-api-mcp-server.py` (10,844 bytes)

**Candidates for removal (demo):** `create_product`, `update_product`, `delete_product` — catalog management tools, not used in sales demos. Removing them saves ~690 tokens.

### Sales Order MCP (2 tools, ~290 tokens)

| Tool | Params | Schema | Description |
|---|---|---|---|
| `search_sales_orders` | 3 | 724 chars | Search by customer/status |
| `get_sales_order` | 1 | 423 chars | Full order by order number |
| **Total** | | **1,147 chars** | **~290 tokens** |

**Source:** `fantaco-mcp-servers/sales-order-mcp/sales-order-api-mcp-server.py` (5,846 bytes)

No trimming needed — only 2 read-only tools.

### MCP Total

| Server | Tools | Est. Tokens |
|---|---|---|
| Customer | 15 | ~2,845 |
| Product | 6 | ~1,070 |
| Sales Order | 2 | ~290 |
| **Total** | **23** | **~4,205** |

**With demo trimming** (remove 5 admin/write tools): **~2,535 tokens** (saves ~1,670)

---

## 3. Workspace Files (Injected by Scripts)

Files injected by `audience-reset.sh` and the operator into each pod's workspace at `/home/node/.openclaw/workspace/`.

### Operator-injected (upstream)

| File | Bytes | Est. Tokens | Source |
|---|---|---|---|
| `skills/platform/SKILL.md` | 22,474 | ~5,620 | claw-operator |
| `AGENTS.md` (base) | ~1,870 | ~468 | claw-operator |
| `HEARTBEAT.md` | 226 | ~57 | gateway auto-generated |
| **Subtotal** | **~24,570** | **~6,145** | |

### audience-reset.sh injected

| File | Bytes | Est. Tokens | Template Source |
|---|---|---|---|
| `AGENTS.md` (appended section) | 1,198 | ~300 | `workspace-templates/AGENTS.md.append` |
| `SOUL.md` | 1,240 | ~310 | `workspace-templates/SOUL.md` |
| `IDENTITY.md` | 164 | ~41 | `workspace-templates/IDENTITY.md` |
| `TOOLS.md` | 873 | ~218 | `workspace-templates/TOOLS.md` |
| `skills/quote-builder/SKILL.md` | 4,614 | ~1,154 | `claw_skills/quote-builder/SKILL.md` |
| **Subtotal** | **~8,089** | **~2,023** | |

### User-created (during demo interaction)

| File | Bytes | Est. Tokens | Created by |
|---|---|---|---|
| `USER.md` | 557 | ~139 | Gateway (user profile, updated by agent) |
| `skills/friendly-greeter/SKILL.md` | 301 | ~75 | User asked agent to create a skill |
| `skills/personal-notes/SKILL.md` | 1,059 | ~265 | User asked agent to create a skill |
| `skills/personal-notes/notes/CUST003.md` | 223 | ~56 | Agent wrote a customer note |
| **Subtotal** | **~2,140** | **~535** | |

### Workspace Total

| Category | Est. Tokens |
|---|---|
| Operator-injected | ~6,145 |
| audience-reset.sh injected | ~2,023 |
| User-created | ~535 |
| **Total workspace** | **~8,703** |

---

## 4. Other Prompt Components (Estimated)

| Component | Est. Tokens | Notes |
|---|---|---|
| OpenClaw base system prompt | ~2,000–3,000 | Built into gateway runtime, not configurable |
| Conversation history | grows per turn | ~200–500 tokens per turn (both sides) |
| MCP tool schemas | ~4,205 | See section 2 |
| Workspace files | ~8,703 | See section 3 |

---

## 5. Full Prompt Budget (Estimated)

| Component | Tokens | % of Baseline |
|---|---|---|
| OpenClaw base system prompt | ~2,500 | 15% |
| **platform/SKILL.md** | **~5,620** | **33%** |
| Other workspace files | ~3,083 | 18% |
| **MCP tool schemas (23 tools)** | **~4,205** | **25%** |
| Conversation history (turn 1) | ~200 | 1% |
| **Baseline (first message)** | **~15,600** | |
| Conversation history (turn 10) | ~3,000 | |
| **After 10 turns** | **~18,600** | |
| **Observed avg (40 calls)** | **~24,800** | |

---

## 6. Tuning Opportunities (Ranked by Impact)

| Opportunity | Savings | Effort | Risk |
|---|---|---|---|
| **Trim platform/SKILL.md** | ~2,000–3,000 tokens | Medium (upstream) | Medium — could break agent answers about proxy/operator |
| **Remove 5 admin MCP tools** | ~1,670 tokens | Low (MCP server change) | Low — demo doesn't use these tools |
| **Trim quote-builder SKILL.md** | ~400–500 tokens | Low | Low — verbose instructions could be shortened |
| **Remove TOOLS.md** | ~218 tokens | Trivial | None — content duplicates MCP schema |
| **Remove HEARTBEAT.md** | ~57 tokens | Trivial | None — heartbeat is disabled |
| **Shorten AGENTS.md append** | ~100–150 tokens | Low | Low — could condense MCP tool list |
| **Use a faster model** | 0 tokens (latency fix) | Config change | Medium — model quality may differ |

**Maximum potential savings:** ~4,500–5,600 tokens (~28–36% reduction)
**Quick wins (no upstream changes):** ~2,445 tokens (~16% reduction)

---

## 7. Latency Impact

From Prometheus (agentic-user1, 40 model calls over 2 hours):

| Metric | Value |
|---|---|
| Model call latency p50 | 8.7s |
| Model call latency p95 | 50.5s |
| End-to-end run p95 | 57.4s |
| Avg prompt tokens/call | ~24,800 |
| Avg output tokens/call | ~179 |
| Cache hit rate | ~69% (17,131 cached of 24,806 prompt) |

The latency is dominated by **prompt processing**, not generation (output is tiny at 179 tokens). Reducing prompt tokens directly reduces the time the LLM spends processing context on cache misses.

---

## 8. Files Referenced

| File | Location |
|---|---|
| Platform skill (in-pod) | `/home/node/.openclaw/workspace/skills/platform/SKILL.md` |
| Platform skill (local copy) | `/tmp/platform-skill.md` |
| Platform skill (source) | `~/ai-projects/claw-operator` (upstream) |
| AGENTS.md append template | `clawoperator-openclaw/workspace-templates/AGENTS.md.append` |
| SOUL.md template | `clawoperator-openclaw/workspace-templates/SOUL.md` |
| IDENTITY.md template | `clawoperator-openclaw/workspace-templates/IDENTITY.md` |
| TOOLS.md template | `clawoperator-openclaw/workspace-templates/TOOLS.md` |
| Quote-builder skill | `claw_skills/quote-builder/SKILL.md` |
| Customer MCP server | `fantaco-mcp-servers/customer-mcp/customer-api-mcp-server.py` |
| Product MCP server | `fantaco-mcp-servers/product-mcp/product-api-mcp-server.py` |
| Sales Order MCP server | `fantaco-mcp-servers/sales-order-mcp/sales-order-api-mcp-server.py` |
| Grafana dashboard | `dashboards/openclaw-admin-overview.json` |
| Enable Prometheus | `clawoperator-openclaw/enable-prometheus.sh` |
| Extract Langfuse traces | `clawoperator-openclaw/extract-langfuse-traces.sh` |
