

Upstream: https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/README.md#install-on-openshift

## OpenShell Fork

We use a fork of OpenShell with multi-tenant RBAC patches for OpenShift:

**Fork:** https://github.com/burrsutter/OpenShell
**Upstream:** https://github.com/NVIDIA/OpenShell

The fork adds:
- `clusterRole.create` flag — lets namespace-scoped users install with `--set clusterRole.create=false` when a cluster-admin pre-creates RBAC
- Namespaced ClusterRole/ClusterRoleBinding names (`openshell-<namespace>-node-reader`) — prevents collisions across tenants
- Conditional guards on Role/RoleBinding templates

The deploy scripts (`0-cluster-admin-setup.sh`, `1-install-openshell.sh`) auto-clone the fork if `../../OpenShell` doesn't exist. Override with `OPENSHELL_REPO` to point elsewhere.

**Syncing with upstream:**

```
cd OpenShell
git fetch upstream
git merge upstream/main
# Resolve any conflicts in deploy/helm/openshell/ templates
git push origin main
```

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
git clone https://github.com/burrsutter/OpenShell
cd OpenShell
```

## Build the CLI

The CLI version must match the server image version. Rebuild after pulling updates.

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

Optional env vars: `OPENSHELL_HOME` (default: `../../OpenShell`, auto-cloned from fork if missing), `OPENSHELL_REPO` (default: `https://github.com/burrsutter/OpenShell`).

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

**Step 1** — Install OpenShell, port-forward gateway, register, and create provider:

```
export LLM_PROVIDER=anthropic  # or openai, vllm
export ANTHROPIC_API_KEY=sk-ant-xxx  # or OPENAI_API_KEY / VLLM_API_KEY
./1-install-openshell.sh
```

Installs the Helm chart, waits for the pod, starts a background port-forward, registers the gateway with the CLI, and creates the LLM provider. The port-forward runs in the background — no separate terminal needed.

Optional env vars: `OPENSHELL_HOME` (default: `../../OpenShell`, auto-cloned from fork if missing), `OPENSHELL_REPO` (default: `https://github.com/burrsutter/OpenShell`), `GATEWAY_PORT` (default: `8081`), `GATEWAY_NAME` (default: `local`), `LLM_PROVIDER` (default: `anthropic`).

