---
name: deploy-backends
description: Deploy FantaCo backend microservices and their PostgreSQL databases to OpenShift
argument-hint: "[all | customer | finance | product | sales-order | hr-recruiting]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Deploy FantaCo Backend Services

Deploy one or more FantaCo backend microservices and their PostgreSQL databases to the current OpenShift namespace using raw Kubernetes manifests.

## Available Services

| Key          | Directory                  | App Port | DB Service     |
|--------------|----------------------------|----------|----------------|
| customer     | fantaco-customer-main      | 8081     | postgres-cust  |
| finance      | fantaco-finance-main       | 8082     | postgres-fin   |
| product      | fantaco-product-main       | 8083     | postgres-prod  |
| sales-order  | fantaco-sales-order-main   | 8084     | postgres-sord  |
| hr-recruiting | fantaco-hr-recruiting      | 8085     | postgres-hr-recruiting |

## Step 1: Verify OpenShift connectivity

Run these checks and **stop if any fail**:

```bash
oc whoami
oc project -q
```

Report the current user and namespace to the user.

## Step 2: Determine which services to deploy

Parse `$ARGUMENTS`:

- If `$ARGUMENTS` is empty or `all` — deploy all 5 services
- If `$ARGUMENTS` contains one or more service keys (space-separated) — deploy only those
- Valid keys: `customer`, `finance`, `product`, `sales-order`, `hr-recruiting`
- If an invalid key is provided, report the error and list valid keys

Map service keys to directories:
- `customer` → `fantaco-customer-main`
- `finance` → `fantaco-finance-main`
- `product` → `fantaco-product-main`
- `sales-order` → `fantaco-sales-order-main`
- `hr-recruiting` → `fantaco-hr-recruiting`

## Step 3: Deploy PostgreSQL databases first

For each selected service, deploy its database (postgres must be ready before the app):

```bash
cd <service-directory>
oc apply -f deployment/kubernetes/postgres/deployment.yaml
oc apply -f deployment/kubernetes/postgres/service.yaml
```

Do this for **all selected services** before moving to Step 4.

## Step 4: Wait for databases

Wait 15 seconds, then verify all postgres pods are running:

```bash
oc get pods -l app=postgres-cust   # (for customer)
oc get pods -l app=postgres-fin    # (for finance)
oc get pods -l app=postgres-prod   # (for product)
oc get pods -l app=postgres-sord   # (for sales-order)
oc get pods -l app=postgres-hr-recruiting  # (for hr-recruiting)
```

Only check pods for the selected services. If any postgres pod is not Running after 60 seconds, warn the user but continue.

## Step 5: Deploy application services

For each selected service, first check if the deployment already exists:

```bash
oc get deployment <service-name> -o name 2>/dev/null
```

Then apply the Kubernetes manifests:

```bash
cd <service-directory>
oc apply -f deployment/kubernetes/application/configmap.yaml
oc apply -f deployment/kubernetes/application/secret.yaml
oc apply -f deployment/kubernetes/application/deployment.yaml
oc apply -f deployment/kubernetes/application/service.yaml
oc apply -f deployment/kubernetes/application/route.yaml
```

**Only if the deployment already existed before the apply**, restart the pod to pick up config changes:

```bash
oc delete pod -l app=<service-name>
```

Do NOT delete the pod on a fresh first-time deploy — `oc apply` already creates a new pod and deleting it just wastes time.

Where `<service-name>` matches the deployment label:
- `fantaco-customer-main`
- `fantaco-finance-main`
- `fantaco-product-main`
- `fantaco-sales-order-main`
- `fantaco-hr-recruiting`

## Step 6: Verify deployment

Wait 20 seconds, then check pod status:

```bash
oc get pods
```

List which pods are Running and which are not. For any pod in Error or CrashLoopBackOff, show the last 20 lines of logs:

```bash
oc logs deployment/<service-name> --tail=20
```

## Step 7: Display routes

Show the routes for all deployed services:

```bash
oc get routes -o custom-columns="NAME:.metadata.name,URL:.spec.host"
```

Present a summary table with `https://` prefixed URLs for the deployed services.

## Step 8: Smoke test

For each deployed service, run a quick health check:

| Service      | Health Path                    | Data Path            |
|--------------|-------------------------------|----------------------|
| customer     | /actuator/health/liveness     | /api/customers       |
| finance      | /actuator/health/liveness     | /api/finance/invoices|
| product      | /actuator/health/liveness     | /api/products        |
| sales-order  | /actuator/health/liveness     | /api/sales-orders    |
| hr-recruiting | /actuator/health/liveness     | /api/jobs            |

```bash
ROUTE_HOST=$(oc get route <route-name> -o jsonpath='{.spec.host}')
curl -sk -o /dev/null -w "%{http_code}" "https://${ROUTE_HOST}<health-path>"
```

Route names:
- `fantaco-customer-service`
- `fantaco-finance-service`
- `fantaco-product-service`
- `fantaco-sales-order-service`
- `fantaco-hr-recruiting-service`

Present results as a summary table showing health and data endpoint status for each service.
