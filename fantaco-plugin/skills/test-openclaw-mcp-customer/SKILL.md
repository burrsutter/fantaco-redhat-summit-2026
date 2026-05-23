---
name: test-openclaw-mcp-customer
description: Run Playwright-based UI test against a live OpenClaw gateway — login, send 5 customer MCP prompts, verify tool invocations and responses
argument-hint: "[namespace-number]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_wait_for, mcp__playwright__browser_evaluate, mcp__playwright__browser_close, mcp__playwright__browser_run_code_unsafe, mcp__playwright__browser_take_screenshot
---

# OpenClaw Customer MCP UI Test

Automated 5-prompt customer MCP integration test using Playwright MCP tools. Verifies login, MCP tool invocation (`customer__search_customers`, `customer__get_customer_detail`, etc.), context retention across prompts, and multi-tool chaining.

## Test Prompts

| # | Prompt | Expects |
|---|--------|---------|
| 1 | Search for customers with "coffee" in their name | `customer__search_customers` tool call, results mentioning coffee-related customers |
| 2 | Look up customer CUST001 and show me their details | `customer__get_customer_detail` tool call, customer details returned |
| 3 | I need to find a customer — I think their name has "Tech" in it | `customer__search_customers` tool call, finds Tech-related customer(s) |
| 4 | do they have any ongoing projects | Context recall from prompt 3 — looks up projects for the Tech customer found |
| 5 | Compare customers CUST001 and CUST003 — show me a side-by-side of their details | Multiple `customer__get_customer_detail` calls, comparison output |

## Step 1: Determine target namespace and URL

Parse `$ARGUMENTS`:

- If a number is provided (e.g. `5`), the namespace is `agentic-user5`
- If empty, detect the current namespace via `oc project -q`

Get the route URL:

```bash
oc whoami
ROUTE_HOST=$(oc get route instance -n <NAMESPACE> -o jsonpath='{.spec.host}')
echo "https://${ROUTE_HOST}"
```

If `oc whoami` fails, tell the user to log in and **stop**.
If the route is not found, tell the user to deploy first and **stop**.

Store the full URL as `TARGET_URL` for the rest of the test.

## Step 2: Get the password

Read the password from the `.env` file:

```bash
grep STUDENT_OPENCLAW_PASSWORD "$(cd "$(dirname "$0")" && pwd)/../.env" 2>/dev/null || echo ""
```

If not found, look for it via the secret:

```bash
oc get secret claw-password -n <NAMESPACE> -o jsonpath='{.data.password}' | base64 -d
```

Store as `PASSWORD`. If neither source has a password, ask the user with `AskUserQuestion`.

## Step 3: Navigate and login

1. `browser_navigate` to `TARGET_URL`
2. `browser_snapshot` to inspect the page

The page may show a login form OR auto-connect. Check the snapshot:

- **If login form is visible** (has Password field and Connect button):
  - `browser_snapshot` again to get fresh element refs
  - `browser_type` the password into the Password textbox
  - `browser_click` the Connect button
  - `browser_wait_for` with `time: 3` for connection to establish
- **If already connected** (shows chat UI with message input):
  - Skip login, proceed to Step 4

After login, `browser_snapshot` to confirm the chat UI is visible.

**IMPORTANT — Stale element refs:** The login form often transitions to the chat UI automatically, making element refs from the previous snapshot invalid. If you get a "Ref not found" error:
1. Take a fresh `browser_snapshot`
2. Check if the page has already connected (chat UI visible)
3. If so, skip login and proceed

Report: `Login: PASS` or `Login: SKIP (auto-connected)`

## Step 4: Start a new session

Before running prompts, start a fresh chat session so prior conversation history doesn't interfere:

1. `browser_snapshot` to find the "New session" button in the sidebar
2. `browser_click` the "New session" button (in the sidebar/complementary area, NOT the one in the message bar)
3. `browser_wait_for` with `time: 3`
4. `browser_snapshot` to confirm the fresh session (should show "Ready to chat")

Report: `New session: PASS`

## Step 5: Prompt 1 — Search customers by industry

Tests the `customer__search_customers` MCP tool with a keyword search.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     if (!ta) return 'no textarea found';
     await ta.fill('Search for customers with "coffee" in their name');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 30` — allow time for MCP tool call + LLM response
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-10).map(m => m.textContent.substring(0, 200));
     const toolCalls = [...document.querySelectorAll('button')].filter(b => b.textContent.includes('Customer')).map(b => b.textContent.trim());
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, toolCalls, inProgress });
   }
   ```
4. If `inProgress` is still `true`, wait 15 more seconds and re-check.

**Verify:**
- A `customer__search_customers` or `Customer Search Customers` tool call button is visible
- The response mentions coffee-related customers (e.g. "Brew & Bean", "Coffee")
- `inProgress` is `false`

Report: `Prompt 1 (search by industry): PASS` or `FAIL` with details.

## Step 6: Prompt 2 — Look up specific customer

