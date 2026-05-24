#!/usr/bin/env bash
# inject-mcp-customer.sh — Register the customer MCP server in the OpenClaw gateway
#
# Patches the Claw CR with spec.mcpServers.customer so the operator:
#   - Injects the MCP config into the gateway's operator.json
#   - Adds the MCP domain as a passthrough route in the proxy config
#   - Reconciles deployments (gateway + proxy restart automatically)
#
# Also creates a supplemental NetworkPolicy so the proxy can reach the
# MCP service on port 9001 (the operator's default egress only allows 443).
#
# The MCP service must already be deployed (see deploy-fantaco-backends.sh).
#
# Usage:
#   ./inject-mcp-customer.sh              # inject into current namespace (student mode)
#   ./inject-mcp-customer.sh 2 5          # inject into agentic-user2 through agentic-user5
#   ./inject-mcp-customer.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  CURRENT_NS=$(oc project -q 2>/dev/null) || { echo "Error: cannot detect current namespace. Run 'oc project <ns>' first."; exit 1; }
  NAMESPACES+=("$CURRENT_NS")
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo "Error: start ($START) must be <= end ($END)"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # inject into current namespace"
  echo "       $0 <start> [end]  # inject into agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  Inject Customer MCP into OpenClaw Gateway"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo ""
echo "Namespaces:"
for NS in "${NAMESPACES[@]}"; do
  echo "  - ${NS}"
done
echo ""
echo "MCP entry:  customer -> http://mcp-customer-service:9001/mcp"
echo "Transport:  streamable-http"
echo ""

# ── Per-namespace injection ─────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Namespace: $NS ==="

  # 1. Verify Claw CR exists
  if ! oc get claw instance -n "$NS" &>/dev/null; then
    echo "  WARN: Claw CR 'instance' not found in $NS — skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  Claw CR: found"

  # 2. Verify MCP service exists
  if ! oc get service mcp-customer-service -n "$NS" &>/dev/null; then
    echo "  WARN: mcp-customer-service not found in $NS."
    echo "        Run deploy-fantaco-backends.sh first."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  MCP service: mcp-customer-service found"

  # 3. Patch Claw CR with mcpServers.customer
  echo "  Patching Claw CR with mcpServers.customer..."
  if oc patch claw instance -n "$NS" --type=merge -p \
    '{"spec":{"mcpServers":{"customer":{"url":"http://mcp-customer-service:9001/mcp","transport":"streamable-http"}}}}' \
    2>&1 | sed 's/^/    /'; then
    echo "  Claw CR patched."
  else
    echo "  WARN: Failed to patch Claw CR in $NS."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  # 4. Create supplemental NetworkPolicy for proxy -> MCP port 9001
  #    The operator's proxy egress only allows port 443. K8s NetworkPolicies
  #    are additive, so this extra policy allows the proxy to reach the MCP
  #    service without conflicting with the operator-managed policies.
  echo "  Applying supplemental NetworkPolicy (proxy -> mcp-customer:9001)..."
  cat <<'NETPOL' | oc apply -n "$NS" -f - 2>&1 | sed 's/^/    /'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-proxy-to-mcp
  labels:
    app: fantaco-mcp
spec:
  podSelector:
    matchLabels:
      app: claw-proxy
      claw.sandbox.redhat.com/instance: instance
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: mcp-customer
      ports:
        - port: 9001
          protocol: TCP
NETPOL

  # 5. Wait for operator reconciliation (gateway + proxy rollout)
  echo "  Waiting for gateway rollout..."
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    echo "  Gateway rolled out."
  else
    echo "  WARN: Gateway rollout did not complete within 120s."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi

  echo "  Waiting for proxy rollout..."
  if oc rollout status deployment/instance-proxy -n "$NS" --timeout=120s 2>/dev/null; then
    echo "  Proxy rolled out."
  else
    echo "  WARN: Proxy rollout did not complete within 120s."
  fi

  # 6. Verify Claw CR status conditions
  echo "  Checking Claw CR status..."
  MCP_CONDITION=$(oc get claw instance -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="McpServersConfigured")].status}' 2>/dev/null)
  READY_CONDITION=$(oc get claw instance -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  if [[ "$MCP_CONDITION" == "True" ]]; then
    echo "  McpServersConfigured: True"
  else
    echo "  WARN: McpServersConfigured: ${MCP_CONDITION:-not set}"
  fi
  if [[ "$READY_CONDITION" == "True" ]]; then
    echo "  Ready: True"
  else
    echo "  WARN: Ready: ${READY_CONDITION:-not set}"
  fi

  # 7. Verify connectivity from gateway pod to MCP service (through proxy)
  echo "  Verifying MCP connectivity (gateway -> proxy -> mcp-customer)..."
  MCP_CHECK=$(oc exec deployment/instance -n "$NS" -c gateway -- \
    curl -sf -o /dev/null -w '%{http_code}' \
    -X POST "http://mcp-customer-service:9001/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' \
    2>/dev/null || echo "FAILED")

  if [[ "$MCP_CHECK" == "200" ]]; then
    echo "  Connectivity OK (HTTP 200)"
  elif [[ "$MCP_CHECK" == "FAILED" ]]; then
    echo "  WARN: Could not reach mcp-customer-service from gateway pod."
    echo "        Check proxy logs: oc logs deployment/instance-proxy -n $NS --tail=20"
  else
    echo "  MCP responded with HTTP $MCP_CHECK"
  fi

  # 8. Show current MCP config in gateway
  echo "  Current MCP servers in config:"
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const c = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json'));
    const servers = (c.mcp && c.mcp.servers) || {};
    for (const [name, cfg] of Object.entries(servers)) {
      console.log('    ' + name + ': ' + cfg.url + ' (' + cfg.transport + ')');
    }
  " 2>/dev/null || echo "    (could not read config)"

  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  echo ""
done

# ── Summary ─────────────────────────────────────────────────────────
echo "============================================"
echo "  MCP Injection Summary"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo ""
echo "Open the OpenClaw UI to verify customer MCP tools are available."
