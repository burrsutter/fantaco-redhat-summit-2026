---
name: reset-user
description: Surgically reset a single user's OpenClaw instance without disrupting the fleet
argument-hint: "<user-number [cluster-id] | route-url>"
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Single-User Reset

Surgically reset one user's OpenClaw instance (state, backends, route, config, persona, skills) without disrupting other users or wiping fleet-wide Prometheus metrics, Grafana dashboards, MLflow traces, or Langfuse traces.

## Step 0: Parse input and resolve target

Parse `$ARGUMENTS` to determine the user number, namespace, cluster, and KUBECONFIG.

**Input formats:**

| Input | Action |
|-------|--------|
| `user23 ql7rg` or `23 w6hwm` | User number + cluster ID → unambiguous |
| `user23` or `user1` | Extract number → namespace `agentic-user23` (may need disambiguation) |
| `23` or `1` (bare number) | Derive namespace `agentic-user1` (may need disambiguation) |
| `https://claw-7da80-a89482.yougetaclaw.com/` | Extract suffix `a89482`, run `lookup-route.sh` |
| `claw-7da80-a89482.yougetaclaw.com` | Same as above |
| Empty / missing | Ask user with AskUserQuestion |

### For URL/hostname inputs

URL inputs are always unambiguous — each route hostname is unique across all clusters.

Extract the route suffix (last 6-char hex segment before the domain) and run:

```bash
cd /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw
./lookup-route.sh <suffix-or-full-url>
```

Parse the output to get `Cluster`, `Namespace`, and `KUBECONFIG` values. If no match is found, report the error and stop.

### For user-number inputs

**Important:** Namespace names repeat across clusters. Both `ql7rg` and `w6hwm` have `agentic-user1` through `agentic-user50`. A bare user number like `1` is ambiguous.

1. Derive namespace: `agentic-user<NUMBER>`
2. Check if `$ARGUMENTS` also contains a cluster ID (second word). If so, use it directly.
3. If no cluster ID given, scan **all** clusters from both `sites/primary.clusters.csv` and `sites/backup.clusters.csv` to find which clusters have this namespace:

```bash
cd /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw
MATCHES=()
for CSV in sites/primary.clusters.csv sites/backup.clusters.csv; do
  [[ -f "$CSV" ]] || continue
  while IFS=, read -r cluster_id kubeconfig_path; do
    [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$cluster_id" ]] && continue
    cluster_id=$(echo "$cluster_id" | xargs)
    kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
    if KUBECONFIG="$kubeconfig_path" oc get ns "agentic-user<NUMBER>" &>/dev/null; then
      MATCHES+=("$cluster_id $kubeconfig_path $CSV")
    fi
  done < "$CSV"
done
```

4. **If exactly 1 match** — use it.
5. **If 2+ matches** — use AskUserQuestion to ask the user which cluster to target. Present options like:
   - `ql7rg` (primary site, yougetaclaw.com)
   - `w6hwm` (primary site, yougetaclaw.com)
   - `pcpwx` (backup site, get-my-claw.com)
6. **If 0 matches** — report the error and stop.

**Set these variables for all subsequent steps:**

- `NS` — the namespace (e.g., `agentic-user23`)
- `USER_NUM` — the user number (e.g., `23`)
- `KUBECONFIG_PATH` — the kubeconfig file path
- `CLUSTER_ID` — the cluster short ID (must match the directory name in `.state/<id>/`)
- `SITE_NAME` — `primary` or `backup` (derived from which clusters.csv matched: `sites/primary.clusters.csv` → `primary`, `sites/backup.clusters.csv` → `backup`; for URL inputs, determine from the domain: `yougetaclaw.com` → `primary`, `get-my-claw.com` → `backup`)

