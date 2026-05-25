# Feedback for Claw-Operator Team

## Context

This document captures all the overrides, patches, and workarounds we apply on top of the default Claw CR to run the Red Hat Summit 2026 demo environment (20 user namespaces, FantaCo enterprise demo). These represent gaps between what the operator provides by default and what a production-like multi-user deployment needs.

**Cluster:** OpenShift on AWS (us-east-2), 10 worker nodes (m5a.4xlarge), 20 student namespaces
**Runtime version:** 2026.5.22
**Operator source:** github.com/codeready-toolchain/claw-operator

---

## 1. Config Re-seeding on Restart (Biggest Pain Point)

**Problem:** Every `oc rollout restart deployment/instance` causes the operator to re-seed `openclaw.json` from its ConfigMap, wiping all user-space configuration changes. This means every restart requires reapplying:

- Model configuration (primary model, aliases, context windows)
- Plugin configuration (diagnostics-prometheus, diagnostics-otel)
- CORS allowedOrigins for custom Routes
- Diagnostics/OTEL settings
- Capture content flags

**Current workaround:** `audience-reset.sh` has a "post-restart re-patch" phase that reapplies all config after the final restart. Alternatively, `kill 1` inside the container restarts the process without re-seeding PVC config.

**Suggestion:** Consider a merge strategy instead of full replacement on restart. For example:
- Operator manages `operator.json` (its defaults)
- User manages `openclaw.json` (their overrides)
- Runtime merges both at startup with user config taking precedence

Or: add a `spec.userConfig` section to the Claw CR that the operator preserves across reconciliation.

---

## 2. Plugin Support in CR Spec

**Problem:** Plugins (`diagnostics-prometheus`, `diagnostics-otel`) must be npm-installed inside the running container, then configured in `openclaw.json`. They survive on PVC but are lost on PVC wipe or fresh deployment. The operator has no awareness of plugins.

**Current workaround:** Scripts run `oc exec ... node /app/dist/index.js plugins install @openclaw/diagnostics-otel` inside every gateway pod, then patch `openclaw.json` to enable and configure them.

**Suggestion:** Allow plugin declaration in the Claw CR:

```yaml
spec:
  plugins:
    - name: diagnostics-prometheus
      enabled: true
    - name: diagnostics-otel
      enabled: true
      config:
        hooks:
          allowConversationAccess: true
```

The operator could then install and configure plugins automatically on deployment and after reconciliation.

---

## 3. Diagnostics / OTEL Configuration in CR Spec

**Problem:** Enabling OTEL tracing requires three separate steps that bypass the CR:

1. npm-install the `diagnostics-otel` plugin inside the container
2. Patch `openclaw.json` with `diagnostics.otel` config block (protocol, sampleRate, captureContent)
3. Set real container env vars via `oc set env` (OTEL SDK reads `process.env`, not config files)

Additionally, the `allowConversationAccess: true` flag in `plugins.entries['diagnostics-otel'].hooks` is critical but undocumented — without it, non-bundled plugins are silently blocked from conversation hooks and only heartbeat traces appear.

**Current workaround:** `audience-reset.sh` handles all three steps, plus reapplies them after every restart.

**Suggestion:** Allow diagnostics configuration in the CR:

```yaml
spec:
  diagnostics:
    enabled: true
    otel:
      enabled: true
      protocol: http/protobuf
      endpoint: http://langfuse-web.langfuse.svc.cluster.local:3000/api/public/otel/v1/traces
      headers: "Authorization=Basic <token>"
      serviceName: "openclaw-${NAMESPACE}"
      captureContent:
        inputMessages: true
        outputMessages: true
        toolInputs: true
        toolOutputs: true
    prometheus:
      enabled: true
      port: 18789
```

The operator could then:
- Auto-install required plugins
- Set OTEL env vars as real container env vars
- Create the ServiceMonitor CR
- Create necessary NetworkPolicies

---