See [Provider Selection](#provider-selection) below for details on each provider.

**Step 2** — Verify OpenShell health (optional):

```
./2-openshell-status.sh
```

Checks the port-forward, gateway pod, CLI registration, gateway connectivity, and provider configuration.

**Step 3** — Create the sandbox, apply policy, label the pod:

```
./3-deploy-openclaw-sandbox.sh
```

**Step 4** — Update OpenClaw, inject API key, copy config, start gateway, and expose the UI. The script reads `STUDENT_OPENCLAW_PASSWORD`, `TELEGRAM_BOT_TOKEN`, and provider API keys from `../.env` automatically. You can also export them or pass the bot token as a flag:

```
./4-configure-openclaw.sh
```

Or override via env vars / flags:

```
export LLM_PROVIDER=anthropic  # must match Step 1
export ANTHROPIC_API_KEY=sk-ant-xxx  # or OPENAI_API_KEY / VLLM_API_KEY
export TELEGRAM_BOT_TOKEN=<token>
./4-configure-openclaw.sh --bot-token <token>
```

The script automatically updates OpenClaw from the older image version to latest (~90s on first run), injects the provider API key, fills the `openclaw.json.template` with the provider config, starts the gateway **inside the sandbox network namespace** via `openshell sandbox exec`, and exposes the UI via an OpenShift Route. This ensures all outbound traffic goes through the policy-enforcing proxy. No port-forward needed — the UI is accessible via the Route URL from any browser.

**Proxy env vars:** The gateway starts with `HTTP_PROXY=http://10.200.0.1:3128`, `HTTPS_PROXY=http://10.200.0.1:3128`, and `OPENCLAW_PROXY_ACTIVE=1`. This routes OpenClaw's Undici fetch requests through the sandbox proxy at `10.200.0.1:3128`, ensuring policy enforcement on all outbound HTTP(S) traffic. Without these, OpenClaw's `image` and `web_fetch` tools bypass the proxy and get `ECONNREFUSED`.

**DNS pinning:** OpenClaw's `web_fetch` tool resolves DNS locally via `getaddrinfo` rather than delegating to the proxy. DNS entries must be pinned inside the **sandbox's** `/etc/hosts` (not the pod's), because the gateway runs inside the sandbox network namespace. Each policy-add script (e.g. `nasa-policy-add.sh`, `reddit-policy-add.sh`) handles DNS pinning automatically via `openshell sandbox exec` when adding endpoints.

**vLLM inline model registration:** When using `LLM_PROVIDER=vllm`, Step 4 registers the custom model as an inline provider in `openclaw.json` under `models.providers.openai`. The OpenAI plugin only recognizes official OpenAI models by default — without this registration, the gateway returns `FailoverError: Unknown model: openai/<model>`. The inline provider config specifies the `baseUrl` (LiteLLM endpoint) and model definition so the plugin knows where to route requests.

**Authentication:** The gateway uses password auth mode (`gateway.auth.mode: "password"`). The password is set from the `STUDENT_OPENCLAW_PASSWORD` variable in `.env`. Students open the Route URL and enter this password in the UI login field — no tokens or URL hashes needed.

**Device pairing** is disabled via `dangerouslyDisableDeviceAuth: true` in the config template, so students can connect directly through the Route without needing to pair their browser. This is a "break glass" config flag — do not use in production.

For interactive setup instead: `./4-configure-openclaw.sh --interactive`

**Step 5** — Verify OpenClaw health (optional):

```
./5-openclaw-status.sh
```

Checks the sandbox pod, gateway process, gateway logs, config, UI Route reachability, and sandbox registration.

**Step 6** — Open the UI in your browser:

```
./6-open-openclaw.sh
```

Opens the Route URL. Students enter the password (from `STUDENT_OPENCLAW_PASSWORD` in `.env`) when prompted.

To stop and restart the gateway later:

```
# Stop via sandbox exec (runs in the sandbox network namespace):
SANDBOX_NAME=$(openshell sandbox list | grep -v '^NAME' | awk '{print $1}' | head -1)
openshell sandbox exec -n "$SANDBOX_NAME" --no-tty -- openclaw gateway stop

# Restart (re-runs the full configure flow):
./4-configure-openclaw.sh
```

## Approve Telegram Pairing

The first time you message the bot from Telegram, it will reply with a pairing code. Approve it:

```
oc exec $POD -n "$NS" -- openclaw pairing approve telegram YOUR_PAIRING_CODE
```

Or use the helper script (from the repo root):

```
./scripts/approve-telegram-pairing.sh YOUR_PAIRING_CODE
```

## Provider Selection

Set `LLM_PROVIDER` before running steps 1-3. All scripts source `provider-config.sh` to pick up the right variables.

| Provider | `LLM_PROVIDER` | API Key Env Var | Model | Notes |
|----------|----------------|-----------------|-------|-------|
| Anthropic (default) | `anthropic` | `ANTHROPIC_API_KEY` | `anthropic/claude-sonnet-4-6` | Built-in Anthropic API endpoint |
| OpenAI | `openai` | `OPENAI_API_KEY` | `openai/gpt-5` | Built-in OpenAI API endpoint |
| vLLM (self-hosted) | `vllm` | `VLLM_API_KEY` | `openai/${VLLM_MODEL}` | OpenAI-compatible API via LiteLLM; requires inline model registration (auto-handled by Step 4) |

**vLLM additional env vars:**
- `VLLM_MODEL` — model name (default: `qwen3-14b`)
- `VLLM_BASE_URL` — API base URL (default: `https://litellm-prod.apps.maas.redhatworkshops.io/v1`)

**Example — switching to vLLM:**

```
export LLM_PROVIDER=vllm
export VLLM_API_KEY=<key>
export VLLM_MODEL=qwen3-14b
export VLLM_BASE_URL=https://litellm-prod.apps.maas.redhatworkshops.io/v1
./1-install-openshell.sh        # installs + creates the vllm provider
./2-openshell-status.sh         # verify gateway health (optional)
./3-deploy-openclaw-sandbox.sh  # deploys with --provider vllm
./4-configure-openclaw.sh       # configures with openai plugin + custom baseUrl
./5-openclaw-status.sh          # verify openclaw health (optional)
```

## Sandbox Security Policy

The default policy is checked in as `openclaw-policy.default.yaml`. Step 3 copies it to `openclaw-policy.yaml` (gitignored) on first run. The add/remove scripts modify the working copy — the default is never touched, so demo endpoints can't be accidentally committed.

`openclaw-policy.yaml` controls what the sandboxed agent can do:

- **`filesystem_policy`** — read-only vs read-write paths
- **`process`** — run-as user/group
- **`network_policies`** — allowlisted hosts, ports, per-binary rules, and L7 HTTP method restrictions

The `network_policies` section is enforced by the OpenShell proxy inside the sandbox's isolated network namespace. It is default-deny — only endpoints listed in the policy are reachable.

See [demo-sandbox-security.md](demo-sandbox-security.md) for the security demo walkthrough.

### Dynamic Policy Scripts

NASA and wttr.in are **not** in the default policy — they are added dynamically during demos to show live policy updates. Each add script inserts the endpoints into `openclaw-policy.yaml`, runs `openshell policy set` to apply immediately, and pins DNS inside the sandbox's `/etc/hosts` via `openshell sandbox exec`. The remove scripts reverse the policy change.

| Script | What it does |
|--------|-------------|
| `./nasa-policy-add.sh` | Adds `api.nasa.gov` + `apod.nasa.gov` to the policy and pins DNS in sandbox |
| `./nasa-policy-remove.sh` | Removes NASA endpoints from the policy |
| `./wttr-policy-add.sh` | Adds `wttr.in` to the policy and pins DNS in sandbox |
| `./wttr-policy-remove.sh` | Removes `wttr.in` from the policy |
| `./hackernews-policy-add.sh` | Adds Hacker News endpoints to the policy and pins DNS in sandbox |
| `./hackernews-policy-remove.sh` | Removes Hacker News endpoints from the policy |
| `./reddit-policy-add.sh` | Adds `www.reddit.com` to the policy and pins DNS in sandbox |
| `./reddit-policy-remove.sh` | Removes Reddit from the policy |

**Demo flow:** Start with the default policy (no NASA/wttr), show that requests are blocked, then run an add script to grant access live.

**Resetting the policy:** To restore the clean default after a demo, delete the working copy and re-run step 3 (or copy manually):

```
rm openclaw-policy.yaml
cp openclaw-policy.default.yaml openclaw-policy.yaml
```

## Useful Commands

```
openshell status                        # Gateway health
openshell sandbox list                  # List sandboxes
openshell sandbox get <name>            # Sandbox details
openshell logs <name> --tail            # Live sandbox logs
openshell policy list <name>            # Policy status
openshell provider list                 # Providers
./show-openclaw-info.sh                 # Show claw name + user from current namespace
./show-openclaw-info.sh <namespace>     # Explicit namespace
```

## Helm Chart (Fork Patches)

The RBAC patches live in the [burrsutter/OpenShell](https://github.com/burrsutter/OpenShell) fork.
No manual patching is needed — the deploy scripts use the fork automatically.

The upstream chart already handles namespace routing correctly:
- `sandboxNamespace` defaults to `.Release.Namespace` via `_helpers.tpl`
- `grpcEndpoint` auto-derives from service DNS + release namespace
- Gateway config uses a TOML ConfigMap (no more env vars)

The fork adds multi-tenant RBAC support on top:
- `clusterRole.create` flag in `values.yaml` (install script passes `--set clusterRole.create=false`)
- Conditional guards on `clusterrole.yaml`, `clusterrolebinding.yaml`, `role.yaml`, `rolebinding.yaml`
- Namespaced ClusterRole names (`openshell-<namespace>-node-reader`) to avoid collisions

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
