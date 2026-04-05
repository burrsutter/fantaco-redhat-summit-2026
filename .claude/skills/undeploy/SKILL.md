---
name: undeploy
description: Remove all FantaCo resources from the current OpenShift namespace
argument-hint: "[all | openclaw | mcp | backends]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Undeploy FantaCo Resources

Remove FantaCo demo stack resources from the current OpenShift namespace in reverse deployment order (OpenClaw → MCP servers → Backend services).

---

## Step 1 — Verify OpenShift connectivity

Run `oc whoami` and `oc project -q`. If either fails, stop and tell the user to log in first with `oc login`.

Store the namespace name for use in later messages.

---

## Step 2 — Parse scope from `$ARGUMENTS`

Determine the scope from `$ARGUMENTS`:
- `all` (default if empty/blank) — remove everything
- `openclaw` — only OpenClaw gateway + filebrowser sidecar
- `mcp` — only MCP servers
- `backends` — only backend microservices + databases

If `$ARGUMENTS` is not one of these values, tell the user the valid options and stop.

---

## Step 3 — Inventory existing resources

Build an inventory of what currently exists in the namespace. Run these checks:

**Helm releases:**
```bash
helm list --short 2>/dev/null
```

**OpenClaw resources (if scope is `all` or `openclaw`):**
```bash
oc get deployment openclaw --no-headers 2>/dev/null
oc get pvc openclaw-data --no-headers 2>/dev/null
oc get service openclaw-service openclaw-filebrowser-service --no-headers 2>/dev/null
oc get route openclaw-route openclaw-filebrowser-route --no-headers 2>/dev/null
```

**MCP resources (if scope is `all` or `mcp`):**
```bash
oc get deployment mcp-customer mcp-finance mcp-product mcp-sales-order mcp-sales-policy-search mcp-hr-policy --no-headers 2>/dev/null
```

**Backend resources (if scope is `all` or `backends`):**
```bash
oc get deployment fantaco-customer-main fantaco-finance-main fantaco-product-main fantaco-sales-order-main fantaco-hr-recruiting fantaco-sales-policy-search fantaco-hr-policy-search --no-headers 2>/dev/null
oc get deployment postgres-cust postgres-fin postgres-prod postgres-sord postgres-hr-recruiting fantaco-sales-policy-search-db fantaco-hr-policy-search-db --no-headers 2>/dev/null
oc get deployment postgresql-customer postgresql-finance postgresql-product postgresql-sales-order postgresql-hr-recruiting --no-headers 2>/dev/null
```

**PVCs:**
```bash
oc get pvc --no-headers 2>/dev/null
```

**Pod count:**
```bash
oc get pods --no-headers 2>/dev/null | wc -l
```

Build a summary grouped by tier showing what was found. If nothing is found for the selected scope, tell the user there's nothing to undeploy and stop.

---

## Step 4 — Confirm with user

Use AskUserQuestion to show the inventory summary and ask for confirmation. Provide three options:

1. **"Yes, delete everything"** — remove all resources including PVCs (data will be lost)
2. **"Yes, but keep PVCs"** — remove workloads but preserve persistent volume claims
3. **"Abort"** — cancel the operation

If the user chooses "Abort", stop immediately with a message that nothing was changed.

---

## Step 5 — Undeploy OpenClaw (Tier 1)

**Skip this step if scope is `mcp` or `backends`.**

Delete OpenClaw gateway and filebrowser sidecar resources:

```bash
oc delete deployment/openclaw --ignore-not-found
oc delete service/openclaw-service service/openclaw-filebrowser-service --ignore-not-found
oc delete route/openclaw-route route/openclaw-filebrowser-route --ignore-not-found
oc delete configmap/openclaw-config configmap/filebrowser-config --ignore-not-found
oc delete secret/openclaw-secrets --ignore-not-found
oc delete networkpolicy/openclaw-egress --ignore-not-found
```

Report what was deleted.

---

## Step 6 — Delete OpenClaw PVC (conditional)

**Skip if:**
- Scope is `mcp` or `backends`
- User chose "Yes, but keep PVCs"

```bash
oc delete pvc/openclaw-data --ignore-not-found
```

---

## Step 7 — Undeploy MCP servers (Tier 2)

**Skip this step if scope is `openclaw` or `backends`.**

First try Helm uninstall:
```bash
helm uninstall fantaco-mcp 2>/dev/null
```