**Verify connectivity:**

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc get ns "$NS" -o name
```

Report the resolved target to the user before proceeding:
> Resetting **agentic-user23** on cluster **ql7rg** (site: primary, KUBECONFIG: ~/.kube/config-cluster-ql7rg)

All subsequent `oc` commands in this skill MUST use `KUBECONFIG="$KUBECONFIG_PATH"` prefix. When calling helper scripts (`post-restart-repatch.sh`, `manage-heartbeat.sh`, `update-broker.sh`), also prefix with `KUBECONFIG="$KUBECONFIG_PATH"` so they target the correct cluster.

**Note:** This skill assumes the namespace has been previously set up by a full `audience-reset.sh` run. MCP endpoint CR patches and NetworkPolicies are already in place from the initial deployment and do not need to be re-applied for a reset.

## Step 1: Wipe user state

Delete sessions, caches, cron state, memory DBs, and old config files inside the gateway pod.

**Important:** Use `oc exec -i` with a heredoc (not `node -e "..."`) to avoid zsh escaping issues with `!==` operators:

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc exec -i deployment/instance -n "$NS" -c gateway -- node <<'WIPE_EOF'
  const { execSync } = require('child_process');
  const fs = require('fs');
  const path = require('path');
  const HOME = '/home/node/.openclaw';

  const dirsToRemove = [
    HOME + '/agents/default/sessions',
    HOME + '/agents/main/agent/codex-home/tmp',
    HOME + '/cron/runs',
    HOME + '/.cache',
    HOME + '/.local',
  ];

  const filesToRemove = [
    HOME + '/agents/main/agent/codex-home/installation_id',
    HOME + '/agents/main/agent/codex-home/.personality_migration',
    HOME + '/cron/jobs.json',
    HOME + '/cron/jobs.json.bak',
    HOME + '/cron/jobs-state.json',
    HOME + '/memory/default.sqlite',
    HOME + '/memory/default.sqlite-wal',
    HOME + '/memory/default.sqlite-shm',
    HOME + '/tasks/runs.sqlite',
    HOME + '/tasks/runs.sqlite-wal',
    HOME + '/tasks/runs.sqlite-shm',
    HOME + '/workspace/.openclaw/workspace-state.json',
    HOME + '/workspace/USER.md',
    HOME + '/workspace/HEARTBEAT.md',
    HOME + '/workspace/IDENTITY.md',
    HOME + '/workspace/SOUL.md',
    HOME + '/identity/device.json',
    HOME + '/openclaw.json',
    HOME + '/openclaw.json.last-good',
    HOME + '/update-check.json',
    HOME + '/logs/config-health.json',
  ];

  let removed = 0;

  for (const d of dirsToRemove) {
    try { execSync('rm -rf ' + JSON.stringify(d), { stdio: 'pipe' }); removed++; } catch (e) {}
  }
  for (const f of filesToRemove) {
    try { fs.unlinkSync(f); removed++; } catch (e) {}
  }

  const codexHome = HOME + '/agents/main/agent/codex-home';
  try {
    const entries = fs.readdirSync(codexHome);
    for (const e of entries) {
      if (/^(state_|logs_).*\\.sqlite/.test(e)) {
        fs.unlinkSync(path.join(codexHome, e));
        removed++;
      }
    }
  } catch (e) {}

  const skillsDir = HOME + '/workspace/skills';
  try {
    const entries = fs.readdirSync(skillsDir);
    for (const e of entries) {
      if (e !== 'platform') {
        execSync('rm -rf ' + JSON.stringify(path.join(skillsDir, e)), { stdio: 'pipe' });
        removed++;
      }
    }
  } catch (e) {}

  try { execSync('rm -rf /tmp/openclaw', { stdio: 'pipe' }); removed++; } catch (e) {}

  console.log('Removed ' + removed + ' items');
WIPE_EOF
```

Report result. If the exec fails because the pod isn't running, stop with an error.

## Step 2: Reset PostgreSQL databases and deploy FantaCo backends

