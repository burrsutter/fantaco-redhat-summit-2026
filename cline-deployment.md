# Cline Extension Deployment for DevSpaces

Step-by-step guide for adding the Cline VS Code extension (`saoudrizwan.claude-dev`) to Red Hat DevSpaces workspaces, pre-configured to use a LiteLLM proxy.

## Prerequisites

- `oc` CLI logged into the target OpenShift cluster as admin
- GitLab instance running on the cluster with a devfiles repo (group `rhdh`, project `devfiles`)
- GitLab API token (stored in `gitlab-token` secret in `parasol-insurance-dev` namespace)
- Dev user namespaces (`dev<N>-devspaces`) already created
- LiteLLM proxy URL and API key

## Architecture Overview

Three pieces work together:

1. **Kubernetes Secret** (`cline-config`) — holds the JSON settings file, auto-mounted into workspace pods at `/home/user/.cline-config/` via `controller.devfile.io` annotations
2. **Devfile `install-cline` command** — downloads the Cline VSIX from public OpenVSX and extracts it into the che-code extensions directory at pod startup
3. **Devfile `configure-cline` command** — copies the mounted secret into `~/.cline/data/globalState.json` so Cline starts pre-configured

```
┌─────────────────────────────────────────────────────────────┐
│  DevWorkspace Pod                                           │
│                                                             │
│  Secret mount (read-only)          Extension dir            │
│  /home/user/.cline-config/         /checode/remote/         │
│    └── cline-settings.json           extensions/            │
│            │                           └── saoudrizwan.     │
│            │ postStart: configure-cline      claude-dev-    │
│            ▼                                 3.81.0-        │
│  /home/user/.cline/data/                     universal/     │
│    └── globalState.json                         ▲           │
│                                                 │           │
│                              postStart: install-cline       │
│                              (downloads VSIX from OpenVSX)  │
└─────────────────────────────────────────────────────────────┘
```

## Step 1: Deploy the `cline-config` Secret

The script `scripts/deploy-cline-config.sh` creates a Secret in each dev namespace. The Secret uses `controller.devfile.io` annotations so the DevWorkspace operator automatically mounts it into pods.

### What to customize for a new cluster

Edit `scripts/deploy-cline-config.sh` and update these values in the `stringData` section:

| Field | Description | Example |
|-------|-------------|---------|
| `openAiBaseUrl` | Your LiteLLM proxy URL | `https://litellm-prod.apps.maas.redhatworkshops.io/v1` |
| `openAiApiKey` | LiteLLM API key | `sk-XxmN30_Da-H67Cnmw5zMFg` |
| `openAiModelId` | Model to use | `claude-opus-4-6` |

### The Secret manifest

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cline-config
  labels:
    controller.devfile.io/mount-to-devworkspace: "true"
  annotations:
    controller.devfile.io/mount-as: subpath        # mount each key as a file
    controller.devfile.io/mount-path: /home/user/.cline-config
    controller.devfile.io/mount-to-devworkspace: "true"
    controller.devfile.io/watch-secret: "true"     # hot-reload on changes
type: Opaque
stringData:
  cline-settings.json: |
    {
      "apiProvider": "openai",
      "openAiBaseUrl": "https://litellm-prod.apps.maas.redhatworkshops.io/v1",
      "openAiApiKey": "sk-XxmN30_Da-H67Cnmw5zMFg",
      "openAiModelId": "claude-opus-4-6",
      "openAiCustomModelInfo": {
        "maxTokens": 16384,
        "contextWindow": 200000,
        "supportsImages": true,
        "supportsPromptCache": true
      }
    }
```

### Run the script

```bash
# Deploy to all namespaces (dev1-devspaces through dev20-devspaces)
./scripts/deploy-cline-config.sh

# Deploy to a single namespace for testing
START=17 END=17 ./scripts/deploy-cline-config.sh

