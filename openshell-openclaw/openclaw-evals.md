# Running OpenClaw Evals from the Command Line

This tutorial walks through sending test prompts to an OpenClaw instance
running inside an OpenShell sandbox on OpenShift and inspecting the results.

## Prerequisites

- Logged in to the OpenShift cluster (`oc login` / `cluster-login.sh`)
- OpenShell installed and OpenClaw sandbox deployed
  (steps 1-4 from the main setup)
- The `openshell.sh` wrapper available in this directory

Verify everything is healthy before starting:

```bash
./5-openclaw-status.sh
```

---

## Step 1 — Find the sandbox name

Every OpenClaw instance runs inside a named sandbox. List the sandboxes in
your namespace to find it:

```bash
./openshell.sh sandbox list
```

Example output:

```
NAME           CREATED              PHASE
master-grouse  2026-05-10 13:02:20  Ready
```

The sandbox name (`master-grouse` above) is what you pass to
`sandbox exec`. Save it for convenience:

```bash
SANDBOX=$(./openshell.sh sandbox list 2>/dev/null \
  | sed $'s/\x1b\\[[0-9;]*m//g' \
  | grep -v '^NAME' | awk '{print $1}' | head -1)
echo "Sandbox: $SANDBOX"
```

---

## Step 2 — Find the agent ID

OpenClaw supports multiple isolated agents. List the configured agents:

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- openclaw agents list
```

Example output:

```
Agents:
- main (default)
  Workspace: ~/.openclaw/workspace
  Agent dir: ~/.openclaw/agents/main/agent
  Model: openai/qwen3-14b
  Routing rules: 0
  Routing: default (no explicit rules)
```

The agent ID is the name on the left — `main` in this case. Most single-agent
deployments only have `main`. If you added agents via `openclaw agents add`,
they will appear here with their own IDs.

---

## Step 3 — Run your first eval: "What model are you running?"

Use `openclaw agent` with `--json` for machine-readable output. The command
must run inside the sandbox network namespace so that the OpenShell policy is
enforced:

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "What model are you running?" \
    --json
```

The JSON response contains the full result. The fields you care about most:

| Field | Description |
|-------|-------------|
| `result.payloads[0].text` | The agent's reply |
| `result.meta.agentMeta.model` | The model that actually ran |
| `result.meta.agentMeta.provider` | The provider (openai, anthropic, etc.) |
| `result.meta.durationMs` | Wall-clock time in milliseconds |
| `result.meta.toolSummary.calls` | Number of tool calls the agent made |
| `status` | `ok` or `error` |

To extract just the reply text:

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "What model are you running?" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

> **Note:** We use `python3` instead of `jq` for JSON parsing. When the agent
> makes tool calls (e.g. `exec`), the JSON output can contain raw control
> characters inside string values that cause `jq` to fail with parse errors.
> Python's `json` module handles these natively.

---

## Step 4 — Run more test prompts

Here are a few useful eval prompts to try. Each tests a different aspect
of the agent.

### Basic identity check

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "What is your name and what tools do you have access to?" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

### Tool use — file system

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "List the files in your workspace directory" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

### Policy enforcement — allowed endpoint

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "Use curl to fetch https://api.github.com/zen and tell me what it says" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

### Policy enforcement — blocked endpoint

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --message "Use curl to fetch https://example.com and show me the HTML" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

This should fail because `example.com` is not in the sandbox policy.

---

## Step 5 — Script a batch eval

Combine everything into a simple loop that runs multiple prompts and captures
results:

```bash
#!/usr/bin/env bash
set -euo pipefail

SANDBOX=$(./openshell.sh sandbox list 2>/dev/null \
  | sed $'s/\x1b\\[[0-9;]*m//g' \
  | grep -v '^NAME' | awk '{print $1}' | head -1)

AGENT=main
PROMPTS=(
  "What model are you running?"
  "What is your name?"
  "List the files in your workspace directory"
  "Use curl to fetch https://api.github.com/zen"
  "What is 2+2? Reply with just the number."
)

i=0
for prompt in "${PROMPTS[@]}"; do
  SESSION_ID="eval-$(date +%s)-${i}"
  i=$((i + 1))

  echo "========================================"
  echo "PROMPT: $prompt"
  echo "----------------------------------------"

  ./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
    openclaw agent --agent "$AGENT" \
      --session-id "$SESSION_ID" \
      --message "$prompt" \
      --json 2>/dev/null \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
m = d['result']['meta']
print('MODEL:   ', m['agentMeta']['model'])
print('DURATION:', m['durationMs'], 'ms')
print('TOOLS:   ', m.get('toolSummary', {}).get('calls', 0), 'tool call(s)')
print('REPLY:   ', d['result']['payloads'][0]['text'])
"
  echo ""
done
```

---

## Useful flags

| Flag | Purpose |
|------|---------|
| `--json` | Machine-readable JSON output (diagnostics go to stderr) |
| `--agent <id>` | Target a specific agent (default: routing rules) |
| `--model <id>` | Override the model for this run, e.g. `anthropic/claude-sonnet-4-6` |
| `--thinking <level>` | Set reasoning depth: `off`, `low`, `medium`, `high`, `adaptive` |
| `--timeout <seconds>` | Override the default 600s timeout |
| `--session-id <id>` | Continue an existing conversation (multi-turn eval) |

Example — override the model:

```bash
./openshell.sh sandbox exec -n "$SANDBOX" --no-tty -- \
  openclaw agent --agent main \
    --model anthropic/claude-sonnet-4-6 \
    --message "What model are you running?" \
    --json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['payloads'][0]['text'])"
```

---

## Checking the audit trail

After running evals, you can inspect the sandbox audit logs to see which
network requests were allowed or blocked:

```bash
./openshell.sh logs "$SANDBOX" --since 10m
```

Add `--level warn` to see only denied requests:

```bash
./openshell.sh logs "$SANDBOX" --level warn --since 10m
```