Delete the PostgreSQL pods to wipe demo data (they use `emptyDir` volumes, so a pod delete resets to the init-script seed state):

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=postgresql-customer --wait=false 2>/dev/null || true
KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=postgresql-salesorder --wait=false 2>/dev/null || true
KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=postgresql-product --wait=false 2>/dev/null || true
```

Wait for the new PostgreSQL pods to be ready, then restart the Java apps so they re-initialize the database schema (JPA/Hibernate creates tables on connect):

```bash
for dep in postgresql-customer postgresql-salesorder postgresql-product; do
  KUBECONFIG="$KUBECONFIG_PATH" oc rollout status deployment/"$dep" -n "$NS" --timeout=60s 2>/dev/null || true
done

KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=fantaco-customer-main --wait=false 2>/dev/null || true
KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=fantaco-sales-order-main --wait=false 2>/dev/null || true
KUBECONFIG="$KUBECONFIG_PATH" oc delete pod -n "$NS" -l app=fantaco-product-main --wait=false 2>/dev/null || true

for dep in fantaco-customer-main fantaco-sales-order-main fantaco-product-main; do
  KUBECONFIG="$KUBECONFIG_PATH" oc rollout status deployment/"$dep" -n "$NS" --timeout=60s 2>/dev/null || true
done
```

Apply the Helm templates for customer, product, and sales-order backends (apps + MCP servers):

**Important:** Use absolute paths for Helm chart directories — relative paths like `../helm` are unreliable across different working directories.

```bash
HELM_DIR="/Users/bsutter/ai-projects/fantaco-redhat-summit-2026/helm"

# Customer app
helm template fantaco-app "$HELM_DIR/fantaco-app" -n "$NS" \
  -s templates/postgres-customer-deployment.yaml \
  -s templates/postgres-customer-service.yaml \
  -s templates/customer-configmap.yaml \
  -s templates/customer-secret.yaml \
  -s templates/customer-deployment.yaml \
  -s templates/customer-service.yaml \
  -s templates/customer-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -

# Customer MCP
helm template fantaco-mcp "$HELM_DIR/fantaco-mcp" -n "$NS" \
  -s templates/customer-deployment.yaml \
  -s templates/customer-service.yaml \
  -s templates/customer-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -

# Sales-order app
helm template fantaco-app "$HELM_DIR/fantaco-app" -n "$NS" \
  -s templates/postgres-salesorder-deployment.yaml \
  -s templates/postgres-salesorder-service.yaml \
  -s templates/salesorder-configmap.yaml \
  -s templates/salesorder-secret.yaml \
  -s templates/salesorder-deployment.yaml \
  -s templates/salesorder-service.yaml \
  -s templates/salesorder-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -

# Sales-order MCP
helm template fantaco-mcp "$HELM_DIR/fantaco-mcp" -n "$NS" \
  -s templates/salesorder-deployment.yaml \
  -s templates/salesorder-service.yaml \
  -s templates/salesorder-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -

# Product app
helm template fantaco-app "$HELM_DIR/fantaco-app" -n "$NS" \
  -s templates/postgres-product-deployment.yaml \
  -s templates/postgres-product-service.yaml \
  -s templates/product-configmap.yaml \
  -s templates/product-secret.yaml \
  -s templates/product-deployment.yaml \
  -s templates/product-service.yaml \
  -s templates/product-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -

# Product MCP
helm template fantaco-mcp "$HELM_DIR/fantaco-mcp" -n "$NS" \
  -s templates/product-deployment.yaml \
  -s templates/product-service.yaml \
  -s templates/product-route.yaml \
  | KUBECONFIG="$KUBECONFIG_PATH" oc apply -n "$NS" -f -