## 4. allowedOrigins in CR Spec

**Problem:** The operator only registers its own default Route in `gateway.controlUi.allowedOrigins`. Custom Routes (e.g., unique audience URLs, public domain proxying) require manually patching `openclaw.json` after deployment — and re-patching after every restart.

**Current workaround:** Scripts patch `allowedOrigins` in `openclaw.json`, restart, then re-patch because the restart wipes the patch.

**Suggestion:** Allow CORS origins in the CR:

```yaml
spec:
  gateway:
    allowedOrigins:
      - "https://claw-*.yougetaclaw.com"
      - "https://claw-*.apps.example.com"
```

Or: auto-detect all Routes targeting the instance Service and add their hostnames to allowedOrigins.

---

## 5. Model Registration in CR Spec

**Problem:** The operator handles provider setup (API keys, auth type) but doesn't support:
- Registering specific model aliases (e.g., `gemini-2.5-pro`, `qwen3-14b`)
- Setting a model as primary
- Configuring context window, context tokens, and max tokens per model
- LiteLLM proxy model registration

**Current workaround:** Scripts patch `openclaw.json` with model configuration:
```javascript
c.agents.defaults.models['google/gemini-2.5-pro'] = {alias: 'gemini-2.5-pro'};
c.agents.defaults.model.primary = 'google/gemini-2.5-pro';
```

**Suggestion:** Allow model configuration in the CR:

```yaml
spec:
  models:
    primary: google/gemini-2.5-pro
    entries:
      - key: google/gemini-2.5-pro
        alias: gemini-2.5-pro
      - key: openai/qwen3-14b
        alias: qwen3-14b
        contextWindow: 32768
        maxTokens: 8192
```

---

## 6. Proxy Egress Port Restriction

**Problem:** The operator's proxy only allows egress on port 443 by default. MCP services running on custom ports (9001, 9003, 9004) require supplemental NetworkPolicies to be created manually.

**Current workaround:** Scripts create a `allow-proxy-to-mcp` NetworkPolicy in each namespace:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-proxy-to-mcp
spec:
  podSelector:
    matchLabels:
      app: claw-proxy
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: mcp-customer
    ports:
    - port: 9001
```

**Suggestion:** When MCP servers are registered in `spec.mcpServers`, the operator already auto-configures the proxy allowlist and gateway config. Consider also auto-creating the necessary NetworkPolicy for the MCP service ports, since the operator knows the port from the URL.

---

## 7. Cross-Namespace Egress for Tracing

**Problem:** Gateway pods need to send OTEL traces to MLflow (port 5000) or Langfuse (port 3000) in separate namespaces. The operator's default NetworkPolicy doesn't allow cross-namespace egress to arbitrary services.

**Current workaround:** Scripts create NetworkPolicies per namespace:
- `allow-instance-to-mlflow` — egress to mlflow namespace port 5000
- `allow-instance-to-langfuse` — egress to langfuse namespace port 3000

**Suggestion:** If diagnostics is added to the CR spec (see item 3), the operator could auto-create the necessary NetworkPolicy based on the configured OTEL endpoint.

---

## 8. Prometheus Integration

**Problem:** Enabling Prometheus metrics requires four manual steps:
1. npm-install `diagnostics-prometheus` plugin
2. Patch `openclaw.json` to enable diagnostics and the plugin
3. Create a NetworkPolicy allowing Prometheus to scrape port 18789
4. Create a ServiceMonitor CR for auto-discovery

**Current workaround:** `enable-prometheus.sh` handles all four steps. `audience-reset.sh` re-patches after resets.

**Suggestion:** If `spec.diagnostics.prometheus.enabled: true` is set in the CR, the operator could handle all four steps automatically. The operator already knows the gateway service name and port.

---

## 9. Operator Controller Memory Limits

**Problem:** Default operator memory limits are too high for demo/sandbox clusters, causing OOMKilled.

**Current workaround:**
```bash
oc patch deployment claw-operator-controller-manager --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/resources",
       "value":{"limits":{"memory":"512Mi"},"requests":{"memory":"128Mi"}}}]'
