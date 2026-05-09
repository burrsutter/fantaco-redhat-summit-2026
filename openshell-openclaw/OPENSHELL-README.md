

https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/README.md#install-on-openshift

## Prerequisites

Install Rust toolchain (cargo):

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

Install z3 (macOS):

```
brew install z3
```

## Clone the Repo

```
git clone https://github.com/NVIDIA/OpenShell
cd OpenShell
```

## Build the CLI

```
export C_INCLUDE_PATH="$(brew --prefix z3)/include"
export LIBRARY_PATH="$(brew --prefix z3)/lib"
cargo install --path crates/openshell-cli
```

## Install OpenShell on OpenShift

Switch to your target namespace first, then run the scripts in order.
All scripts auto-detect the namespace from `oc project -q`.

```
oc project <namespace>
```

## Launch OpenClaw

**Step 0** — Cluster-admin setup (run once per namespace by a cluster-admin):

```
./0-cluster-admin-setup.sh <namespace>
```

Optional env vars: `OPENSHELL_HOME` (default: `../../OpenShell`).

This script performs operations that require cluster-admin privileges:

| Resource | Scope | What it does |
|----------|-------|--------------|
| SCC grant | Per-namespace | Grants `privileged` SCC to the `default` SA in the target namespace |
| Role `openshell-sandbox` | Per-namespace | Allows the `openshell` SA to manage Sandbox CRs and watch events |
| RoleBinding `openshell-sandbox` | Per-namespace | Binds the Role to the `openshell` SA |
| CRD `sandboxes.agents.x-k8s.io` | Cluster-wide | Installs the Sandbox CRD, controller namespace, SA, and StatefulSet (idempotent) |
| ClusterRole `openshell-<ns>-node-reader` | Cluster-wide | Grants node read access; name includes namespace to avoid collisions |
| ClusterRoleBinding `openshell-<ns>-node-reader` | Cluster-wide | Binds the ClusterRole to the `openshell` SA in the target namespace |

The namespace user (`user1`) **cannot** create Roles, RoleBindings, ClusterRoles, ClusterRoleBindings, CRDs, or grant SCCs. All six operations above must be performed by a cluster-admin before Step 1.

**Step 1** — Install OpenShell (Helm chart — no cluster-admin required):

```
./1-install-openshell.sh
```

Optional env vars: `OPENSHELL_HOME` (default: `../../OpenShell`).

**Step 2** — Port-forward the gateway (run in a separate terminal, keep running):

```
export LLM_PROVIDER=anthropic  # or openai, vllm
export ANTHROPIC_API_KEY=sk-ant-xxx  # or OPENAI_API_KEY / VLLM_API_KEY
./2-port-forward-openshell.sh
```

Registers the gateway with the CLI and creates the LLM provider.
Optional env vars: `GATEWAY_PORT` (default: `8081`), `GATEWAY_NAME` (default: `local`), `LLM_PROVIDER` (default: `anthropic`).

