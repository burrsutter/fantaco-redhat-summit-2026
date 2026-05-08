

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

**Step 1** — Install OpenShell (SCC, Helm chart, CRD):

```
./1-install-openshell.sh
```

Optional env vars: `OPENSHELL_HOME` (default: `../OpenShell`).

**Step 2** — Port-forward the gateway (run in a separate terminal, keep running):

```
export OPENAI_API_KEY=sk-xxx
./2-port-forward-openshell.sh
```

Registers the gateway with the CLI and creates the OpenAI provider.
Optional env vars: `GATEWAY_PORT` (default: `8081`), `GATEWAY_NAME` (default: `local`).

**Step 3** — Create the sandbox, apply policy, label the pod:

```
./3-deploy-openclaw-sandbox.sh
```

**Step 4** — Update OpenClaw, inject API key, copy config, start gateway (requires `$OPENAI_API_KEY`):

```
./4-configure-openclaw.sh
```

The script automatically updates OpenClaw from the older image version to latest (~90s on first run), injects the OpenAI API key, copies the pre-configured `openclaw.json`, and starts the gateway.

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

## Cleanup

To tear down and start over:

```
openshell sandbox list
openshell sandbox delete <sandbox-name>
```