```

**Suggestion:** Consider lower default resource requests/limits, or make them configurable at install time.

---

## 10. Enterprise Skills Injection

**Problem:** Custom skills (e.g., `quote-builder`) must be manually copied into the gateway pod's PVC filesystem. They're lost on PVC wipe.

**Current workaround:** `audience-reset.sh` Phase 6 copies skill files into `/home/node/.openclaw/workspace/skills/<skill>/SKILL.md` via `oc exec ... bash -c 'cat > ...'`.

**Suggestion:** Consider a mechanism for persistent skill injection, either:
- `spec.skills` in the CR with ConfigMap or Secret references
- A skills volume mount from a shared ConfigMap
- Skills bundled into a custom gateway image layer

---

## 11. AGENTS.md / IDENTITY.md Pre-Population

**Problem:** Fresh gateway instances prompt users with a bootstrap questionnaire (identity, preferences). For demo environments, we need to pre-fill these to skip the questionnaire.

**Current workaround:** `audience-reset.sh` writes `IDENTITY.md` and appends enterprise instructions to `AGENTS.md` via `oc exec`.

**Suggestion:** Allow initial workspace files in the CR:

```yaml
spec:
  workspace:
    files:
      IDENTITY.md: |
        # Who Am I?
        - Name: Demo User
        - Creature: An octopus
      AGENTS.md: |
        ## Enterprise assistant
        You are a FantaCo enterprise assistant...
```

---

## 12. Route Timeout Annotation

**Problem:** The default OpenShift Route timeout (30s) is too short for LLM responses that may take 60+ seconds. Custom audience Routes need `haproxy.router.openshift.io/timeout: 3600s`.

**Current workaround:** Scripts set this annotation when creating audience Routes.

**Suggestion:** The operator-created default Route should also have an appropriate timeout annotation for LLM workloads (e.g., 5 minutes minimum).

---

## Summary: What We Patch vs. What the CR Should Support

| What We Patch | How | Ideal CR Support |
|---------------|-----|-----------------|
| Model registration + primary | `oc exec` → patch openclaw.json | `spec.models.primary`, `spec.models.entries[]` |
| Plugin installation | `oc exec` → npm install in container | `spec.plugins[]` |
| Diagnostics/OTEL config | `oc exec` → patch openclaw.json + `oc set env` | `spec.diagnostics.otel.*` |
| Prometheus metrics | `oc exec` + NetworkPolicy + ServiceMonitor | `spec.diagnostics.prometheus.enabled` |
| CORS allowedOrigins | `oc exec` → patch openclaw.json (reapply after restart) | `spec.gateway.allowedOrigins[]` |
| MCP NetworkPolicy (custom ports) | `oc apply` NetworkPolicy | Auto-create from `spec.mcpServers` port info |
| Cross-namespace egress (tracing) | `oc apply` NetworkPolicy | Auto-create from `spec.diagnostics.otel.endpoint` |
| Skills injection | `oc exec` → file copy to PVC | `spec.skills[]` or ConfigMap mount |
| Workspace files (IDENTITY.md, AGENTS.md) | `oc exec` → file write to PVC | `spec.workspace.files` |
| Route timeout | Annotation on custom Route | Default Route annotation |
| Operator memory limits | `oc patch` controller-manager | Lower defaults or install-time config |

---

## Environment Details

- **Scripts location:** `clawoperator-openclaw/` in the fantaco-redhat-summit-2026 repo
- **Key scripts:** `audience-reset.sh` (consolidates most overrides), `enable-prometheus.sh`, `deploy-traces-langfuse.sh`, `deploy-traces-mlflow.sh`
- **State management:** `.state/` directory (gitignored) for generated secrets and credentials
- **Main config:** `../.env` for API keys, model config, cluster credentials