Tests the `customer__get_customer_detail` MCP tool with a specific customer ID.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Look up customer CUST001 and show me their details');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 30`
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-10).map(m => m.textContent.substring(0, 200));
     const toolCalls = [...document.querySelectorAll('button')].filter(b => b.textContent.includes('Customer')).map(b => b.textContent.trim());
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, toolCalls, inProgress });
   }
   ```
4. If `inProgress` is still `true`, wait 15 more seconds and re-check.

**Verify:**
- A `customer__get_customer_detail` or `Customer Get Customer Detail` tool call button is visible
- The response mentions "CUST001" and shows customer details (name, email, phone, etc.)
- `inProgress` is `false`

Report: `Prompt 2 (customer detail): PASS` or `FAIL` with details.

## Step 7: Prompt 3 — Fuzzy search by name

Tests keyword-based customer search — the assistant should use `customer__search_customers`.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('I need to find a customer — I think their name has "Tech" in it');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 30`
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-10).map(m => m.textContent.substring(0, 200));
     const toolCalls = [...document.querySelectorAll('button')].filter(b => b.textContent.includes('Customer')).map(b => b.textContent.trim());
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, toolCalls, inProgress });
   }
   ```
4. If `inProgress` is still `true`, wait 15 more seconds and re-check.

**Verify:**
- A `customer__search_customers` or `Customer Search Customers` tool call is visible
- The response mentions "Tech Solutions" or similar tech-named customers
- `inProgress` is `false`

Report: `Prompt 3 (fuzzy search): PASS` or `FAIL` with details.

## Step 8: Prompt 4 — Context recall + project lookup

Tests context retention — the assistant should remember the Tech customer from Prompt 3 and look up their projects without being told which customer.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('do they have any ongoing projects');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 30`
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-10).map(m => m.textContent.substring(0, 200));
     const toolCalls = [...document.querySelectorAll('button')].filter(b => b.textContent.includes('Customer') || b.textContent.includes('Project')).map(b => b.textContent.trim());
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, toolCalls, inProgress });
   }
   ```
4. If `inProgress` is still `true`, wait 15 more seconds and re-check.

**Verify:**
- The assistant connects this to the Tech customer from Prompt 3 (context recall)
- Tool call(s) visible (may use customer detail, project search, or similar)
- Response discusses projects for the Tech customer
- `inProgress` is `false`

Report: `Prompt 4 (context + projects): PASS` or `FAIL` with details.

## Step 9: Prompt 5 — Multi-customer comparison

Tests chaining multiple MCP tool calls to compare two customers.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Compare customers CUST001 and CUST003 — show me a side-by-side of their details');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 45` — this prompt may trigger multiple tool calls
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, [role="log"] th, [role="log"] td, .message-content')];
     const lastMsgs = msgs.slice(-15).map(m => m.textContent.substring(0, 200));
     const toolCalls = [...document.querySelectorAll('button')].filter(b => b.textContent.includes('Customer')).map(b => b.textContent.trim());
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, toolCalls, inProgress });
   }
   ```
4. If `inProgress` is still `true`, wait 20 more seconds and re-check.

**Verify:**
- At least two `Customer Get Customer Detail` tool calls visible (one for CUST001, one for CUST003)
- The response mentions both "CUST001" and "CUST003" with comparison details
- `inProgress` is `false`

Report: `Prompt 5 (multi-customer compare): PASS` or `FAIL` with details.

## Step 10: Screenshot and summary

1. `browser_take_screenshot` with `fullPage: true` and filename `mcp-customer-test-final.png`
2. `browser_close` to close the browser

Present the final summary:

```
============================================
  Customer MCP UI Test Results
============================================
  Namespace: <NAMESPACE>
  URL:       <TARGET_URL>

  Login:                              PASS
  New session:                        PASS
  Prompt 1 (search by industry):      PASS
  Prompt 2 (customer detail):         PASS
  Prompt 3 (fuzzy search):            PASS
  Prompt 4 (context + projects):      PASS
  Prompt 5 (multi-customer compare):  PASS

  Result: 7/7 PASSED
============================================
```

If any step failed, include the failure details and a screenshot path if one was taken.

## Error handling

- **Stale element refs:** Always take a fresh `browser_snapshot` before interacting with elements. Prefer `browser_run_code_unsafe` with `page.$('textarea')` for the message input — it is the most reliable method.
- **Timeout on wait_for:** If `browser_wait_for` for expected text times out, take a `browser_take_screenshot` and `browser_evaluate` to capture what IS on the page, then report FAIL with details.
- **No textarea found:** The chat UI may still be loading. `browser_wait_for` with `time: 5` and retry once.
- **MCP tool not invoked:** If the assistant responds without calling an MCP tool, mark as FAIL — this means the MCP integration is not working.
- **403 or connection errors in tool output:** If you see 403 in tool results, the proxy NetworkPolicy or passthrough route is misconfigured. Report FAIL with suggestion to check `allow-proxy-to-mcp` NetworkPolicy and Claw CR `spec.mcpServers`.
