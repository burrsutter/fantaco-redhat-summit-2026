---
name: test-openclaw-basic
description: Run Playwright-based UI verification against a live OpenClaw gateway — login, chat, context recall, skill invocation
argument-hint: "[namespace-number]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_type, mcp__playwright__browser_wait_for, mcp__playwright__browser_evaluate, mcp__playwright__browser_close, mcp__playwright__browser_run_code_unsafe, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_fill_form
---

# OpenClaw UI Verification Test

Automated 8-prompt contextual chat test using Playwright MCP tools. Verifies login, chat functionality, identity assignment, context retention, skill creation, skill invocation with name recall, and assistant identity recall.

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

## Step 4: Prompt 1 — Hello

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

## Step 5: Prompt 2 — Establish identity

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
- `inProgress` is `false` (stale spinner tolerance as in Step 4)

Report: `Prompt 2 (identity): PASS` or `FAIL` with details.

## Step 5b: Prompt 3 — Establish context

This tells the assistant the user's role and company, setting up the context recall test.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('I work as a Java developer building microservices at FantaCo');
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
- The assistant acknowledges the context (Java, microservices, or FantaCo)
- `inProgress` is `false` (stale spinner tolerance as in Step 4)

Report: `Prompt 3 (context): PASS` or `FAIL` with details.

## Step 5c: Prompt 4 — Context recall

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

## Step 6: Prompt 5 — Create the friendly-greeter skill

This tests the assistant's ability to create a new skill from a natural-language request.

1. `browser_run_code_unsafe`:
   ```javascript
   async (page) => {
     const ta = await page.$('textarea');
     await ta.fill('Create a skill called friendly-greeter. When invoked, it should greet the user with exactly: Aloha <name>, Welcome to FantaCo — replacing <name> with the name from the message. If no name is given, ask for one. No extra commentary.');
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

## Step 7: Prompt 6 — Invoke the skill with a different name

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
- Response contains "Aloha George, Welcome to FantaCo" (friendly-greeter skill fired with correct name)
- `inProgress` is `false`

Report: `Prompt 6 (skill invocation): PASS` or `FAIL` with details.

## Step 7b: Prompt 7 — Skill invocation with name recall

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
- Response contains "Aloha Takeshi, Welcome to FantaCo" — proving the assistant recalled the user's name from Prompt 2 and invoked the friendly-greeter skill
- `inProgress` is `false`

Report: `Prompt 7 (name recall + skill): PASS` or `FAIL` with details.

## Step 7c: Prompt 8 — Assistant identity recall

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

## Step 8: Cleanup and summary

1. `browser_close` to close the browser

Present the final summary:

```
============================================
  OpenClaw UI Test Results
============================================
  Namespace: <NAMESPACE>
  URL:       <TARGET_URL>

  Login:                            PASS
  Prompt 1 (hello):                 PASS
  Prompt 2 (identity):              PASS
  Prompt 3 (context):               PASS
  Prompt 4 (context recall):        PASS
  Prompt 5 (skill creation):        PASS
  Prompt 6 (skill invocation):      PASS
  Prompt 7 (name recall + skill):   PASS
  Prompt 8 (assistant identity):    PASS

  Result: 9/9 PASSED  (+ login)
============================================
```

If any step failed, include the failure details and a screenshot path if one was taken.

## Error handling

- **Stale element refs:** Always take a fresh `browser_snapshot` before interacting with elements. Prefer `browser_run_code_unsafe` with `page.$('textarea')` for the message input — it is the most reliable method.
- **Timeout on wait_for:** If `browser_wait_for` for expected text times out, take a `browser_take_screenshot` and `browser_evaluate` to capture what IS on the page, then report FAIL with details.
- **No textarea found:** The chat UI may still be loading. `browser_wait_for` with `time: 5` and retry once.
- **Skill creation timeout:** The assistant may take up to 60 seconds to create the skill (involves writing files). If `inProgress` is still `true` after 60 seconds total, report FAIL.