# Deploy to a custom range
START=1 END=5 ./scripts/deploy-cline-config.sh
```

The script is idempotent (uses `oc apply`) and skips namespaces that don't exist.

### Verify

```bash
oc get secret cline-config -n dev17-devspaces -o jsonpath='{.data.cline-settings\.json}' | base64 -d
```

## Step 2: Update the Devfile in GitLab

The devfile lives at `rhdh/devfiles/devfile.yaml` in the cluster's GitLab instance. Two new commands need to be added to the `commands` section, and the `postStart` events need to be updated.

### Command: `install-cline`

Downloads the Cline v3.81.0 VSIX from public OpenVSX and extracts it into the che-code extensions directory. This is needed because Cline is not published on the cluster's private OpenVSX registry.

```yaml
- id: install-cline
  exec:
    label: "Install Cline extension"
    component: development-tooling
    commandLine: |
      VSIX_URL="https://open-vsx.org/api/saoudrizwan/claude-dev/3.81.0/file/saoudrizwan.claude-dev-3.81.0.vsix"
      curl -fsSL "$VSIX_URL" -o /tmp/cline.vsix
      # OpenVSX sometimes serves gzip-wrapped files
      file /tmp/cline.vsix | grep -q gzip && mv /tmp/cline.vsix /tmp/cline.vsix.gz && gunzip /tmp/cline.vsix.gz || true
      # Extract into che-code extensions directory
      mkdir -p /checode/remote/extensions/saoudrizwan.claude-dev-3.81.0-universal
      cd /checode/remote/extensions/saoudrizwan.claude-dev-3.81.0-universal
      unzip -qo /tmp/cline.vsix "extension/*" -d .
      mv extension/* . && rmdir extension
      rm -f /tmp/cline.vsix
    group:
      kind: build
```

**To update the version**: change `3.81.0` in the URL, the directory name, and verify the VSIX file name at `https://open-vsx.org/extension/saoudrizwan/claude-dev`.

### Command: `configure-cline`

Copies the mounted secret into Cline's data directory. Only seeds the config if the user hasn't already configured Cline (preserves user changes across restarts).

```yaml
- id: configure-cline
  exec:
    label: "Configure Cline settings"
    component: development-tooling
    commandLine: |
      mkdir -p /home/user/.cline/data
      if [ ! -f /home/user/.cline/data/globalState.json ]; then
        cp /home/user/.cline-config/cline-settings.json /home/user/.cline/data/globalState.json
      fi
    group:
      kind: build
```

### Updated postStart events

Both commands must run **before** `configure-settings`. The `install-cline` command must come first since it sets up the extension files that Cline needs.

```yaml
events:
  postStart:
    - install-cline          # download and extract VSIX
    - configure-cline        # seed API config from secret
    - init-podman-socket
    - init-continue
    - init-claude
    - configure-settings
```

### How to push the devfile update

Option A — Via GitLab API:

```bash
# Get GitLab token
GITLAB_TOKEN=$(oc get secret gitlab-token -n parasol-insurance-dev \
  -o jsonpath='{.data.token}' | base64 -d)

# Cluster domain
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster \
  -o jsonpath='{.spec.domain}')

GL_URL="https://gitlab-gitlab.apps.${CLUSTER_DOMAIN}"

# Find project ID for rhdh/devfiles
PROJECT_ID=$(curl -fsSL -k \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GL_URL}/api/v4/projects?search=devfiles" | \
  python3 -c "import sys,json; print([p['id'] for p in json.load(sys.stdin) if p['path_with_namespace']=='rhdh/devfiles'][0])")

echo "Project ID: ${PROJECT_ID}"

# Update the file (PUT for existing files)
curl -fsSL -k -X PUT \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  "${GL_URL}/api/v4/projects/${PROJECT_ID}/repository/files/devfile.yaml" \
  -d "$(python3 -c "
import json
content = open('path/to/your/devfile.yaml').read()
print(json.dumps({
    'branch': 'main',
    'content': content,
    'commit_message': 'add Cline extension install and config to postStart'
}))
")"
```

Option B — Clone the repo and push:

```bash
CLUSTER_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
git clone https://gitlab-gitlab.apps.${CLUSTER_DOMAIN}/rhdh/devfiles.git
cd devfiles
# edit devfile.yaml
git add devfile.yaml
git commit -m "add Cline extension install and config to postStart"
git push origin main
```

## Step 3: Verify the Deployment

### Test on a single workspace first

1. Deploy the secret to one namespace:
   ```bash
   START=17 END=17 ./scripts/deploy-cline-config.sh
   ```

2. Update the devfile in GitLab (Step 2 above)

3. Restart the workspace — stop and start via the DevSpaces dashboard, or:
   ```bash
   # Find the DevWorkspace
   oc get devworkspace -n dev17-devspaces

   # Stop it
   oc patch devworkspace <name> -n dev17-devspaces \
     --type merge -p '{"spec":{"started":false}}'

   # Wait for it to stop, then start
   oc patch devworkspace <name> -n dev17-devspaces \
     --type merge -p '{"spec":{"started":true}}'
   ```

4. Open the workspace IDE and check:
   - Cline appears in the Extensions sidebar (look for the Cline icon)
   - Click the Cline icon — the API provider should show "OpenAI Compatible" with the LiteLLM URL pre-filled
   - Send a test message like "Hello, what model are you?" to confirm connectivity

### Troubleshooting

**Cline not showing in extensions sidebar:**
```bash
# Check if the extension was extracted
oc exec -n dev17-devspaces <pod> -- \
  ls /checode/remote/extensions/saoudrizwan.claude-dev-3.81.0-universal/

# Check postStart logs
oc logs -n dev17-devspaces <pod> -c development-tooling | grep -i cline
```

**Cline shows but not configured:**
```bash
# Check if the secret is mounted
oc exec -n dev17-devspaces <pod> -- \
  cat /home/user/.cline-config/cline-settings.json

# Check if globalState was seeded
oc exec -n dev17-devspaces <pod> -- \
  cat /home/user/.cline/data/globalState.json
```

**Config not picked up by extension (fallback):**

Cline v3.x may still use VS Code's globalState SQLite DB instead of the file-based `~/.cline/data/`. If the pre-seeded config doesn't appear in the UI:

1. Open the Cline sidebar manually
2. Configure the API provider through the UI (one-time per workspace)
3. Consider pre-populating the SQLite DB as an alternative — the DB is at `/checode/remote/data/User/globalStorage/state.vscdb`

## Full Devfile Reference

The complete devfile with all commands (Cline, Roo Code, Continue, Claude Code, Podman) is maintained in GitLab at:

```
https://gitlab-gitlab.apps.<CLUSTER_DOMAIN>/rhdh/devfiles/-/blob/main/devfile.yaml
```

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/deploy-cline-config.sh` | Deploys `cline-config` Secret to dev namespaces |
| GitLab: `rhdh/devfiles/devfile.yaml` | Devfile with `install-cline` and `configure-cline` commands |

## Related Secrets (same pattern)

The Cline config follows the same `controller.devfile.io` annotation pattern used by these other extension configs in the cluster:

| Secret name | Mount path | Configures |
|-------------|------------|------------|
| `cline-config` | `/home/user/.cline-config/` | Cline extension |
| `roo-config` | `/home/user/.roo-config/` | Roo Code extension |
| `continue-config` | `/home/user/.continue-config/` | Continue extension |
| `claude-config` | `/home/user/.claude-config/` | Claude Code CLI |
