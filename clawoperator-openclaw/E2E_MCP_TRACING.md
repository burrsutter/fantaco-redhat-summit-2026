# End-to-End Distributed Tracing: OpenClaw Agent through MCP Server

**Status:** Research document (2026-05-26)
**Goal:** Determine how to get a single trace spanning OpenClaw agent turn, MCP tool call, and MCP server execution, visible in **Langfuse**.
**Scope:** Python-based MCP servers only (FastMCP). Java backends are out of scope for now.

---

## Table of Contents

1. [Current State](#1-current-state)
2. [Does the MCP Protocol Support Trace Context Propagation?](#2-does-the-mcp-protocol-support-trace-context-propagation)
3. [How Could OTEL Context Propagate from OpenClaw through MCP Calls?](#3-how-could-otel-context-propagate-from-openclaw-through-mcp-calls)
4. [MCP Server SDKs and OTEL Instrumentation](#4-mcp-server-sdks-and-otel-instrumentation)
5. [Existing OpenClaw Plugins or Configurations for This](#5-existing-openclaw-plugins-or-configurations-for-this)
6. [What Would Need to Change in the MCP Server Code](#6-what-would-need-to-change-in-the-mcp-server-code)
7. [How This Would Appear in Langfuse or MLflow](#7-how-this-would-appear-in-langfuse-or-mlflow)
8. [Recommended Path Forward](#8-recommended-path-forward)
9. [References](#9-references)

---

## 1. Current State

### Tracing architecture today

```
OpenClaw Gateway Pod
  |
  +-- langfuse-tracer plugin       --> Langfuse REST API (prompt/response text)
  |     hooks: before_agent_start, agent_end
  |     sends: trace-create + generation-create per agent turn
  |
  +-- diagnostics-otel plugin      --> MLflow OTEL endpoint (spans, tokens, timing)
  |     sends: openclaw.agent.turn, openclaw.model.usage, tool loop spans
  |
  +-- diagnostics-prometheus        --> Prometheus scrape (metrics)
```

### MCP server architecture today

```
OpenClaw Gateway (Node.js, runtime 2026.5.22)
  |
  +-- built-in MCP client
  |     transport: streamable-http
  |     routes through: instance-proxy:8080
  |
  +---> mcp-customer-service:9001/mcp     (FastMCP 2.13.3, Python)
  +---> mcp-product-service:9003/mcp      (FastMCP 2.13.3, Python)
  +---> mcp-sales-order-service:9004/mcp  (FastMCP 2.13.3, Python)
  +---> mcp-finance-service:9002/mcp      (FastMCP 2.13.3, Python)
  +---> mcp-hr-recruiting-service:9005    (FastMCP 2.13.3, Python)
  +---> mcp-sales-policy-search:9006      (FastMCP 2.13.3, Python)
  +---> mcp-hr-policy-service:9007        (FastMCP 2.13.3, Python)
```

### The gap

Today, OpenClaw's `diagnostics-otel` plugin emits `openclaw.tool.loop` spans that record tool call metadata (name, duration) but these spans end at the OpenClaw gateway boundary. The MCP servers have zero OTEL instrumentation. There is no trace context propagation across the MCP boundary. Result: two disconnected trace worlds.

The `langfuse-tracer` plugin is even more limited -- it only captures one trace per agent turn (prompt in, response out) with no sub-spans for individual tool calls at all.

---

## 2. Does the MCP Protocol Support Trace Context Propagation?

**Yes.** As of the 2026-07-28 MCP Specification Release Candidate (SEP-414), W3C Trace Context propagation via `params._meta` is formally standardized.

### How it works

The MCP JSON-RPC protocol uses `params._meta` as a metadata property bag. SEP-414 reserves three key names for trace context:

- `traceparent` -- W3C Trace Context parent header
- `tracestate` -- W3C Trace Context state header
- `baggage` -- W3C Baggage header

Example MCP request with trace context:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "search_customers",
    "arguments": {
      "company_name": "Tech Solutions"
    },
    "_meta": {
      "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
      "tracestate": "rojo=00f067aa0ba902b7"
    }
  },
  "id": 1
}
```

### Why `_meta` instead of HTTP headers?

MCP is transport-independent. It works over stdio, SSE, and streamable HTTP. HTTP headers only cover HTTP transport. Multiple MCP requests can be sent over a single HTTP request. The `_meta` approach works identically regardless of transport.

MCP and underlying transport (such as HTTP) contexts are independent. The MCP specification recommends that MCP server instrumentation use context extracted from `params._meta` as the parent for MCP server spans, and link (not parent) the current ambient HTTP context if present.

### Key point

SEP-414 explicitly rejected DNS-prefixed key names (like `io.modelcontextprotocol.traceparent`) in favor of the bare W3C names. This means standard OpenTelemetry propagators work without any MCP-specific configuration.

---

## 3. How Could OTEL Context Propagate from OpenClaw through MCP Calls?

There are two sides to this: the **client side** (OpenClaw gateway, injecting context into outbound MCP requests) and the **server side** (MCP servers, extracting context and creating child spans).

### Client side: OpenClaw gateway

OpenClaw v2026.4.25 added an "internal traceparent propagation helper that only formats trusted dispatcher metadata." The `diagnostics-otel` plugin creates spans for tool calls (`openclaw.tool.loop`) as part of the agent turn trace.

The question is whether OpenClaw's built-in MCP client currently injects `traceparent` into `params._meta` when making MCP tool calls. Based on the research:

- **OpenClaw's MCP client does have trace context awareness.** The v2026.4.25 release notes mention "propagate W3C `traceparent` headers from trusted model-call trace context to provider transports."
- **However**, the project is running runtime version **2026.5.22**. The exact behavior of `_meta` injection in this version is not documented in publicly available release notes.
- **The `diagnostics-otel` plugin must be enabled** for there to be an active OTEL context to propagate. This is already the case in our deployment.

**Assessment:** It is likely but not confirmed that the OpenClaw runtime 2026.5.22 already injects `traceparent` into `params._meta` for MCP tool calls when `diagnostics-otel` is enabled. This needs to be verified empirically by inspecting MCP request logs on the server side.

### Server side: MCP servers (FastMCP 2.13.3)

**FastMCP 2.x does NOT have built-in OpenTelemetry support.** Native OTEL instrumentation was introduced in FastMCP 3.0 (released January 2026). Our MCP servers pin `fastmcp==2.13.3`.

This means even if OpenClaw sends `traceparent` in `_meta`, the MCP servers currently ignore it. No child spans are created. The trace ends at the gateway.

---

## 4. MCP Server SDKs and OTEL Instrumentation

### Option A: Upgrade to FastMCP 3.x (recommended)

FastMCP 3.0+ has native OpenTelemetry instrumentation:

- **Zero-config tracing**: All tool calls, resource reads, and prompt renders automatically create spans.
- **MCP semantic conventions**: Span names follow `{method} {target}` format (e.g., `tools/call search_customers`), with `mcp.method.name`, `mcp.session.id`, and `gen_ai.tool.name` attributes.
- **Context extraction from `_meta`**: FastMCP 3.x extracts `traceparent`/`tracestate` from `params._meta` and uses it as the parent context for server spans.
- **Auto-instrumentation**: Run with `opentelemetry-instrument fastmcp run server.py` for zero-code OTEL setup.
- **Programmatic setup**: Configure the OTEL SDK before importing FastMCP.

Required pip packages for OTEL export:
```
fastmcp>=3.0.0
opentelemetry-api
opentelemetry-sdk
opentelemetry-exporter-otlp-proto-http
```

Run with:
```bash
OTEL_SERVICE_NAME=mcp-customer \
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces \
OTEL_EXPORTER_OTLP_TRACES_HEADERS=x-mlflow-experiment-id=1 \
opentelemetry-instrument python customer-api-mcp-server.py
```

**Breaking changes risk**: FastMCP 3.0 is a major version upgrade. The server code uses `FastMCP("name")`, `@mcp.tool()`, and `mcp.run(transport="http")` which are all still supported in 3.x. The migration risk is low for our straightforward server implementations.

### Option B: Use third-party instrumentation (keep FastMCP 2.x)

Several packages provide auto-instrumentation for FastMCP without upgrading:

1. **`opentelemetry-instrumentation-mcp`** (by Traceloop/OpenLLMetry, v0.52.3)
   - Auto-instruments the MCP Python SDK
   - pip install: `opentelemetry-instrumentation-mcp`
   - May produce doubled spans if combined with FastMCP 3.x built-in instrumentation

2. **`splunk-otel-instrumentation-fastmcp`** (by Splunk)
   - Specifically targets FastMCP
   - Automatically propagates W3C TraceContext (`traceparent`, `tracestate`) between MCP client and server
   - pip install: `splunk-otel-instrumentation-fastmcp`

3. **`shinzo-py`** (Shinzo SDK)
   - Zero-code-change automatic instrumentation for FastMCP and MCP SDK
   - Rich metrics (request duration, error rates)

### Option C: Manual instrumentation (keep FastMCP 2.x)

Add OpenTelemetry instrumentation manually to each MCP server. This gives full control but requires code changes to every tool function:

```python
from opentelemetry import trace, context, propagation
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

# Configure OTEL SDK
provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(
    OTLPSpanExporter(endpoint="http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces")
))
trace.set_tracer_provider(provider)

tracer = trace.get_tracer("mcp-customer")

def extract_context_from_meta(meta: dict | None):
    """Extract OTEL context from MCP _meta field."""
    if not meta:
        return context.get_current()
    carrier = {}
    if "traceparent" in meta:
        carrier["traceparent"] = meta["traceparent"]
    if "tracestate" in meta:
        carrier["tracestate"] = meta["tracestate"]
    if "baggage" in meta:
        carrier["baggage"] = meta["baggage"]
    return propagation.extract(carrier) if carrier else context.get_current()

@mcp.tool()
async def search_customers(
    company_name: str = None,
    _meta: dict = None,  # <-- accept _meta parameter
) -> Dict[str, Any]:
    ctx = extract_context_from_meta(_meta)
    with tracer.start_as_current_span(
        "tools/call search_customers",
        context=ctx,
        kind=trace.SpanKind.SERVER,
        attributes={"mcp.method.name": "tools/call", "gen_ai.tool.name": "search_customers"},
    ):
        # ... existing implementation ...
```

**Downside**: Requires adding `_meta` parameter and trace code to every tool function. FastMCP 2.x may not pass `_meta` to tool functions automatically.

---

## 5. Existing OpenClaw Plugins or Configurations for This

### What exists today

1. **`diagnostics-otel` plugin (built-in)**
   - Creates `openclaw.agent.turn` root span per agent interaction
   - Creates child spans: `openclaw.model.usage` (LLM calls), `openclaw.tool.loop` (tool execution cycles)
   - Captures tool inputs/outputs when `captureContent` is enabled
   - Exports via OTLP/HTTP to MLflow
   - **Does NOT appear to propagate trace context to remote MCP servers via `_meta`** in the current deployment (needs verification)

2. **`langfuse-tracer` plugin (custom, vendored)**
   - Sends one trace per agent turn to Langfuse REST API
   - No sub-spans for individual tool calls
   - No distributed tracing capability

3. **`diagnostics-prometheus` plugin (built-in)**
   - Metrics only, no traces

4. **`openclaw-observability-plugin`** (third-party, by Henrik Rexed)
   - Community plugin with deeper tracing: session context propagation, agent turn duration, dispatch prepare/reply phases
   - Uses `TraceContextStore` for session-level trace correlation
   - Head-based sampling support
   - Not currently deployed in this project

### What may exist but is unverified

- **OpenClaw v2026.4.25+ traceparent propagation**: The release notes mention an "internal traceparent propagation helper." This may already inject `traceparent` into `params._meta` for MCP calls when `diagnostics-otel` is active. This needs empirical verification.

### What does NOT exist

- No configuration flag in `openclaw.json` to explicitly enable/disable MCP trace context propagation
- No documentation in the OpenClaw docs about end-to-end MCP distributed tracing
- No OTEL instrumentation of any kind in the FantaCo MCP servers

---

## 6. What Would Need to Change in the MCP Server Code

### Minimal changes (Option A: upgrade to FastMCP 3.x)

**Step 1: Update `requirements.txt`** for each MCP server:

```
fastmcp>=3.2.0
python-dotenv==1.2.1
opentelemetry-api>=1.40.0
opentelemetry-sdk>=1.40.0
opentelemetry-exporter-otlp-proto-http>=1.40.0
```

**Step 2: No Python code changes needed.** FastMCP 3.x auto-instruments all `@mcp.tool()` functions. The `FastMCP("name")`, `@mcp.tool()`, and `mcp.run(transport="http")` APIs are backward compatible.

**Step 3: Update the Dockerfile** to run with `opentelemetry-instrument`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY customer-api-mcp-server.py .

# Use opentelemetry-instrument wrapper for auto-instrumentation
CMD ["opentelemetry-instrument", "python", "customer-api-mcp-server.py"]
```

Or configure the OTEL SDK programmatically before the `FastMCP` import (zero Dockerfile changes but requires a small code addition at the top of each server file).

**Step 4: Set OTEL environment variables** in the Helm chart or deployment:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: mcp-customer
  - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    value: http://mlflow-mlflow.mlflow.svc.cluster.local:5000/v1/traces
  - name: OTEL_EXPORTER_OTLP_TRACES_HEADERS
    value: x-mlflow-experiment-id=1
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: http/protobuf
```

**Step 5: Add NetworkPolicy** allowing MCP server pods to reach MLflow (or Langfuse):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mcp-to-mlflow
spec:
  podSelector:
    matchLabels:
      app: mcp-customer  # repeat for each MCP server
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: mlflow
    ports:
    - port: 5000
      protocol: TCP
```

### Moderate changes (Option B: keep FastMCP 2.x, add third-party instrumentation)

Same as Option A but use `splunk-otel-instrumentation-fastmcp` or `opentelemetry-instrumentation-mcp` instead of relying on FastMCP 3.x built-in support. Requires adding the instrumentation package to `requirements.txt` and potentially calling `FastMCPInstrumentor().instrument()` in the server code.

---

## 7. How This Would Appear in Langfuse or MLflow

### In MLflow (via diagnostics-otel + MCP server OTEL)

If both sides export to the same MLflow OTEL endpoint with the same `trace_id`, MLflow would show a single trace with the full span tree:

```
openclaw-agent-turn (root span, from OpenClaw diagnostics-otel)
  |
  +-- chat gpt-5.4-mini (LLM inference span)
  |
  +-- openclaw.tool.loop (tool execution loop)
  |     |
  |     +-- tools/call search_customers (MCP CLIENT span, from OpenClaw)
  |           |
  |           +-- tools/call search_customers (MCP SERVER span, from FastMCP)
  |                 |
  |                 +-- GET /api/customers (HTTP client span, from httpx)
  |
  +-- chat gpt-5.4-mini (follow-up LLM call with tool results)
```

Each span would carry attributes like:
- `mcp.method.name: tools/call`
- `gen_ai.tool.name: search_customers`
- `mcp.session.id: <session>`
- `service.name: mcp-customer` (on the server spans)
- `service.name: openclaw-agentic-user6` (on the gateway spans)

### In Langfuse (via langfuse-tracer)

The current `langfuse-tracer` plugin only sends one trace per turn and does not participate in OTEL distributed tracing. To get MCP sub-spans in Langfuse, you would need one of:

1. **Route MCP server OTEL to Langfuse's OTEL endpoint** (`/api/public/otel/v1/traces`). The MCP server spans would appear as separate OTEL traces in Langfuse. They would NOT be connected to the `langfuse-tracer` traces because those are created via REST API with independent trace IDs.

2. **Enhance the `langfuse-tracer` plugin** to create sub-spans for each tool call using Langfuse's REST API. This would require hooking into `before_tool_call` / `after_tool_call` events (if available in the plugin API) and creating `span-create` items in the Langfuse batch. The MCP server side would still need separate instrumentation.

3. **Replace `langfuse-tracer` with OTEL-only approach**: Route `diagnostics-otel` to Langfuse's OTEL endpoint instead of MLflow, and also route MCP server OTEL to the same Langfuse endpoint. Downside: Langfuse's OTEL ingestion is experimental and does not populate Langfuse's native input/output fields well (this was the original reason for creating the custom `langfuse-tracer` plugin).

4. **Hybrid approach**: Keep `langfuse-tracer` for the human-readable prompt/response view. Also route `diagnostics-otel` AND MCP server OTEL to a shared backend (MLflow or Jaeger/Tempo) for the full distributed trace waterfall. View prompt text in Langfuse, view distributed traces in MLflow.

### Practical outcome

The most realistic near-term outcome is **MLflow as the distributed trace backend**:
- OpenClaw `diagnostics-otel` sends the agent-side spans to MLflow (already working)
- MCP servers send their tool execution spans to the same MLflow endpoint (to be implemented)
- If OpenClaw propagates `traceparent` via `_meta`, both sides share the same `trace_id` and MLflow shows a unified trace tree
- Langfuse continues to show the human-readable prompt/response view via `langfuse-tracer` (no change)

---

## 8. Recommended Path Forward (Langfuse-focused, Python MCP servers only)

**Scope:** Only the 7 Python-based MCP servers. Java backends are out of scope for now.
**Target backend:** Langfuse (not MLflow).

### Phase 1: Verify OpenClaw trace context propagation (no code changes)

Before changing any MCP server code, verify whether OpenClaw already injects `traceparent` into `params._meta`:

```bash
# Add a debug print to one MCP server's tool function and check logs after a tool call
# Or inspect MCP traffic at the proxy level
```

### Phase 2: Upgrade FastMCP to 3.x and add OTEL export to Langfuse

1. Update `requirements.txt` in all 7 MCP servers: `fastmcp>=3.2.0` + OTEL packages
2. Update Dockerfiles to use `opentelemetry-instrument` wrapper
3. Set OTEL env vars to point at Langfuse's OTEL endpoint:
   ```yaml
   env:
     - name: OTEL_SERVICE_NAME
       value: mcp-customer
     - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
       value: http://langfuse-web.langfuse.svc.cluster.local:3000/api/public/otel/v1/traces
     - name: OTEL_EXPORTER_OTLP_TRACES_HEADERS
       value: Authorization=Basic <base64(public_key:secret_key)>
     - name: OTEL_EXPORTER_OTLP_PROTOCOL
       value: http/protobuf
   ```
4. Add NetworkPolicy for MCP pods to reach Langfuse
5. Rebuild container images with `--platform linux/amd64` (see memory note on arch mismatch)
6. Redeploy MCP servers
7. Update `audience-reset.sh` to set OTEL env vars on MCP deployments

**Estimated effort:** 2-4 hours including image rebuild and testing.

### Phase 3: Enhance langfuse-tracer with tool call sub-spans

To get MCP tool calls visible as nested spans within the existing Langfuse traces:

1. Add `before_tool_call` / `after_tool_call` hooks to the `langfuse-tracer` plugin
2. Create Langfuse `span-create` items nested under the `openclaw-turn` trace
3. Include tool name, input arguments, output result, and duration

This captures tool call metadata from the OpenClaw gateway side. Combined with Phase 2, Langfuse would show both:
- The agent-level trace with tool sub-spans (from `langfuse-tracer`)
- The MCP server execution spans (from OTEL)

### Phase 4: Correlate langfuse-tracer REST traces with MCP OTEL spans

To link the two trace sources in Langfuse:

1. Pass the `langfuse-tracer` trace ID as the `traceparent` trace ID
2. Or use Langfuse's `externalId` field to cross-reference
3. This is the most complex step and may require changes to how `langfuse-tracer` generates trace IDs

### Summary

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| 1 | Verify OpenClaw `_meta` propagation | 30 min | Determines if traces will auto-connect |
| 2 | Upgrade FastMCP 2.13 → 3.x + OTEL → Langfuse | 2-4 hrs | MCP server spans visible in Langfuse |
| 3 | Enhance langfuse-tracer with tool sub-spans | 2 hrs | Tool calls nested in Langfuse traces |
| 4 | Correlate REST + OTEL traces in Langfuse | 2-4 hrs | Unified view (may not be needed if Phase 2+3 are sufficient) |

The sweet spot is **Phases 1-3**: upgrade FastMCP, export OTEL to Langfuse, and add tool sub-spans to `langfuse-tracer`.

---

## 9. References

### MCP Specification and Standards
- [SEP-414: Document OpenTelemetry Trace Context Propagation Conventions](https://modelcontextprotocol.io/seps/414-request-meta)
- [MCP 2026-07-28 Release Candidate](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/)
- [PR #414: Document request.params._meta convention](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/414)
- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)

### OpenTelemetry Semantic Conventions
- [OTEL Semantic Conventions for MCP](https://opentelemetry.io/docs/specs/semconv/gen-ai/mcp/)
- [OTEL Semantic Conventions for GenAI](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [PR #2083: MCP semantic conventions](https://github.com/open-telemetry/semantic-conventions/pull/2083)

### FastMCP
- [FastMCP OpenTelemetry Documentation](https://gofastmcp.com/servers/telemetry)
- [Introducing FastMCP 3.0](https://jlowin.dev/blog/fastmcp-3)

### OpenClaw
- [OpenClaw v2026.4.25 Release Notes](https://github.com/openclaw/openclaw/releases/tag/v2026.4.25)
- [OpenClaw Logging Documentation](https://docs.openclaw.ai/logging)
- [OpenClaw MCP Documentation](https://docs.openclaw.ai/cli/mcp)
- [PR #11100: Diagnostics OTEL plugin wiring + GenAI semantic conventions](https://github.com/openclaw/openclaw/pull/11100)

### Distributed Tracing Examples
- [FastMCP Distributed Tracing with _meta Context Propagation](https://timvw.be/2025/10/14/fastmcp-distributed-tracing-transport-agnostic-context-propagation-with-_meta/)
- [Langfuse MCP Tracing Documentation](https://langfuse.com/docs/observability/features/mcp-tracing)
- [Langfuse MCP Tracing Examples](https://github.com/langfuse/langfuse-examples/tree/main/applications/mcp-tracing)
- [Agent Traces Need to Cross the MCP Boundary](https://focused.io/lab/agent-traces-need-to-cross-the-mcp-boundary)
- [Distributed Tracing for Agentic Workflows (Red Hat Developer)](https://developers.redhat.com/articles/2026/04/06/distributed-tracing-agentic-workflows-opentelemetry)

### OTEL Instrumentation Packages
- [opentelemetry-instrumentation-mcp (PyPI)](https://pypi.org/project/opentelemetry-instrumentation-mcp/)
- [splunk-otel-instrumentation-fastmcp (PyPI)](https://pypi.org/project/splunk-otel-instrumentation-fastmcp/)
- [Google Cloud: Instrument a self-hosted MCP server with OpenTelemetry](https://docs.cloud.google.com/stackdriver/docs/instrumentation/self-hosted-mcp-servers)
- [openclaw-observability-plugin (Henrik Rexed)](https://github.com/henrikrexed/openclaw-observability-plugin)
