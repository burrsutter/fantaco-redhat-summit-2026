# OpenClaw Manual Test Prompts

Password: see `.env` for `STUDENT_OPENCLAW_PASSWORD`

## Basic Test (8 prompts)

Send these in order in a single chat session.

1. `Hello`
2. `My name is Sally Sellers`
3. `your name is FantaBot`
4. `I'm a new sales rep at FantaCo`
5. `What's the best way to learn about our product catalog?`
6. `Create a skill called friendly-greeter. When invoked, it should greet the user with exactly: Aloha <name>, Welcome to FantaCo — replacing <name> with the name from the message. If no name is given, ask for one. No extra commentary.`
7. `Use the friendly-greeter skill to greet George`
8. `Now greet me`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Hello | Agent responds with a greeting |
| 2 | My name is Sally Sellers | Agent acknowledges the name |
| 3 | your name is FantaBot | Agent acknowledges the bot name (FantaBot) |
| 4 | I'm a new sales rep at FantaCo | Agent acknowledges the sales rep role |
| 5 | What's the best way to learn about our product catalog? | Agent suggests ways to explore the product catalog (could mention tools, docs, asking colleagues, etc.) |
| 6 | Create a skill... | Agent confirms the skill was created |
| 7 | Use the friendly-greeter... | Response contains "Aloha George, Welcome to Red Hat" |
| 8 | Now greet me | Response contains "Aloha Sally Sellers, Welcome to Red Hat" |

## MCP Tests (12 prompts)

Start a **new session** before running these.

1. `Who are my customers`
2. `Look up customer CUST003 and show me their details`
3. `do they have any ongoing projects`
4. `Compare customers CUST001 and CUST003 — show me a side-by-side of their details`
5. `what are the products in the Enchanted Forest theme`
6. `create a new workspace skill that manages personal customer notes that uses the workspace memory and when creating the notes identifies the customer record, if there is any confusion ask me for clarity. use the customer database and mcp.`
7. `who are the contacts for Tech Solutions`
8. `update my personal notes for Tech Solutions CEO David`
9. `his wife's name is Bianca`
10. `they have two children: 4 and 8, Blake and Dion`
11. `and he is a huge fan of Def Leppard`
12. `Remember whenever I ask about a customer, always include their current project summary too.`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Who are my customers | MCP tool call visible, returns: Brew & Bean Coffee Shop, Green Thumb Garden Center, Tech Solutions IT, NovaSpark AI Labs |
| 2 | Look up customer CUST001... | MCP tool call visible, full customer details shown |
| 3 | do they have any ongoing projects | Recalls CUST003 from prompt 2, looks up their projects |
| 4 | Compare customers CUST001 and CUST003... | Multiple MCP tool calls, side-by-side comparison |
| 5 | what are the products in the Enchanted Forest theme | MCP tool call visible, returns Enchanted Forest themed products |
| 6 | create a new workspace skill... | Agent creates a skill that uses workspace memory and the customer MCP to store/retrieve personal notes tied to customer records. May ask clarifying questions about format or scope. |
| 7 | who are the contacts for Tech Solutions | Uses MCP to look up Tech Solutions contacts |
| 8 | update my personal notes for Tech Solutions CEO David | Invokes the newly created skill to start/update personal notes for David |
| 9 | his wife's name is Bianca | Adds wife's name to David's personal notes |
| 10 | they have two children: 4 and 8, Blake and Dion | Adds children info to David's personal notes |
| 11 | and he is a huge fan of Def Leppard | Adds Def Leppard interest to David's personal notes |
| 12 | Remember whenever I ask about a customer... | Agent updates **USER.md** (not MEMORY.md) with the preference. Verify in Agents → Core Files → USER (Cmd+Shift+R if stale). USER.md stores facts about the human — preferences, habits, how they like to work. Future customer lookups should now auto-include project summaries. |

## Quote Builder Test (3 prompts)

Continue in the **same session** as the MCP Customer Test (or start a new one).

1. `/quote_builder Start a new project NovaSpark AI Labs, Enchanted Forest`
2. `Change the quantities to 3 for all decoration items`
3. `approve`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | /quote_builder NovaSpark... | Multiple MCP tool calls (search customers, search products, get orders). Displays a draft quote with customer info, product table with prices, and order history |
| 2 | Change the quantities... | Updated quote with adjusted quantities and recalculated totals |
| 3 | approve | Creates a new project via MCP, confirms with a project ID |

## Heartbeat Monitoring Test (2 prompts)

Continue in the **same session** or start a new one.

