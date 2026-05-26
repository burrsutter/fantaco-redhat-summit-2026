# OpenClaw Manual Test Prompts

Password: see `.env` for `STUDENT_OPENCLAW_PASSWORD`

## Basic Test (7 prompts)

Send these in order in a single chat session.

1. `Hello`
2. `My name is Sally Sellers and your name is FantaBot`
3. `I'm a new sales rep at FantaCo`
4. `What's the best way to learn about our product catalog?`
5. `Create a skill called friendly-greeter. When invoked, it should greet the user with exactly: Aloha <name>, Welcome to FantaCo — replacing <name> with the name from the message. If no name is given, ask for one. No extra commentary.`
6. `Use the friendly-greeter skill to greet George`
7. `Now greet me`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Hello | Agent responds with a greeting |
| 2 | My name is Sally Sellers | Agent acknowledges the name |
| 3 | I'm a new sales rep at FantaCo | Agent acknowledges the sales rep role |
| 4 | What's the best way to learn about our product catalog? | Agent suggests ways to explore the product catalog (could mention tools, docs, asking colleagues, etc.) |
| 5 | Create a skill... | Agent confirms the skill was created |
| 6 | Use the friendly-greeter... | Response contains "Aloha George, Welcome to Red Hat" |
| 7 | Now greet me | Response contains "Aloha Sally Sellers, Welcome to Red Hat" |

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