See [Provider Selection](#provider-selection) below for details on each provider.

**Step 3** — Create the sandbox, apply policy, label the pod:

```
./3-deploy-openclaw-sandbox.sh
```

**Step 4** — Update OpenClaw, inject API key, copy config, start gateway (requires the provider API key and `$TELEGRAM_BOT_TOKEN`):

```
export LLM_PROVIDER=anthropic  # must match Step 2
export ANTHROPIC_API_KEY=sk-ant-xxx  # or OPENAI_API_KEY / VLLM_API_KEY
export TELEGRAM_BOT_TOKEN=<token>
./4-configure-openclaw.sh
```

Or pass the bot token as a flag: `./4-configure-openclaw.sh --bot-token <token>`

The script automatically updates OpenClaw from the older image version to latest (~90s on first run), injects the provider API key, fills the `openclaw.json.template` with the provider config, and starts the gateway **inside the sandbox network namespace** via `openshell sandbox exec`. This ensures all outbound traffic goes through the policy-enforcing proxy.

For interactive setup instead: `./4-configure-openclaw.sh --interactive`

**Step 5** — Port forward OpenClaw UI (run in a separate terminal):

```
./5-port-forward-openclaw.sh
```

**Step 6** — Open the UI in your browser with the auth token:

```
./6-open-openclaw.sh
```

To stop and restart the gateway later:

```
POD=$(oc get pod -l app=openclaw -n "$(oc project -q)" -o jsonpath='{.items[0].metadata.name}')
oc exec $POD -n "$(oc project -q)" -- openclaw gateway stop
./4-configure-openclaw.sh
```

## Approve Telegram Pairing

The first time you message the bot from Telegram, it will reply with a pairing code. Approve it:

```
oc exec $POD -n "$NS" -- openclaw pairing approve telegram YOUR_PAIRING_CODE
```

Or use the helper script:

```
./scripts/approve-telegram-pairing.sh YOUR_PAIRING_CODE
```

## Provider Selection

Set `LLM_PROVIDER` before running steps 2-4. All scripts source `provider-config.sh` to pick up the right variables.

| Provider | `LLM_PROVIDER` | API Key Env Var | Model | Notes |
|----------|----------------|-----------------|-------|-------|
| Anthropic (default) | `anthropic` | `ANTHROPIC_API_KEY` | `anthropic/claude-sonnet-4-6` | Built-in Anthropic API endpoint |
| OpenAI | `openai` | `OPENAI_API_KEY` | `openai/gpt-5` | Built-in OpenAI API endpoint |
| vLLM (self-hosted) | `vllm` | `VLLM_API_KEY` | `openai/${VLLM_MODEL}` | OpenAI-compatible API via LiteLLM |

**vLLM additional env vars:**
- `VLLM_MODEL` — model name (default: `qwen3-14b`)
- `VLLM_BASE_URL` — API base URL (default: `https://litellm-prod.apps.maas.redhatworkshops.io/v1`)

**Example — switching to vLLM:**

```
export LLM_PROVIDER=vllm
export VLLM_API_KEY=<key>
export VLLM_MODEL=qwen3-14b
export VLLM_BASE_URL=https://litellm-prod.apps.maas.redhatworkshops.io/v1
./2-port-forward-openshell.sh   # creates the vllm provider
./3-deploy-openclaw-sandbox.sh  # deploys with --provider vllm
./4-configure-openclaw.sh       # configures with openai plugin + custom baseUrl
```

## Sandbox Security Policy

`openclaw-policy.yaml` is the OpenShell sandbox policy applied in step 3. It controls what the sandboxed agent can do:

- **`filesystem_policy`** — read-only vs read-write paths
- **`process`** — run-as user/group
- **`network_policies`** — allowlisted hosts, ports, per-binary rules, and L7 HTTP method restrictions

The `network_policies` section is enforced by the OpenShell proxy inside the sandbox's isolated network namespace. It is default-deny — only endpoints listed in the policy are reachable.

See [demo-sandbox-security.md](demo-sandbox-security.md) for the security demo walkthrough.

## Useful Commands

```
openshell status                        # Gateway health
openshell sandbox list                  # List sandboxes
openshell sandbox get <name>            # Sandbox details
openshell logs <name> --tail            # Live sandbox logs
openshell policy list <name>            # Policy status
openshell provider list                 # Providers
```

## Helm Chart Patches (reapply after rebasing OpenShell main)

Upstream OpenShell hardcodes `openshell` as the namespace and uses
namespace-unaware names for cluster-scoped resources. These changes make the
chart auto-detect from the Helm release namespace and allow multiple installs
on the same cluster.

**`deploy/helm/openshell/values.yaml`** — default both to empty so the
templates fall through to `.Release.Namespace`:

```yaml
# was: sandboxNamespace: openshell
sandboxNamespace: ""

# was: grpcEndpoint: "https://openshell.openshell.svc.cluster.local:8080"
grpcEndpoint: ""
```

**`deploy/helm/openshell/templates/statefulset.yaml`** — two changes:

1. Sandbox namespace (line ~66): add `default .Release.Namespace`

```yaml
# was:  value: {{ .Values.server.sandboxNamespace | quote }}
value: {{ .Values.server.sandboxNamespace | default .Release.Namespace | quote }}
```

2. gRPC endpoint (line ~79-83): auto-construct the URL when empty

```yaml
# was:  value: {{ if .Values.server.disableTls }}{{ ... }}{{ end }}
# replace with:
            - name: OPENSHELL_GRPC_ENDPOINT
              {{- if .Values.server.grpcEndpoint }}
              value: {{ if .Values.server.disableTls }}{{ .Values.server.grpcEndpoint | replace "https://" "http://" | quote }}{{ else }}{{ .Values.server.grpcEndpoint | quote }}{{ end }}
              {{- else }}
              value: {{ printf "%s://%s.%s.svc.cluster.local:%s" (ternary "http" "https" .Values.server.disableTls) (include "openshell.fullname" .) .Release.Namespace (toString .Values.service.port) | quote }}
              {{- end }}
```

**`deploy/helm/openshell/templates/networkpolicy.yaml`** — add `default .Release.Namespace` (line ~14):

```yaml
# was:  namespace: {{ .Values.server.sandboxNamespace }}
namespace: {{ .Values.server.sandboxNamespace | default .Release.Namespace }}
```

**`deploy/helm/openshell/templates/clusterrole.yaml`** — include namespace in name to avoid collisions (line ~7):

```yaml
# was:  name: {{ include "openshell.fullname" . }}-node-reader
name: {{ include "openshell.fullname" . }}-{{ .Release.Namespace }}-node-reader
```

**`deploy/helm/openshell/templates/clusterrolebinding.yaml`** — same change for both `metadata.name` and `roleRef.name` (lines ~7, ~13):

```yaml
# was:  name: {{ include "openshell.fullname" . }}-node-reader
name: {{ include "openshell.fullname" . }}-{{ .Release.Namespace }}-node-reader
```

## Reset / Re-run

To tear down all student-user resources and start fresh (preserves cluster-admin setup):

```
./clean-namespace.sh
```

Or clean specific namespaces:

```
./clean-namespace.sh agentic-user1,agentic-user2
```

Then re-run from Step 1.

## Cleanup

To tear down and start over:

```
openshell sandbox list
openshell sandbox delete <sandbox-name>
```
