---
name: test-openclaw-lb
description: Run Playwright-based UI verification through the yougetaclaw.com load balancer — broker redirect, login, chat, context recall, skill invocation, status board
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_wait_for, mcp__playwright__browser_evaluate, mcp__playwright__browser_close, mcp__playwright__browser_run_code_unsafe, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_fill_form, mcp__playwright__browser_tabs
---

# OpenClaw Load Balancer UI Verification Test

Automated test through the `yougetaclaw.com` session broker. Verifies broker redirect, cookie assignment, login, 6 chat prompts (hello, identity, context, context recall, skill creation, skill invocation), and status board — all without requiring `oc` cluster access.

## Step 1: Check broker status (pre-test)

Verify the broker has routes available before starting.

1. `browser_navigate` to `https://yougetaclaw.com/status/api`
2. `browser_evaluate` to extract the JSON:
   ```javascript
   () => {
     try {
       return document.body.innerText;
     } catch (e) {
       return JSON.stringify({ error: e.message });
     }
   }
   ```
3. Parse the JSON response. Check:
   - `total > 0` — routes are loaded
   - `available > 0` — at least one route is free to assign

If `total === 0`, report **"No routes loaded — run audience-reset.sh first"** and **stop**.
If `available === 0`, report **"All routes assigned — run 09-broker-reset.sh to free routes"** and **stop**.

Record the baseline `assigned` count for later comparison.

Report: `Broker status: PASS (X total, Y available, Z assigned)`

## Step 2: Get the password

Read the password from the `.env` file:

```bash
grep STUDENT_OPENCLAW_PASSWORD "$(cd "$(dirname "$0")" && pwd)/../.env" 2>/dev/null || echo ""
```

This test does **not** require `oc` — no cluster fallback. If the password is not found in `.env`, use `AskUserQuestion` to ask the user.

Store as `PASSWORD`.

## Step 3: Visit yougetaclaw.com — verify broker redirect

1. `browser_navigate` to `https://yougetaclaw.com`
2. `browser_wait_for` with `time: 5` — allow the broker redirect chain to complete
3. `browser_evaluate` to capture the final URL:
   ```javascript
   () => window.location.href
   ```

**Verify:**
- The final URL matches the pattern `https://claw-*.yougetaclaw.com/...` — proving the broker performed a 302 redirect to an assigned backend
- Extract and store the assigned public host (e.g. `claw-user5.yougetaclaw.com`) for later verification against the status board

Report: `Broker redirect: PASS (→ <assigned-host>)` or `FAIL` with the actual URL.

## Step 4: Login

1. `browser_snapshot` to inspect the page

The page may show a login form OR auto-connect. Check the snapshot:

- **If login form is visible** (has Password field and Connect button):
  - `browser_snapshot` again to get fresh element refs
  - `browser_type` the password into the Password textbox
  - `browser_click` the Connect button
  - `browser_wait_for` with `time: 3` for connection to establish
- **If already connected** (shows chat UI with message input):
  - Skip login, proceed to Step 5

After login, `browser_snapshot` to confirm the chat UI is visible.

**IMPORTANT — Stale element refs:** The login form often transitions to the chat UI automatically, making element refs from the previous snapshot invalid. If you get a "Ref not found" error:
1. Take a fresh `browser_snapshot`
2. Check if the page has already connected (chat UI visible)
3. If so, skip login and proceed

Report: `Login: PASS` or `Login: SKIP (auto-connected)`

## Step 5: Prompt 1 — Hello

A simple greeting to trigger the bootstrap flow on a fresh instance.

1. Focus the message input. Use `browser_run_code_unsafe` as the most reliable method:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     if (!ta) return 'no textarea found';
     await ta.fill('Hello');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 15` — allow the bootstrap response to generate
3. `browser_evaluate` to check response and spinner state:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-4).map(m => m.textContent.substring(0, 120));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- The assistant responds with a greeting or bootstrap prompt
- `inProgress` is `false` — **however**, on a freshly reset instance the first prompt triggers the bootstrap identity flow, which can leave `inProgress: true` due to background file writes. If a response appeared but `inProgress` is still `true`, wait up to 30 more seconds. If it remains `true` after that, still mark as **PASS** — this is a known stale spinner issue on first bootstrap and does not indicate a real failure.

Report: `Prompt 1 (hello): PASS` or `FAIL` with details.

## Step 6: Prompt 2 — Establish identity

This prompt sets both the user's name and the assistant's name.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('My name is Takeshi and your name is Nokori');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `text: "Takeshi"` — wait for the assistant to acknowledge the name
3. `browser_wait_for` with `time: 15` — allow the full response to generate
4. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-4).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- The response mentions "Takeshi" and/or "Nokori" — proving the assistant accepted the identity assignment
- `inProgress` is `false` (stale spinner tolerance as in Step 5)

Report: `Prompt 2 (identity): PASS` or `FAIL` with details.

## Step 6b: Prompt 3 — Establish context

This tells the assistant the user's role and company, setting up the context recall test.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('I work as a Java developer building microservices at StarFleet Industries');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 15` — allow the response to generate
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-4).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- The assistant acknowledges the context (Java, microservices, or StarFleet Industries)
- `inProgress` is `false` (stale spinner tolerance as in Step 5)

Report: `Prompt 3 (context): PASS` or `FAIL` with details.

## Step 6c: Prompt 4 — Context recall

This tests whether the assistant remembers the Java/microservices context from Prompt 3.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('What framework would you recommend for my next project?');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `time: 20` — this prompt needs more thinking time
3. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-5).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- The response references Java-relevant frameworks (Quarkus, Spring Boot, Micronaut, etc.) — proving it retained the Java developer context from Prompt 3
- `inProgress` is `false`