```

If Langfuse OTEL auth state exists, inject it into MCP deployments:

```bash
LANGFUSE_STATE="/Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw/.state/${CLUSTER_ID}/langfuse.env"
if [[ -f "$LANGFUSE_STATE" ]]; then
  source "$LANGFUSE_STATE"
  LF_AUTH="Basic $(echo -n "${INIT_PUBLIC_KEY}:${INIT_SECRET_KEY}" | base64)"
  for MCP_DEP in mcp-customer mcp-product mcp-sales-order; do
    KUBECONFIG="$KUBECONFIG_PATH" oc set env deployment/"$MCP_DEP" -n "$NS" \
      OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=${LF_AUTH}" 2>/dev/null || true
  done
fi
```

## Step 3: Restart gateway and wait for rollout

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc rollout restart deployment/instance -n "$NS"
KUBECONFIG="$KUBECONFIG_PATH" oc rollout status deployment/instance -n "$NS" --timeout=120s
```

If rollout fails, report the error but continue with remaining steps.

## Step 4: Wait for gateway to be exec-ready

Poll until the gateway pod responds to `oc exec`:

```bash
for attempt in $(seq 1 30); do
  if KUBECONFIG="$KUBECONFIG_PATH" oc exec deployment/instance -n "$NS" -c gateway -- node -e "console.log('ready')" &>/dev/null; then
    echo "Gateway is exec-ready"
    break
  fi
  sleep 2
done
```

If not ready after 60 seconds, report a warning but try to continue.

## Step 5: Install plugins and repatch config

### 5a. Copy langfuse-tracer plugin files (if applicable)

Source `.env` to get Langfuse credentials, then copy plugin files only if credentials are available:

```bash
source /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/.env
PLUGINS_DIR="/Users/bsutter/ai-projects/fantaco-redhat-summit-2026/claw_plugins"
if [[ -n "${LANGFUSE_PUBLIC_KEY:-}" && -n "${LANGFUSE_SECRET_KEY:-}" && -d "$PLUGINS_DIR/langfuse-tracer" ]]; then
  POD=$(KUBECONFIG="$KUBECONFIG_PATH" oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
    | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)
  if [[ -n "$POD" ]]; then
    KUBECONFIG="$KUBECONFIG_PATH" oc exec "$POD" -n "$NS" -c gateway -- mkdir -p /home/node/.openclaw/extensions/langfuse-tracer 2>/dev/null
    for PFILE in index.js openclaw.plugin.json; do
      KUBECONFIG="$KUBECONFIG_PATH" oc cp "$PLUGINS_DIR/langfuse-tracer/$PFILE" "$POD:/home/node/.openclaw/extensions/langfuse-tracer/$PFILE" -n "$NS" -c gateway 2>/dev/null || true
    done
  fi
fi
```

### 5b. Install prometheus plugin

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc exec deployment/instance -n "$NS" -c gateway -- \
  node /app/dist/index.js plugins install @openclaw/diagnostics-prometheus@2026.5.26 2>&1 \
  | grep -E "^(Installed|Already|Error)" || true