Then clean up any raw-manifest resources (covers non-Helm deployments or leftovers):
```bash
oc delete deployment/mcp-customer deployment/mcp-finance deployment/mcp-product deployment/mcp-sales-order deployment/mcp-sales-policy-search deployment/mcp-hr-policy --ignore-not-found

oc delete service/mcp-customer-service service/mcp-finance-service service/mcp-product-service service/mcp-sales-order-service service/mcp-sales-policy-search-service service/mcp-hr-policy-service --ignore-not-found

oc delete route/mcp-customer-route route/mcp-finance-route route/mcp-product-route route/mcp-sales-order-route route/mcp-sales-policy-search-route route/mcp-hr-policy-route --ignore-not-found
```

Report what was deleted.

---

## Step 8 — Undeploy backend services (Tier 3)

**Skip this step if scope is `openclaw` or `mcp`.**

First try Helm uninstall:
```bash
helm uninstall fantaco-app 2>/dev/null
```

Then clean up any raw-manifest resources (covers non-Helm deployments or leftovers):

**Application deployments:**
```bash
oc delete deployment/fantaco-customer-main deployment/fantaco-finance-main deployment/fantaco-product-main deployment/fantaco-sales-order-main deployment/fantaco-hr-recruiting deployment/fantaco-sales-policy-search deployment/fantaco-hr-policy-search --ignore-not-found
```

**Database deployments (both `postgres-*` and `postgresql-*` naming variants):**
```bash
oc delete deployment/postgres-cust deployment/postgres-fin deployment/postgres-prod deployment/postgres-sord deployment/postgres-hr-recruiting deployment/fantaco-sales-policy-search-db deployment/fantaco-hr-policy-search-db --ignore-not-found

oc delete deployment/postgresql-customer deployment/postgresql-finance deployment/postgresql-product deployment/postgresql-sales-order deployment/postgresql-hr-recruiting --ignore-not-found
```

**Application services:**
```bash
oc delete service/fantaco-customer-service service/fantaco-finance-service service/fantaco-product-service service/fantaco-sales-order-service service/fantaco-hr-recruiting-service service/fantaco-sales-policy-search-service service/fantaco-hr-policy-search-service --ignore-not-found
```

**Database services (both `postgres-*` and `postgresql-*` naming variants):**
```bash
oc delete service/postgres-cust service/postgres-fin service/postgres-prod service/postgres-sord service/postgres-hr-recruiting service/fantaco-sales-policy-search-db service/fantaco-hr-policy-search-db --ignore-not-found

oc delete service/postgresql-customer service/postgresql-finance service/postgresql-product service/postgresql-sales-order service/postgresql-hr-recruiting --ignore-not-found
```

**Routes:**
```bash
oc delete route/fantaco-customer-service route/fantaco-finance-service route/fantaco-product-service route/fantaco-sales-order-service route/fantaco-hr-recruiting-service route/fantaco-sales-policy-search-route route/fantaco-hr-policy-search-route --ignore-not-found
```

Report what was deleted.

---

## Step 9 — Delete remaining PVCs (conditional)

**Skip if:**
- User chose "Yes, but keep PVCs"
- Scope does not include `backends`

List and delete all remaining PVCs in the namespace:
```bash
oc get pvc --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | while read pvc; do
  oc delete pvc "$pvc" --ignore-not-found
done
```

---

## Step 10 — Wait for cleanup

```bash
sleep 10
```

Allow time for OpenShift to terminate pods and clean up resources.

---

## Step 11 — Verify namespace is clean

Check for any remaining resources:
```bash
oc get pods --no-headers 2>/dev/null
oc get deployments --no-headers 2>/dev/null
oc get services --no-headers 2>/dev/null
oc get routes --no-headers 2>/dev/null
oc get pvc --no-headers 2>/dev/null
```

Report any stragglers that remain. If resources still exist, suggest the user wait and re-run or manually delete them.

---

## Step 12 — Summary report

Print a summary table showing what was removed per tier:

```
=== FantaCo Undeploy Summary ===

Namespace: <namespace>
Scope:     <scope>

Tier 1 — OpenClaw:    <removed / skipped / not found>
Tier 2 — MCP Servers: <removed / skipped / not found>
Tier 3 — Backends:    <removed / skipped / not found>
PVCs:                 <removed / kept / not found>

Stragglers:           <none / list any remaining>
```

If everything was removed, tell the user the namespace is clean.

Provide redeploy instructions:
```
To redeploy, run these skills in order:
  1. /deploy-backends
  2. /deploy-mcp-servers
  3. /deploy-openclaw
  4. /inject-mcp-openclaw
```
