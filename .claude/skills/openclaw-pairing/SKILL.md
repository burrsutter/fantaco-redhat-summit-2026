---
name: openclaw-pairing
description: List and approve OpenClaw pairing requests via oc exec
argument-hint: "[list | approve <code>] [--channel <channel>]"
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# OpenClaw Pairing Management

Manage pairing requests on the running OpenClaw gateway by exec-ing into the pod.

## Step 1: Verify OpenShift connectivity and find the pod

```bash
oc whoami
oc project -q
```

Find the OpenClaw pod:

```bash
POD=$(oc get pod -l app=openclaw -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"
```

If no pod is found, tell the user to run `/deploy-openclaw` first and **stop**.

## Step 2: Parse arguments and execute

Parse `$ARGUMENTS` to determine the action:

### If `$ARGUMENTS` is empty or `list`

List all pending pairing requests:

```bash
oc exec "$POD" -c gateway -- openclaw pairing list --json
```

If no channel argument is provided and the command fails asking for a channel, try listing available channels:

```bash
oc exec "$POD" -c gateway -- openclaw channels list --json 2>/dev/null
```

Then retry with the channel name:

```bash
oc exec "$POD" -c gateway -- openclaw pairing list <channel> --json
```

Display the results as a table showing pending codes, senders, and timestamps.

If no pending requests, tell the user there are no pairing requests waiting.

### If `$ARGUMENTS` starts with `approve`

Extract the pairing code from `$ARGUMENTS` (everything after `approve`).

If no code is provided, first list pending requests (as above) and ask the user which code to approve using `AskUserQuestion`.

Approve the pairing code:

```bash
oc exec "$POD" -c gateway -- openclaw pairing approve <CODE>
```

If the command fails asking for a channel, try with the channel:

```bash
oc exec "$POD" -c gateway -- openclaw pairing approve <CHANNEL> <CODE>
```

Report success or failure to the user.

### If `$ARGUMENTS` is something else

Show usage:
- `/openclaw-pairing` or `/openclaw-pairing list` — list pending pairing requests
- `/openclaw-pairing approve <CODE>` — approve a specific pairing code
- `/openclaw-pairing approve` — list pending requests and interactively choose one

## Step 3: Summary

After any action, show the current gateway auth token for reference:

```bash
oc exec "$POD" -c gateway -- cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json; print('Gateway token:', json.load(sys.stdin).get('gateway',{}).get('auth',{}).get('token','(not set)'))"
```

And the route URL:

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
echo "Control UI: https://${ROUTE_HOST}"
```
