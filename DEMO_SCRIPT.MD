# FantaCo OpenClaw Demo Script

## Scenario

This demo shows how OpenClaw can support a traditional enterprise user at FantaCo.

FantaCo is a company that sells office supplies, furniture, and themed workplace design/construction services. Sally Sellers is a newly hired sales representative. She uses OpenClaw to work across customer CRM data, sales orders, invoices, product catalog data, sales policy knowledge, and internal HR information for employees.

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
Who are the contacts?
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
Update my personal notes of Tech Solutions CEO David
his wife name is Bianca,
they have two children ages 4 and 8, Blake and Dion
He is a big fan of Van Halen
```

Goal:

- Demonstrate memory-backed customer relationship notes.
- Show customer-specific personal context capture for future account interactions.

### 11. Find a contact

Sally says:

```text
who is my primary contact at NovaSpark AI Labs?
```

Goal:

- Demonstrate contact lookup for another account.
- Show that OpenClaw can move between customers while preserving Sally's context.

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

- The current customer MCP server supports project lookup and project updates. If project creation is not yet implemented in the connected backend/tooling, this step should be framed as either:
  - creating a draft/project request through another tool, or
  - a future enhancement item for the demo.

## Suggested Narrative Arc

This script tells a clean enterprise story:

1. Sally establishes identity and memory.
2. Sally learns what OpenClaw can do.
3. Sally uses internal employee knowledge.
4. Sally explores her customer portfolio.
5. Sally researches a customer across multiple systems.
6. Sally sets up proactive monitoring and Telegram alerts.
7. Sally retrieves policy guidance.
8. Sally creates her own custom skills.
9. Sally uses memory and customer data together for relationship management.
10. Sally moves from research into action with a new customer project.

## Demo Risks and Gaps

- `Who are my customers?` depends on customer records having salesperson assignment data for Sally Sellers.
- `Tech Solutions recent orders` depends on sales-order data for that customer existing in the environment.
- Scheduled task and Telegram alerting depend on those features being enabled in the OpenClaw runtime.
- Skill creation depends on the environment allowing local skill authoring.
- Personal customer note URLs depend on a defined internal customer browser URL format.
- `Start a new project` may require new backend support if project creation is not currently exposed.

## Optional Follow-Up Enhancements

- Add a dedicated project-creation MCP tool if the backend supports it.
- Add a customer browser URL convention to the personal notes skill.
- Add a richer `urgent items` rule for scheduled monitoring.
- Add a demo step that combines projects, invoices, and notes into an account summary for Sally before a customer call.
