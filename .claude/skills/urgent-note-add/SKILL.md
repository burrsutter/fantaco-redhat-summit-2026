---
name: urgent-note-add
description: Create a deterministic URGENT project note for testing OpenClaw alerting/notification
argument-hint: "[customerId] [projectId]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Create URGENT Project Note

Generate a deterministic URGENT project note by running `scripts/analyze-project-urgent-note.sh`. The note includes milestone summary and IN_PROGRESS task context.

## Step 1: Parse arguments

Parse `$ARGUMENTS`:

- If no arguments provided, default to `CUST003 1`
- If one argument, treat as `<customerId>` and default projectId to `1`
- If two arguments, treat as `<customerId> <projectId>`

Store as `CUSTOMER_ID` and `PROJECT_ID`.

## Step 2: Determine the Customer API base URL

Try OpenShift first, then fall back to localhost:

```bash
OC_HOST=$(oc get route fantaco-customer-service -o jsonpath='{.spec.host}' 2>/dev/null || true)
```

- If `OC_HOST` is non-empty, set `BASE_URL=https://${OC_HOST}`
- If empty, set `BASE_URL=http://localhost:8081`

Report which target is being used (OpenShift route or localhost).

## Step 3: Verify the API is reachable

```bash
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}")
```

- If not `200`, report the error and stop.

## Step 4: Run the script

```bash
BASE_URL=${BASE_URL} ./scripts/analyze-project-urgent-note.sh ${CUSTOMER_ID} ${PROJECT_ID}
```

Report the full JSON response from the script.

## Step 5: Confirm the note was created

Fetch the notes list and show the newly created URGENT note:

```bash
curl -sk "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}/notes" | jq '.[] | select(.noteType == "URGENT" and .author == "ProjectHealthCheck")'
```

Report success with the note ID and a reminder that `scripts/delete-project-urgent-notes.sh` can be used to reset.
