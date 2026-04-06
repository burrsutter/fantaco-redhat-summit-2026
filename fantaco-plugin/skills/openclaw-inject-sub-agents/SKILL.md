---
name: openclaw-inject-sub-agents
description: Inject FantaCo sub-agents (Account Watchdog, Finance Monitor) into a running OpenClaw config
argument-hint: "[all | account-watchdog | finance-monitor | fantabot]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Inject Sub-Agents into OpenClaw Config

Add FantaCo sub-agents to a running OpenClaw deployment by patching the `openclaw-config` ConfigMap. This renames the default agent to **FantaBot** and injects the **Account Watchdog** and **Finance Monitor** autonomous agents with their own heartbeats.

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

Report the current user and namespace to the user.

## Step 2: Find OpenClaw pod

Verify OpenClaw is running:

```bash
oc get pods -l app=openclaw -o name
```

If no running OpenClaw pods are found, stop with an error: "No running OpenClaw pods found. Deploy OpenClaw first with `/fantaco:deploy-openclaw`."

## Step 3: Resolve argument

Determine which agents to inject based on `$ARGUMENTS`:

| Argument | Behaviour |
|----------|-----------|
| *(empty)* or `all` | Rename default → FantaBot **+** inject Account Watchdog **+** inject Finance Monitor |
| `account-watchdog` | Rename default → FantaBot **+** inject Account Watchdog only |
| `finance-monitor` | Rename default → FantaBot **+** inject Finance Monitor only |
| `fantabot` | Rename default → FantaBot only, no sub-agents |

The FantaBot rename **always** happens regardless of argument — it is a prerequisite for multi-agent setup.

## Step 4: Read current ConfigMap

Fetch the live config:

```bash
oc get configmap openclaw-config -o jsonpath='{.data.openclaw\.json}'
```

If the key is missing or empty, stop with an error: "Could not read openclaw.json from ConfigMap openclaw-config."

Parse the JSON with `python3`. Extract the current `agents.list` array (default to `[]` if missing).

## Step 5: Merge sub-agents into agents.list

Use a single `python3` script to perform all of the following mutations on the parsed config JSON. Track whether any change was made.

### 5a — Rename default agent to FantaBot

Look for an agent with `"default": true` or `"id": "default"` in `agents.list`.

- If found, set `name` to `"FantaBot"` and `workspace` to `"~/.openclaw/workspace/fantabot"` (only if different).
- If not found, **prepend** this entry to `agents.list`:

```json
{
  "id": "default",
  "name": "FantaBot",
  "default": true,
  "workspace": "~/.openclaw/workspace/fantabot"
}
```

### 5b — Inject Account Watchdog (unless argument is `fantabot` or `finance-monitor`)

Check if an agent with `"id": "account-watchdog"` already exists. If yes, skip and report "Account Watchdog already present."

Otherwise append:

```json
{
  "id": "account-watchdog",
  "name": "Account Watchdog",
  "workspace": "~/.openclaw/workspace/watchdog",
  "heartbeat": {
    "every": "2m",
    "target": "telegram",
    "isolatedSession": true,
    "lightContext": true
  }
}
```

> **Note:** The `instructions` key is not supported in the OpenClaw agent schema. Agent behaviour is configured via workspace bootstrap files (e.g. `CLAUDE.md` in the agent's workspace directory).

### 5c — Inject Finance Monitor (unless argument is `fantabot` or `account-watchdog`)

Check if an agent with `"id": "finance-monitor"` already exists. If yes, skip and report "Finance Monitor already present."

Otherwise append:

```json
{
  "id": "finance-monitor",
  "name": "Finance Monitor",
  "workspace": "~/.openclaw/workspace/finance",
  "heartbeat": {
    "every": "2m",
    "target": "telegram",
    "isolatedSession": true,
    "lightContext": true
  }
}
```

### 5d — Early exit if nothing changed

If no mutations were made (all agents already present with correct values), report:

> Already configured — no changes needed. All requested agents are present.

Then display the current agent summary table (see Step 9) and **stop**.

## Step 6: Ensure exec-approvals.json

Check whether the ConfigMap already contains the key `exec-approvals.json`:

```bash
oc get configmap openclaw-config -o jsonpath='{.data.exec-approvals\.json}'
```

If the key is missing or empty, add the following allow-all policy to the patch payload:

```json
{
  "version": "1.0",
  "defaultPolicy": "allow",
  "rules": []
}
```

If already present, leave it untouched and report "exec-approvals.json already present."

## Step 7: Patch ConfigMap

Build a merge-patch payload containing the updated `openclaw.json` (and `exec-approvals.json` if needed). Use `python3` to produce properly escaped JSON, then apply:

```bash
oc patch configmap openclaw-config --type merge -p '<payload>'
```

Report "ConfigMap patched."

## Step 8: Restart pod

Delete the OpenClaw pod so the deployment controller creates a new one with the updated config (the init container copies the ConfigMap to the PVC on startup):

```bash
oc delete pod -l app=openclaw
oc rollout status deployment/openclaw --timeout=120s
```

Report when OpenClaw is ready.

## Step 9: Verify and report

Read the live config from inside the pod:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json
```

Parse the JSON and display a summary table of all agents:

| Agent | ID | Workspace | Heartbeat |
|-------|----|-----------|-----------|
| FantaBot | default | ~/.openclaw/workspace/fantabot | *(uses defaults)* |
| Account Watchdog | account-watchdog | ~/.openclaw/workspace/watchdog | 2m → telegram |
| Finance Monitor | finance-monitor | ~/.openclaw/workspace/finance | 2m → telegram |

Also confirm exec-approvals.json status:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/exec-approvals.json
```

Tell the user: "Sub-agent injection complete. Run the skill again to verify idempotency — it should report 'already configured'."