1. `Add a check to HEARTBEAT.md: alert me if Tech Solutions has any urgent notes.`
2. `What are you monitoring for me?`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Add a check to HEARTBEAT.md... | Agent uses the `write` tool to update HEARTBEAT.md with a check for urgent notes on Tech Solutions. May look up the customer ID (CUST003) first via MCP. Confirm via Agents → Core Files → HEARTBEAT (hit Refresh or Cmd+Shift+R if stale). |
| 2 | What are you monitoring for me? | Agent reads HEARTBEAT.md and summarizes the active checks — should mention Tech Solutions urgent notes. Good way to verify the file was actually written. |

### How heartbeat works

- The agent reads HEARTBEAT.md every ~30 minutes automatically
- If it finds actionable checks, it runs them and posts results in chat
- If nothing needs attention, it silently returns `HEARTBEAT_OK` (user sees nothing)
- Empty file = no API calls, no cost
- The GUI may show stale content — use Cmd+Shift+R to hard refresh

### Demo story arc

1. Show the empty HEARTBEAT.md in Agents → Core Files → HEARTBEAT
2. Send prompt 1 — agent updates the file
3. Send prompt 2 — agent confirms what it's watching
4. (Optional) Add an urgent note to Tech Solutions via the customer web UI
5. Wait for the next heartbeat cycle (~30 min) or mention it fires automatically
6. Key point: the agent went from reactive to proactive with a single prompt

## Scheduled Task Test (1 prompt)

Continue in the **same session** or start a new one.

1. `Create a cronjob, that runs every 1 minute, that will check on Tech Solutions projects and let me know if any urgent notes show up`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Create a scheduled task... | Agent creates a cron/scheduled task that runs every minute. It should use the customer MCP tools to look up Tech Solutions (CUST003) projects and check for urgent notes. Confirm the task is registered and running. |

## Proxy Allowlist Demo (1 prompt + admin steps)

This demonstrates the proxy security model: agents can only reach approved domains.

1. `Show me the NASA APOD`
2. `Get me the top headline from BBC News`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Show me the NASA APOD | Agent tries to fetch `apod.nasa.gov` but **fails** — the proxy blocks it. Agent reports it cannot access the site. |
| 2 | Get me the top headline from BBC News | Agent tries to fetch `www.bbc.com` but **fails** — same proxy block. Good alternative if you want a text-only example (no images). |

### Demo flow (presenter steps)

1. **Send the prompt** — agent fails with a network/fetch error
2. **Show the blocked request in Loki** — run from the `clawoperator-openclaw/` directory:
   ```bash
   ./review-blocked-requests.sh 5m
   ```
   Output shows `apod.nasa.gov` blocked, which namespace hit it, and when.
3. **Approve the domain** — add it to the proxy allowlist:
   ```bash
   ./manage-proxy-allowlist.sh allow apod.nasa.gov
   ```
   This patches the Claw CR, the operator regenerates the proxy config, and the proxy pod restarts (~10 seconds).
4. **Re-send the prompt** — `Show me the NASA APOD` now succeeds, agent fetches and displays the image.
5. **Key point:** The agent operates within a zero-trust network boundary. The admin controls which external domains are reachable — no blanket internet access.

### Multi-domain example: XKCD

XKCD images are hosted on a separate subdomain, so you need to allow both:

```bash
./manage-proxy-allowlist.sh allow xkcd.com,imgs.xkcd.com
```

Prompt: `Show me today's XKCD comic`

The script supports comma-separated domains for allow and revoke.

### Other fun prompts that trigger proxy blocks

| Prompt | Blocked domain(s) |
|--------|-------------------|
| `Show me the NASA APOD` | `apod.nasa.gov` |
| `Get me the top headline from BBC News` | `www.bbc.com` (verified working) |
| `Show me today's XKCD comic` | `xkcd.com`, `imgs.xkcd.com` |
| `What's the current Bitcoin price?` | `api.coindesk.com` or similar |
| `Get me the top headline from BBC News` | `bbc.com` |
| `What's trending on Hacker News?` | `news.ycombinator.com` |
| `Look up the Wikipedia page for Red Hat` | `en.wikipedia.org` |

### Useful admin commands

```bash
# Check what's being blocked (last 5 minutes, all namespaces)
./review-blocked-requests.sh 5m

# Check what's being blocked for a specific user
./review-blocked-requests.sh 5m user2

# List currently allowed domains
./manage-proxy-allowlist.sh list 2

# Allow one or more domains (comma-separated)
./manage-proxy-allowlist.sh allow apod.nasa.gov
./manage-proxy-allowlist.sh allow xkcd.com,imgs.xkcd.com 2

# Revoke access
./manage-proxy-allowlist.sh revoke apod.nasa.gov
./manage-proxy-allowlist.sh revoke xkcd.com,imgs.xkcd.com 2
```

### Optional: revoke access afterward

```bash
./manage-proxy-allowlist.sh revoke apod.nasa.gov
```
