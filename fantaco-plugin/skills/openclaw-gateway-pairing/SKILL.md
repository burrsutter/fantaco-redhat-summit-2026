---
name: openclaw-gateway-pairing
description: Open the OpenClaw Control UI in a browser and approve device pairing
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# OpenClaw Gateway Device Pairing

Pair a browser to the running OpenClaw gateway. This opens the Control UI, displays the gateway token, and approves the device pairing request server-side.

## Step 1: Verify OpenShift connectivity

```bash
oc whoami
oc project -q
```

If either command fails, tell the user to log in to OpenShift first and **stop**.

Report the current user and namespace.

## Step 2: Get route URL and gateway token

Get the route hostname:

```bash
ROUTE_HOST=$(oc get route openclaw-route -o jsonpath='{.spec.host}')
echo "Route: https://${ROUTE_HOST}"
```

If the route is not found, tell the user to run `/fantaco:deploy-openclaw` first and **stop**.

Get the gateway auth token from the running pod:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])"
```

Display both clearly to the user:
- The full URL: `https://<ROUTE_HOST>`
- The gateway token as copyable text

## Step 3: Open browser

Open the Control UI in the default browser:

```bash
open "https://${ROUTE_HOST}"
```

Tell the user to enter the gateway token in the UI login screen.

## Step 4: Wait for user to enter token

Use `AskUserQuestion` to ask the user to confirm what they see after entering the token. Options:

- **"I see pairing required"** — the token was accepted and a device pairing request is pending
- **"Something went wrong"** — an error occurred

If the user selects "Something went wrong", show the last 40 lines of gateway logs and **stop**:

```bash
oc logs deployment/openclaw -c gateway --tail=40
```

## Step 5: Approve the device pairing

**Important:** The `openclaw` CLI cannot connect via plain `oc exec` when the gateway uses `--bind lan`. You must resolve the pod IP and pass connection details explicitly.

First, get the pod IP and the current gateway token:

```bash
POD_IP=$(oc get pod -l app=openclaw -o jsonpath='{.items[0].status.podIP}')
TOKEN=$(oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/openclaw.json | python3 -c "import sys,json; print(json.load(sys.stdin)['gateway']['auth']['token'])")
```

Read the pending request directly from disk to get the request ID:

```bash
oc exec deployment/openclaw -c gateway -- cat /home/node/.openclaw/devices/pending.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
for rid, req in data.items():
    print(f'Request: {rid}  Device: {req.get(\"deviceId\",\"?\")[:16]}...  Platform: {req.get(\"platform\",\"?\")}  Client: {req.get(\"clientId\",\"?\")}')
if not data:
    print('(no pending requests)')
"
```

**If exactly one pending request** — approve it automatically:

```bash
oc exec deployment/openclaw -c gateway -- sh -c "OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1 timeout 15 openclaw devices approve <REQUEST_UUID> --url ws://${POD_IP}:18789 --token ${TOKEN}"
```

**If multiple pending requests** — use `AskUserQuestion` to let the user pick which one to approve, then approve the selected one using the same command pattern.

**If no pending requests** — tell the user no pending device requests were found. Suggest they refresh the browser and re-enter the token, then run `/fantaco:openclaw-gateway-pairing` again.

## Step 6: Confirm success

After approving, tell the user:

1. Refresh the browser — the UI should now connect to the gateway
2. Show the route URL one more time for reference: `https://<ROUTE_HOST>`