Report: `Prompt 4 (context recall): PASS` or `FAIL` with details.

## Step 7: Prompt 5 — Create the friendly-greeter skill

This tests the assistant's ability to create a new skill from a natural-language request.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Create a skill called friendly-greeter. When invoked, it should greet the user with exactly: Aloha <name>, Welcome to Red Hat — replacing <name> with the name from the message. If no name is given, ask for one. No extra commentary.');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `text: "friendly-greeter"` — wait for the assistant to acknowledge it is working on the skill
3. `browser_wait_for` with `time: 30` — skill creation involves file writes and may take a while
4. `browser_evaluate` to check response:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-5).map(m => m.textContent.substring(0, 250));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```
5. If `inProgress` is still `true`, wait another 30 seconds and re-check. The assistant may need time to write files.

**Verify:**
- The assistant confirms the skill was created (mentions "created", "saved", "done", or similar)
- `inProgress` is `false`

Report: `Prompt 5 (skill creation): PASS` or `FAIL` with details.

## Step 8: Prompt 6 — Invoke the skill with a different name

This tests that the newly created friendly-greeter skill works with an explicit name.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Use the friendly-greeter skill to greet George');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `text: "Aloha George"` — the friendly-greeter should produce the full greeting
   - If this times out after 30 seconds, take a screenshot and check what response was given
3. `browser_wait_for` with `time: 5` — allow response to fully render
4. `browser_evaluate` to check final state:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-3).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- Response contains "Aloha George, Welcome to Red Hat" (friendly-greeter skill fired with correct name)
- `inProgress` is `false`

Report: `Prompt 6 (skill invocation): PASS` or `FAIL` with details.

## Step 8b: Prompt 7 — Skill invocation with name recall

This tests that the skill can be invoked without an explicit name, requiring the assistant to recall the user's name from Prompt 2.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Now greet me');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `text: "Aloha Takeshi"` — the assistant should recall the user's name and invoke the skill
   - If this times out after 30 seconds, take a screenshot and check what response was given
3. `browser_wait_for` with `time: 5` — allow response to fully render
4. `browser_evaluate` to check final state:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-3).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- Response contains "Aloha Takeshi, Welcome to Red Hat" — proving the assistant recalled the user's name from Prompt 2 and invoked the friendly-greeter skill
- `inProgress` is `false`

Report: `Prompt 7 (name recall + skill): PASS` or `FAIL` with details.

## Step 8c: Prompt 8 — Assistant identity recall

This tests that the assistant remembers its own name set in Prompt 2.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('what is your name?');
     await ta.press('Enter');
     return 'sent';
   }
   ```
2. `browser_wait_for` with `text: "Nokori"` — the assistant should respond with its name
   - If this times out after 15 seconds, take a screenshot and check what response was given
3. `browser_wait_for` with `time: 5` — allow response to fully render
4. `browser_evaluate` to check final state:
   ```javascript
   () => {
     const msgs = [...document.querySelectorAll('[role="log"] p, [role="log"] li, .message-content')];
     const lastMsgs = msgs.slice(-3).map(m => m.textContent.substring(0, 200));
     const inProgress = document.body.innerText.includes('In progress');
     return JSON.stringify({ lastMsgs, inProgress });
   }
   ```

**Verify:**
- Response contains "Nokori" — proving the assistant remembers its own name from Prompt 2
- `inProgress` is `false`

Report: `Prompt 8 (assistant identity): PASS` or `FAIL` with details.

## Step 9: Verify status board

Confirm the status board reflects the assignment made in Step 3.

1. `browser_tabs` with `action: "new"` and `url: "https://yougetaclaw.com/status"`
2. `browser_wait_for` with `time: 3` — allow the status page to load
3. `browser_snapshot` to inspect the status board table
4. Look for the assigned host from Step 3 in the table — it should show `● assigned` status

**Verify:**
- The assigned host appears in the status board
- Its status indicator shows assigned (green dot / `● assigned`)

Report: `Status board: PASS (<assigned-host> shows assigned)` or `FAIL` with details.

## Step 10: Cleanup and summary

1. `browser_close` to close the browser

Present the final summary:

```
============================================
  OpenClaw Load Balancer Test Results
============================================
  Entry:     https://yougetaclaw.com
  Assigned:  <assigned-host>

  Broker status:                    PASS
  Broker redirect:                  PASS
  Login:                            PASS
  Prompt 1 (hello):                PASS
  Prompt 2 (identity):             PASS
  Prompt 3 (context):              PASS
  Prompt 4 (context recall):       PASS
  Prompt 5 (skill creation):       PASS
  Prompt 6 (skill invocation):     PASS
  Prompt 7 (name recall + skill):  PASS
  Prompt 8 (assistant identity):   PASS
  Status board:                     PASS

  Result: 11/11 PASSED  (+ login)
============================================
```

If any step failed, include the failure details and a screenshot path if one was taken.

## Error handling

- **Stale element refs:** Always take a fresh `browser_snapshot` before interacting with elements. Prefer `browser_run_code_unsafe` with `page.$('textarea')` for the message input — it is the most reliable method.
- **Timeout on wait_for:** If `browser_wait_for` for expected text times out, take a `browser_take_screenshot` and `browser_evaluate` to capture what IS on the page, then report FAIL with details.
- **No textarea found:** The chat UI may still be loading. `browser_wait_for` with `time: 5` and retry once.
- **Skill creation timeout:** The assistant may take up to 60 seconds to create the skill (involves writing files). If `inProgress` is still `true` after 60 seconds total, report FAIL.
- **Broker redirect failure:** If the final URL after navigating to `yougetaclaw.com` does not match `claw-*.yougetaclaw.com`, take a screenshot and report FAIL — the broker may be down or misconfigured.