```

### 5c. Install diagnostics-otel plugin (if MLflow is deployed)

```bash
MLFLOW_ROUTE=$(KUBECONFIG="$KUBECONFIG_PATH" oc get route mlflow -n mlflow -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$MLFLOW_ROUTE" ]]; then
  KUBECONFIG="$KUBECONFIG_PATH" oc exec deployment/instance -n "$NS" -c gateway -- \
    node /app/dist/index.js plugins install @openclaw/diagnostics-otel@2026.5.26 2>&1 \
    | grep -E "^(Installed|Already|Error)" || true
fi
```

### 5d. Run post-restart-repatch.sh

The `SITE_NAME` was already determined in Step 0. Export `KUBECONFIG` so the script targets the correct cluster:

```bash
cd /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw
KUBECONFIG="$KUBECONFIG_PATH" ./post-restart-repatch.sh --site "$SITE_NAME" "$NS"
```

## Step 6: Inject persona and skills

Get the running gateway pod name:

```bash
POD=$(KUBECONFIG="$KUBECONFIG_PATH" oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
  | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)
```

If no pod found, report error and stop.

### 6a. Pre-fill IDENTITY.md

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc cp \
  /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw/workspace-templates/IDENTITY.md \
  "$POD:/home/node/.openclaw/workspace/IDENTITY.md" -n "$NS" -c gateway
```

### 6b. Pre-fill SOUL.md

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc cp \
  /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw/workspace-templates/SOUL.md \
  "$POD:/home/node/.openclaw/workspace/SOUL.md" -n "$NS" -c gateway
```

### 6c. Append AGENTS.md

```bash
AGENTS_APPEND=$(cat /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw/workspace-templates/AGENTS.md.append)
KUBECONFIG="$KUBECONFIG_PATH" oc exec "$POD" -n "$NS" -c gateway -- node -e "
  const fs = require('fs');
  const f = '/home/node/.openclaw/workspace/AGENTS.md';
  let content = fs.readFileSync(f, 'utf8');
  if (!content.includes('Enterprise assistant')) {
    content += $(printf '%s' "$AGENTS_APPEND" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))');
    fs.writeFileSync(f, content);
  }
"
```

### 6d. Replace TOOLS.md

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc cp \
  /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw/workspace-templates/TOOLS.md \
  "$POD:/home/node/.openclaw/workspace/TOOLS.md" -n "$NS" -c gateway
```

### 6e. Inject enterprise skills

```bash
SKILLS_DIR="/Users/bsutter/ai-projects/fantaco-redhat-summit-2026/claw_skills"
SKILLS_DEST="/home/node/.openclaw/workspace/skills"

for SKILL in quote-builder; do
  if [[ -f "$SKILLS_DIR/$SKILL/SKILL.md" ]]; then
    KUBECONFIG="$KUBECONFIG_PATH" oc exec "$POD" -n "$NS" -c gateway -- mkdir -p "${SKILLS_DEST}/${SKILL}" 2>/dev/null
    KUBECONFIG="$KUBECONFIG_PATH" oc cp "$SKILLS_DIR/$SKILL/SKILL.md" "$POD:${SKILLS_DEST}/${SKILL}/SKILL.md" -n "$NS" -c gateway
    echo "Injected skill: $SKILL"
  fi
done
```

## Step 7: Disable heartbeat

Export `KUBECONFIG` so manage-heartbeat.sh targets the correct cluster:

```bash
cd /Users/bsutter/ai-projects/fantaco-redhat-summit-2026/clawoperator-openclaw
KUBECONFIG="$KUBECONFIG_PATH" ./manage-heartbeat.sh disable "$USER_NUM"
```

## Step 8: Wipe leftover heartbeat sessions

Clear any sessions created between the gateway restart (Step 3) and heartbeat disable (Step 7):

```bash
KUBECONFIG="$KUBECONFIG_PATH" oc exec deployment/instance -n "$NS" -c gateway -- node -e "
  const fs = require('fs');
  const sessDir = '/home/node/.openclaw/agents/default/sessions';
  try {
    const entries = fs.readdirSync(sessDir);
    let removed = 0;
    for (const e of entries) {
      try { fs.rmSync(sessDir + '/' + e, { recursive: true, force: true }); removed++; } catch {}
    }
    console.log('Cleared ' + removed + ' leftover sessions');
  } catch (e) {
    console.log('No sessions directory (clean state)');
  }
" 2>/dev/null || true
```

## Step 9: Report summary

Print a summary with:
- Namespace and cluster
- Existing audience URL (unchanged): `https://<current audience route host>`
- Status of each step (success/warning/failure)
- Reminder that the route, broker, and other users were NOT affected

**Deliberately skipped** (not needed for single-user reset):
- Route deletion/creation (user keeps their existing URL and broker assignment)
- Broker update (no route change means no broker sync needed)
- Prometheus pod reset
- Grafana dashboard reset
- MLflow trace deletion
- Langfuse trace deletion
