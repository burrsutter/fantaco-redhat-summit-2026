---
name: openclaw-telegram-pairing
description: Approve a Telegram pairing request on the OpenClaw gateway
argument-hint: "[pairing-code]"
disable-model-invocation: true
allowed-tools: Bash, AskUserQuestion
---

# Telegram Pairing

Approve a Telegram pairing code on the running OpenClaw gateway pod. This is the quick path for the most common pairing workflow.

## Step 1: Verify OpenShift connectivity and find the pod

```bash
oc whoami
NAMESPACE=$(oc project -q)
echo "Namespace: $NAMESPACE"
```

Find the OpenClaw pod:

```bash
POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD"
```

If no pod is found, tell the user to run `/deploy-openclaw` first and **stop**.

## Step 2: Resolve the pairing code

If `$ARGUMENTS` contains a pairing code, use it directly.

If `$ARGUMENTS` is empty, list pending Telegram pairing requests:

```bash
oc exec "$POD" -c gateway -n "$NAMESPACE" -- openclaw pairing list telegram --json
```

If no pending requests are found, tell the user there are no Telegram pairing requests waiting and **stop**.

If there are pending requests, display them as a table (code, sender, timestamp) and ask the user which code to approve using `AskUserQuestion`.

## Step 3: Approve the pairing code

```bash
oc exec "$POD" -c gateway -n "$NAMESPACE" -- openclaw pairing approve "$PAIRING_CODE"
```

Report success or failure. On success, tell the user their Telegram client is now paired and ready to use.

## Step 4: Show connection info

```bash
ROUTE_HOST=$(oc get route openclaw-route -n "$NAMESPACE" -o jsonpath='{.spec.host}')
echo "Control UI: https://${ROUTE_HOST}"
```
