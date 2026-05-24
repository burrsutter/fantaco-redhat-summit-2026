# OpenClaw Manual Test Prompts

Password: see `.env` for `STUDENT_OPENCLAW_PASSWORD`

## Basic Test (8 prompts)

Send these in order in a single chat session.

1. `Hello`
2. `My name is Takeshi and your name is Nokori`
3. `I work as a Java developer building microservices at FantaCo`
4. `What framework would you recommend for my next project?`
5. `Create a skill called friendly-greeter. When invoked, it should greet the user with exactly: Aloha <name>, Welcome to Red Hat — replacing <name> with the name from the message. If no name is given, ask for one. No extra commentary.`
6. `Use the friendly-greeter skill to greet George`
7. `Now greet me`
8. `what is your name?`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Hello | Agent responds with a greeting |
| 2 | My name is Takeshi... | Agent acknowledges both names, does NOT ask about creature/vibe/emoji |
| 3 | I work as a Java developer... | Agent acknowledges the context |
| 4 | What framework... | Agent recommends Java frameworks (Quarkus, Spring Boot, etc.) |
| 5 | Create a skill... | Agent confirms the skill was created |
| 6 | Use the friendly-greeter... | Response contains "Aloha George, Welcome to Red Hat" |
| 7 | Now greet me | Response contains "Aloha Takeshi, Welcome to Red Hat" |
| 8 | what is your name? | Response contains "Nokori" |

## MCP Customer Test (5 prompts)

Start a **new session** before running these.

1. `Search for customers with "coffee" in their name`
2. `Look up customer CUST001 and show me their details`
3. `I need to find a customer — I think their name has "Tech" in it`
4. `do they have any ongoing projects`
5. `Compare customers CUST001 and CUST003 — show me a side-by-side of their details`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | Search for customers... | MCP tool call visible, coffee-related customers returned |
| 2 | Look up customer CUST001... | MCP tool call visible, full customer details shown |
| 3 | ...name has "Tech"... | MCP tool call visible, finds Tech-related customer(s) |
| 4 | do they have any ongoing projects | Recalls the Tech customer from prompt 3, looks up their projects |
| 5 | Compare customers CUST001 and CUST003... | Multiple MCP tool calls, side-by-side comparison |

## Quote Builder Test (3 prompts)

Continue in the **same session** as the MCP Customer Test (or start a new one).

1. `/quote_builder NovaSpark AI Labs, Enchanted Forest`
2. `Change the quantities to 3 for all decoration items`
3. `approve`

### What to look for

| # | Prompt | Expected |
|---|--------|----------|
| 1 | /quote_builder NovaSpark... | Multiple MCP tool calls (search customers, search products, get orders). Displays a draft quote with customer info, product table with prices, and order history |
| 2 | Change the quantities... | Updated quote with adjusted quantities and recalculated totals |
| 3 | approve | Creates a new project via MCP, confirms with a project ID |
