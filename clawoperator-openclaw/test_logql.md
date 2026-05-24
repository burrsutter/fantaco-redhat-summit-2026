# LogQL Query Examples for OpenClaw

Use these in **OpenShift Console → Observe → Logs** or in the **Grafana Explore** view with the Loki data source.

> **Important:** Namespace wildcards (`.*`) are NOT allowed by the Loki OPA policy. Use explicit alternation (`|`) instead.

## Basic Queries

### All logs for a single user

```logql
{kubernetes_namespace_name="agentic-user1"}
```

### All logs across all 5 OpenClaw users

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5"}
```

### Gateway container only (filters out proxy, device-pairing, MCP, DB)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"}
```

### Proxy container only (network allow/deny decisions)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="proxy"}
```

## Agent & Chat Activity

### WebSocket commands (chat messages, session activity)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"} |= "ws"
```

### Agent runs (model calls, completions)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"} |= "agent"
```

### Chat history / session list requests

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"} |= "chat.history"
```

### Errors only

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"} |~ "ERROR|error|Error"
```

### Warnings and errors

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="gateway"} |~ "WARN|ERROR|warn|error"
```

## MCP Tool Activity

### MCP server logs (customer backend)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="mcp-server"}
```

### Customer search queries hitting the MCP server

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="mcp-server"} |= "search"
```

### Customer lookups by ID

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="mcp-server"} |= "CUST"
```

## Identifying Which Customers a User is Talking About

These queries look for customer-related activity across the MCP server and gateway logs.

### Customer names mentioned in MCP requests

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="mcp-server"} |~ "(?i)coffee|tech|nova|spark|enchanted|fantaco"
```

### Customer IDs in MCP traffic (CUST001, CUST002, etc.)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="mcp-server"} |~ "CUST[0-9]+"
```

### All customer-related activity across all users

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5", kubernetes_container_name="mcp-server"} |~ "(?i)customer|CUST[0-9]+"
```

### Customer REST API calls (Spring Boot backend)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="fantaco-customer-main"} |= "/api/customers"
```

### Customer search via REST API (see what search terms users are using)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="fantaco-customer-main"} |= "search"
```

## Network Security (Proxy Logs)

### Blocked outbound requests (403s from proxy)

```logql
{kubernetes_namespace_name="agentic-user1", kubernetes_container_name="proxy"} |= "WARN"
```

### All proxy traffic across users

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5", kubernetes_container_name="proxy"} |= "WARN"
```

## Cross-User Comparison

### Errors across all OpenClaw instances

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5"} |~ "ERROR|error"
```

### Gateway restarts across all users

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5", kubernetes_container_name="gateway"} |= "restart"
```

### Model configuration across all users

```logql
{kubernetes_namespace_name=~"agentic-user1|agentic-user2|agentic-user3|agentic-user4|agentic-user5", kubernetes_container_name="gateway"} |= "agent model"
```

## Infrastructure Logs

### Loki stack health

```logql
{kubernetes_namespace_name="openshift-logging"} |= "error"
```

### Vector collector issues

```logql
{kubernetes_namespace_name="openshift-logging", kubernetes_container_name=~"collector|vector"} |= "error"
```

## Tips

- **Time range matters** — set it to "Last 1 hour" or wider in the top-right dropdown
- **Use `|=` for substring match** (fast) and `|~` for regex match (slower)
- **Case-insensitive regex**: `|~ "(?i)pattern"`
- **Exclude lines**: `!= "noisy-thing"` or `!~ "pattern"`
- **JSON parsing**: append `| json` to parse structured log lines, then filter fields with `| field="value"`
- **Line limit**: the default is 50 lines — increase in the UI or append `| limit 200`
