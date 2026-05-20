# Claw-Operator Deployment Scripts

Automate deployment of OpenClaw instances via the claw-operator for Red Hat Summit demo namespaces.

## Prerequisites

- `oc login` as cluster-admin (for admin setup) or as student user (for verification)
- `../.env` populated with credentials (copy from `../.env.example`)
- claw-operator repo available locally (default: `../../claw-operator`)

## Step 0: Admin Setup (one-time)

Install the claw-operator, create RBAC, and grant access to student namespaces:

```bash
# For agentic-user2 through agentic-user5
./0-admin-setup.sh 2 5

# Just agentic-user3
./0-admin-setup.sh 3
```

This script:
1. Installs the claw-operator (if not already running) via `make dev-deploy`
2. Patches memory limits to prevent OOMKilled (512Mi limit / 128Mi request)
3. Creates the `claw-user` ClusterRole
4. Grants `claw-user` role to each student user in their namespace

## Step 1: Deploy Claw Instances

Create secrets and Claw CRs in each namespace:

```bash
# Deploy to agentic-user2 through agentic-user5
./1-deploy-claw.sh 2 5

# Just agentic-user3
./1-deploy-claw.sh 3
```

This script:
1. Sources `../.env` for API keys and passwords
2. Creates the API key secret (provider-specific)
3. Creates the password secret (`claw-password`)
4. Applies the Claw CR with password auth enabled
5. Waits for all 3 pods per namespace (up to 120s)
6. Prints the URL for each instance

## Step 2: Check Health

Run the automated health check across namespaces:

```bash
# Check agentic-user2 through agentic-user5
./2-openclaw-status.sh 2 5

# Just agentic-user3
./2-openclaw-status.sh 3
```

This script checks:
1. Claw-operator pod is running
2. All 3 instance pods (instance, instance-proxy, instance-device-pairing) are Running
3. Claw CR status conditions
4. Gateway logs for errors
5. URL is reachable (HTTP 200/302)

## Step 3: Open in Browser

Open the OpenClaw UI for one or more namespaces:

```bash
# Open agentic-user2 through agentic-user5
./3-open-openclaw.sh 2 5

# Just agentic-user3
./3-open-openclaw.sh 3
```

Gets the URL from the Claw CR status and opens it in the default browser. Students enter the password when prompted.

## Provider Selection

Set `LLM_PROVIDER` env var before running `1-deploy-claw.sh`:

| Provider | `LLM_PROVIDER` | Env vars needed | Auth type |
|----------|----------------|-----------------|-----------|
| LiteLLM (default) | `litellm` | `LLM_API_KEY`, `LLM_API_BASE_URL` | bearer |
| Anthropic | `anthropic` | `ANTHROPIC_API_KEY` | apiKey |
| OpenAI | `openai` | `OPENAI_API_KEY` | apiKey |

Example:
```bash
LLM_PROVIDER=anthropic ./1-deploy-claw.sh 2 5
```

## Cluster Login Helper

Log in as a student user or admin without remembering the API server URL:

```bash
# Log in as user3
./cluster-login.sh 3

# Log in as admin
./cluster-login.sh admin
```

Sources `../.env` for credentials and derives the API server URL from `OPENSHIFT_CONSOLE_URL`.

## Cleanup

Remove Claw CR and secrets from student namespaces (preserves operator and ClusterRole):

```bash
# Clean agentic-user2 through agentic-user5
./clean-namespace.sh 2 5

# Just agentic-user3
./clean-namespace.sh 3
```

This script:
1. Deletes the Claw CR (triggers operator cleanup of deployments/services/routes)
2. Waits for pods to terminate (up to 120s)
3. Deletes secrets (litellm-api-key, anthropic-api-key, openai-api-key, claw-password)

To uninstall the operator itself:
```bash
cd ../../claw-operator
make undeploy
```

## Useful Commands

```bash
# Get the URL for a namespace
oc get claw instance -n agentic-user2 -o jsonpath='{.status.url}'

# Check gateway logs
oc logs deployment/instance -n agentic-user2 -c gateway --tail=30

# Check proxy logs
oc logs deployment/instance-proxy -n agentic-user2 --tail=30

# List all Claw instances across namespaces
oc get claws -A
```

## Environment Variables

All scripts support:

| Variable | Default | Description |
|----------|---------|-------------|
| `NAMESPACE_PREFIX` | `agentic-user` | Namespace name prefix |

Admin setup also supports:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAW_OPERATOR_HOME` | `../../claw-operator` | Path to claw-operator repo |
| `REGISTRY` | `quay.io/bsutter` | Container image registry |
| `TAG` | `latest` | Container image tag |
