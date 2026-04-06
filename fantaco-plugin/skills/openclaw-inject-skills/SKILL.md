---
name: openclaw-inject-skills
description: Inject FantaCo claw skills (quote-builder, customer-360, etc.) into a running OpenClaw workspace
argument-hint: "[skill-name or 'all']"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Inject Claw Skills into OpenClaw Workspace

Copy local `claw_skills/` directories into the running OpenClaw pod so they become available as slash commands. Each skill directory must contain a `SKILL.md` file.

Skills must be placed inside the **default agent's workspace** (not the global workspace). Read `openclaw.json` to find the default agent's `workspace` path (e.g., `~/.openclaw/workspace/fantabot`) and place skills under `<agent-workspace>/skills/`.

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

Save the pod name (e.g., `pod/openclaw-xxxxx`) — it will be used for `oc cp` commands.

## Step 3: Discover local skills

List directories under `claw_skills/` that contain a `SKILL.md` file:

```bash
for d in claw_skills/*/; do [ -f "${d}SKILL.md" ] && echo "$d"; done
```

For each discovered skill directory, read the `SKILL.md` frontmatter to extract the `name` and `description` fields.

Display the discovered skills in a table:

| # | Directory | Skill Name | Description |
|---|-----------|------------|-------------|
| 1 | quote-builder | quote_builder | Build a themed project quote... |
| 2 | customer-360 | customer_360 | ... |

If no skills are found, stop with an error: "No claw skills found in `claw_skills/`. Create a skill directory with a `SKILL.md` file first."

## Step 4: Select which skills to inject

Determine which skills to inject based on `$ARGUMENTS`:

- If `$ARGUMENTS` is `all` or empty/not provided → inject **all** discovered skills
- If `$ARGUMENTS` matches a specific directory name (e.g., `quote-builder`) → inject only that one
- Otherwise, use `AskUserQuestion` with `multiSelect: true` to let the user pick which skills to inject. List each discovered skill as an option with its name and description.

## Step 5: Resolve the default agent's workspace path

Read the live OpenClaw config to find the default agent's workspace:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json
```

Parse the JSON and find the agent with `"default": true` in `agents.list`. Use its `workspace` value (e.g., `~/.openclaw/workspace/fantabot`). Resolve `~` to `/home/node`.

This gives the **skills base path**: `<resolved-workspace>/skills/` (e.g., `/home/node/.openclaw/workspace/fantabot/skills/`).

If no default agent is found, fall back to the `agents.defaults.workspace` value, or `/home/node/.openclaw/workspace` as a last resort.

## Step 6: Check what's already in the pod

For each selected skill, check if the skill directory already exists at the skills base path:

```bash
oc exec deployment/openclaw -c gateway -- ls <skills-base-path>/<skill-dir>/SKILL.md 2>/dev/null
```

Where `<skill-dir>` is the directory name (e.g., `quote-builder`).

Track which skills are **new** (not found in pod) and which are **existing** (already present).

If **all** selected skills already exist in the pod, report:

> Already configured — no changes needed. All selected skills are already present in the pod.

Display the summary table (see Step 9) and **stop**.

## Step 7: Copy skills into pod

For each **new** skill (not already in the pod), first ensure the target directory exists, then copy the contents:

```bash
oc exec deployment/openclaw -c gateway -- mkdir -p <skills-base-path>/<skill-dir>
oc cp claw_skills/<skill-dir>/SKILL.md <pod-name>:<skills-base-path>/<skill-dir>/SKILL.md -c gateway
```

If the skill directory contains additional files beyond `SKILL.md`, copy each file individually to avoid `oc cp` directory-nesting issues.

Where `<pod-name>` is the full pod name from Step 2 (without the `pod/` prefix, e.g., `openclaw-xxxxx`).

Report each copy operation as it completes.

**Important:** Use the actual pod name (not `deployment/openclaw`) for `oc cp` because it requires a pod name, not a deployment reference. Use `deployment/openclaw` for `oc exec`.

## Step 8: Restart pod

Delete the OpenClaw pod so the deployment controller creates a new one that picks up the skills:

```bash
oc delete pod -l app=openclaw
oc rollout status deployment/openclaw --timeout=120s
```

Report when OpenClaw is ready.

## Step 9: Verify and report

List all skills inside the pod after restart:

```bash
oc exec deployment/openclaw -c gateway -- find <skills-base-path> -name SKILL.md 2>/dev/null
```

Display a summary table of the injection results:

| Skill | Directory | Status |
|-------|-----------|--------|
| quote_builder | quote-builder | Injected |
| customer_360 | customer-360 | Already present |

Tell the user: "Skill injection complete. The injected skills are now available as slash commands in OpenClaw (e.g., `/quote_builder`)."
