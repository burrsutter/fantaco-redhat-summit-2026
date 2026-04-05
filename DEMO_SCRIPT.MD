# FantaCo OpenClaw Demo Script

## Scenario

This demo shows how OpenClaw can support a traditional enterprise user at FantaCo.

FantaCo is a company that sells office supplies, furniture, and themed workplace design/construction services. Sally Sellers is a newly hired sales representative. She uses OpenClaw as her **Second Brain** — a persistent, always-on AI partner that remembers what she learns, monitors her accounts autonomously, and grows smarter with every interaction. Sally works across customer CRM data, sales orders, invoices, product catalog data, sales policy knowledge, and internal HR information for employees.

Important framing:

- FantaCo is not an HR benefits company.
- FantaCo does provide internal HR benefits to its employees.
- The themed workplace offerings include:
  - Enchanted Forest
  - Interstellar Spaceship
  - 1920s Speakeasy
  - Serene Zen Garden

## Demo Setup

Assumptions before starting:

- OpenClaw is installed.
- Telegram pairing is complete.
- The relevant FantaCo MCP servers are connected.
- Memory is enabled.
- Scheduled tasks are enabled.
- Skill creation is enabled.
- Account Watchdog and Finance Monitor sub-agents are pre-configured in the OpenClaw gateway.
- Pre-built claw_skills (`customer-360`, `invoice-lookup`, `order-status`, `product-search`, `customer-lookup`) are loaded into the workspace. These are vendor/team-built skills that complement user-created skills.
- The workspace file browser is deployed (`/openclaw-workspace-viewer add`) so the presenter can show the Second Brain on disk.
- An urgent project note has been created (`/urgent-note-add`) so the Account Watchdog has something to detect during the demo.

## Demo Flow

### 1. Identity and memory

Sally says to OpenClaw:

```text
Your name is FantaBot
My name is Sally Sellers
```

Then:

```text
Create a memory: My Birthday is April 9 1987
```

Goal:

- Establish agent identity and user identity.
- Demonstrate personal memory creation.

### 2. Capability discovery

Sally says:

```text
What are your available skills?
```

Then:

```text
What are your available tools?
```

Goal:

- Show OpenClaw can explain its skill surface.
- Show OpenClaw can explain connected tools and integrations.

### 3. Internal employee knowledge

Sally says:

```text
How is the 401K handled here at FantaCo
```

Goal:

- Demonstrate internal HR policy retrieval.
- Reinforce that HR benefits are employee-facing, not customer-facing.

### 3a. Second Brain recall — birthday test

Sally says:

```text
When is my birthday?
```

Goal:

- Prove that memory persisted across topic changes (Steps 2-3 were unrelated to the birthday).
- The audience sees the Second Brain *working*, not just being populated.
- Quick, high-impact moment — OpenClaw should respond with "April 9, 1987."

### 4. Customer portfolio

Sally says:

```text
Who are my customers?
```

Goal:

- Use the customer MCP integration.
- Ideally resolve this through salesperson assignment for Sally Sellers.

### 5. Customer account research

Sally says:

```text
What are Tech Solutions recent orders?
```

Then:

```text
Any notes associated with Tech Solutions?
```

Then:

```text
Any projects for Tech Solutions?
```

Goal:

- Show multi-system exploration for one account.
- Combine customer CRM, sales order, and project data.

Presenter note:

- If needed, OpenClaw should first resolve `Tech Solutions` to the correct customer record, then continue with contacts, notes, orders, and projects.

### 5a. Finance research

Sally says:

```text
Does Tech Solutions have any outstanding invoices?
```

Goal:

- Exercise the Finance MCP integration.
- Natural follow-up during account research — orders lead to invoices.

### 5b. Product browsing

Sally says:

```text
What products do we have for the Enchanted Forest theme?
```

Goal:

- Exercise the Product MCP integration.
- Sets up the project creation step later in the demo.

### 6. Proactive monitoring and notification

Sally says:

```text
Create a scheduled task, every 1 minute, check Tech Solutions projects and alert me for urgent items via Telegram
```

