---
name: urgent-note-delete
description: Delete URGENT project notes created by ProjectHealthCheck to reset OpenClaw alerting test runs
argument-hint: "[customerId] [projectId]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Delete URGENT Project Notes

Remove all URGENT notes created by ProjectHealthCheck for a given project by running `scripts/delete-project-urgent-notes.sh`. Used to reset test runs for OpenClaw alerting/notification testing.

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
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}/notes")
```

- If not `200`, report the error and stop.

## Step 4: Run the script

```bash
BASE_URL=${BASE_URL} ./scripts/delete-project-urgent-notes.sh ${CUSTOMER_ID} ${PROJECT_ID}
```

Report the output from the script.

## Step 5: Confirm deletion

Fetch the notes list and verify no ProjectHealthCheck URGENT notes remain:

```bash
curl -sk "${BASE_URL}/api/customers/${CUSTOMER_ID}/projects/${PROJECT_ID}/notes" | jq '[.[] | select(.noteType == "URGENT" and .author == "ProjectHealthCheck")] | length'
```

- If `0`, report success — test environment is reset.
- If non-zero, report a warning that some notes were not deleted.