Goal:

- Demonstrate task scheduling.
- Demonstrate monitoring of customer projects.
- Demonstrate proactive Telegram notification.

Presenter note:

- If `urgent` is ambiguous, OpenClaw should define the rule explicitly, for example:
  - urgent project notes
  - blocked or overdue milestones
  - project status changes that need rep attention

### 6a. Finance monitoring

Sally says:

```text
Also create a scheduled task, every 4 hours, check if any of my customers have overdue invoices and alert me via Telegram
```

Goal:

- Extend the monitoring pattern to Finance MCP.
- Show multiple scheduled tasks covering different concerns.

### 7. Policy retrieval

Sally says:

```text
What is our return sales policy?
```

Goal:

- Demonstrate sales policy retrieval using the sales-policy search MCP.

### 8. Skill creation

Sally says:

```text
I wish to learn how to create my own Skills. Create a Skill that simply asks for a name and then responds with Jambo, Bonjour, Aloha <name>
```

Then:

```text
Let's test the skill, Greet Marvin
```

Goal:

- Demonstrate user-authored skill creation.
- Demonstrate immediate use of a newly created skill.

### 9. Personal customer notes skill

Sally says:

```text
Create another skill that manages personal customer notes that uses the workspace memory
and when creating the notes identifies the customer.
If there is any confusion related to the customer name ask for clarity using the customer database
add the URL to our internal customer browser for that specific customer
```

Goal:

- Demonstrate custom workflow creation using memory plus MCP lookups.
- Show disambiguation against the customer system.
- Show note enrichment with an internal customer browser URL.

Presenter note:

- The internal customer browser URL pattern should be defined before the live demo if it is expected in the response.

### 10. Use the custom notes skill

Sally says:

```text
Who are the contacts for Tech Solutions?
```

Goal:

- Demonstrate access to contacts using the customer MCP


```text
Update my personal notes of Tech Solutions CEO David
his wife name is Bianca,
they have two children ages 4 and 8, Blake and Dion
He is a big fan of Van Halen
```

Goal:

- Demonstrate memory-backed customer relationship notes.
- Show customer-specific personal context capture for future account interactions.

### 10a. Second Brain — workspace viewer

**Presenter action** (not a Sally prompt — this is a visual reveal):

Open the workspace file browser in Chrome to show the audience what the Second Brain looks like on disk. Navigate to the workspace directory and show Sally's personal customer notes file, the memory files, and the skill definitions she created.

URL: `https://<openclaw-filebrowser-route>/`
Credentials: `admin / openclaw-demo`

Goal:

- "Peek behind the curtain" — the audience sees that the Second Brain is real files on real storage, not magic.
- Grounds the concept and makes it tangible.
- Show the notes about David's family, the birthday memory, and the greeting/personal-notes skill definitions.

### 11. Find a contact

Sally says:

```text
who is my primary contact at NovaSpark AI Labs?
```

Goal:

- Demonstrate contact lookup for another account.
- Show that OpenClaw can move between customers while preserving Sally's context.

### 11a. Pre-built skill — Customer 360

Sally says:

```text
/customer_360 NovaSpark AI Labs
```

Then:

```text
What skills are available for working with customers?
```

Goal:

- Showcase a pre-built, production-grade skill — not just the toy greeting skill from Step 8.
- The `/` slash-command invocation is visually striking and demonstrates the skill surface.
- The follow-up question reveals the full skill hierarchy: vendor-built skills (`customer-360`, `invoice-lookup`, `order-status`, `product-search`, `customer-lookup`) vs. user-created skills (greeting, personal notes).
- `customer-360` orchestrates Customer + Sales Order + Finance MCP servers in a single skill.

Presenter note:

- Explain that `customer-360` was built by the platform team and shared across the organization. Skills can be vendor-built, team-built, or user-created — and they all compose the same way.

### 12. Start a new project

Sally says:

```text
Start a new project for customer NovaSpark AI Labs
based on theme Enchanted Forest
```

Goal:

- Demonstrate project initiation for a customer.
- Show how OpenClaw bridges from customer lookup to project creation workflow.

Presenter note:

- OpenClaw uses the `create_project` tool on the Customer MCP to create the project directly.

### 12a. Sub-agent reveal — discover, review, act

**Beat 1 — Discovery:**

Sally says:

```text
Show me my active agents
```

**Beat 2 — Watchdog findings:**

Sally says:

```text
What has the Account Watchdog found recently?
```

**Beat 3 — Act on the finding:**

Sally says:

```text
That electrical inspection issue sounds urgent. Add a note to the Tech Solutions project flagging this for immediate follow-up and alert the site foreman via Telegram.
```

Goal:

- **Beat 1:** Demonstrate pre-configured sub-agents running autonomous background work.
- **Beat 2:** Show agent specialization and heartbeat-driven monitoring. The Account Watchdog should have detected the urgent project note (created by `/urgent-note-add`) during its 2-minute heartbeat.
- **Beat 3:** Close the loop — the sub-agent *found* something, and now Sally *acts* on it through FantaBot. This demonstrates the full cycle: autonomous detection → human review → assisted action.

Presenter note:

- The Account Watchdog should have detected the urgent project note during its 2-minute heartbeat. If it hasn't run yet, pause briefly or fill with conversation. Steps 1-11 should provide at least 6-8 minutes of demo time — enough for 3-4 heartbeat cycles.
- Without Beat 3, sub-agents are just a novelty. The action step is what makes them powerful.

### 13. Second Brain payoff — "What do you know about me?"

Sally says:

```text
What do you know about me and my accounts?
```

Goal:

- This is the Second Brain payoff. OpenClaw should recall: Sally's name, birthday, her customer portfolio, that Tech Solutions has an urgent electrical issue, that NovaSpark has a new Enchanted Forest project, the personal notes about David's family, and the active monitoring tasks.
- The audience sees everything accumulated into a coherent knowledge base — the Second Brain in action.
- Closing moment: OpenClaw isn't just answering questions — it *knows* Sally.

## Suggested Narrative Arc

This script tells a clean enterprise story with three hero features woven throughout — **Second Brain**, **Skills**, and **Sub-Agents**:

1. Sally establishes her identity and begins building her **Second Brain** (memory).
2. Sally learns what OpenClaw can do — **tools and skills**.
3. Sally taps internal employee knowledge (HR policy retrieval).
4. Sally proves her **Second Brain** remembers (birthday recall).
5. Sally explores her customer portfolio.
6. Sally researches a customer across multiple systems.
7. Sally checks invoices and browses the product catalog.
8. Sally sets up **proactive monitoring** — scheduled tasks for projects and finance.
9. Sally retrieves policy guidance.
10. Sally creates her own **custom skills** (greeting, personal notes).
11. Sally uses **memory + MCP** together for relationship management.
12. Sally peeks inside her **Second Brain** (workspace viewer).
13. Sally uses a **pre-built skill** (`/customer_360`) for a cross-system briefing.
14. Sally moves from research into action — creates a new customer project.
15. Sally discovers her **sub-agents** have been working autonomously in the background.
16. Sally **acts on a sub-agent finding** — closing the autonomous monitoring loop.
17. Sally asks OpenClaw to summarize everything it knows — the **Second Brain payoff**.

## Demo Risks and Gaps

- `Who are my customers?` depends on customer records having salesperson assignment data for Sally Sellers.
- `Tech Solutions recent orders` depends on sales-order data for that customer existing in the environment.
- Scheduled task and Telegram alerting depend on those features being enabled in the OpenClaw runtime.
- Skill creation depends on the environment allowing local skill authoring.
- Personal customer note URLs depend on a defined internal customer browser URL format.
- Sub-agent heartbeats are set to 2-minute intervals. The presenter should work through Steps 1-11 before reaching Step 12a, giving sub-agents time to run at least once.

## Optional Follow-Up Enhancements

- Add a customer browser URL convention to the personal notes skill.
- Add a richer `urgent items` rule for scheduled monitoring.
- Exercise HR Recruiting MCP if a recruiting storyline fits the demo narrative.
