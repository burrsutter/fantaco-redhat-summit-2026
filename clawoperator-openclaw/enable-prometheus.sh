#!/usr/bin/env bash
# enable-prometheus.sh — Enable Prometheus metrics scraping for OpenClaw instances
#
# Installs the diagnostics-prometheus plugin, enables diagnostics in config,
# and creates a ServiceMonitor CR so Prometheus (User Workload Monitoring)
# auto-discovers the metrics endpoint.
#
# Auth: Uses the existing claw-password secret (the gateway password doubles
# as a Bearer token for operator-scope API routes like /api/diagnostics/prometheus).
#
# Usage:
#   ./enable-prometheus.sh              # current namespace (student mode)
#   ./enable-prometheus.sh 2 5          # agentic-user2 through agentic-user5
#   ./enable-prometheus.sh 3            # just agentic-user3
#
# Prerequisites:
#   - User Workload Monitoring enabled (openshift-user-workload-monitoring)
#   - OpenClaw instances already deployed (gateway pods running)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  echo "Usage: $0                # enable in current namespace"
  echo "       $0 <start> [end]  # enable in agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  Enable Prometheus Metrics for OpenClaw"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo ""
echo "Namespaces:"
for NS in "${NAMESPACES[@]}"; do
  echo "  - ${NS}"
done
echo ""

# ── Per-namespace setup ─────────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Configuring namespace: $NS ==="

  # Verify gateway pod is running
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo "  WARN: No gateway pod found in $NS -- skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  Gateway pod: $POD"

  # 1. Install the diagnostics-prometheus plugin (npm, not ClawHub)
  echo "  Installing diagnostics-prometheus plugin..."
  oc exec deployment/instance -n "$NS" -c gateway -- \
    node /app/dist/index.js plugins install @openclaw/diagnostics-prometheus 2>&1 \
    | grep -E "^(Installed|Already|Error)" || true

  # 2. Patch openclaw.json: enable diagnostics + prometheus plugin
  echo "  Patching openclaw.json (diagnostics + prometheus plugin)..."
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const fs = require('fs');
    const f = '/home/node/.openclaw/openclaw.json';
    const c = JSON.parse(fs.readFileSync(f));

    // Enable diagnostics
    c.diagnostics = { enabled: true };

    // Enable diagnostics-prometheus plugin
    if (!c.plugins) c.plugins = {};
    if (!c.plugins.allow) c.plugins.allow = [];
    if (!c.plugins.allow.includes('diagnostics-prometheus')) {
      c.plugins.allow.push('diagnostics-prometheus');
    }
    if (!c.plugins.entries) c.plugins.entries = {};
    c.plugins.entries['diagnostics-prometheus'] = { enabled: true };

    fs.writeFileSync(f, JSON.stringify(c, null, 2));
    console.log('OK');
  "

  # 3. Create NetworkPolicy to allow Prometheus scraping
  echo "  Creating NetworkPolicy: allow-prometheus-scrape..."
  oc apply -n "$NS" -f - <<NPEOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchLabels:
      app: claw
      claw.sandbox.redhat.com/instance: instance
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          network.openshift.io/policy-group: monitoring
    ports:
    - port: 18789
      protocol: TCP
  policyTypes:
  - Ingress
NPEOF

  # 4. Create ServiceMonitor CR (uses claw-password as Bearer token)
  echo "  Creating ServiceMonitor: openclaw-gateway..."
  oc apply -n "$NS" -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: openclaw-gateway
spec:
  endpoints:
  - interval: 30s
    port: gateway
    path: /api/diagnostics/prometheus
    authorization:
      type: Bearer
      credentials:
        name: claw-password
        key: password
  selector:
    matchLabels:
      app: claw
      claw.sandbox.redhat.com/instance: instance
EOF

  # 5. Restart gateway to load the plugin
  echo "  Restarting gateway deployment..."
  oc rollout restart deployment/instance -n "$NS"

  echo "  Waiting for rollout..."
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    echo "  Gateway restarted successfully."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  WARN: Rollout did not complete within 120s."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
done

# ── Summary ─────────────────────────────────────────────────────────
echo "============================================"
echo "  Prometheus Setup Complete"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo ""
echo "Verify:"
echo "  # Check metrics endpoint (pick any namespace):"
echo "  PASS=\$(oc get secret claw-password -n <NS> -o jsonpath='{.data.password}' | base64 -d)"
echo "  oc exec deployment/instance -n <NS> -c gateway -- \\"
echo "    curl -s -H \"Authorization: Bearer \$PASS\" \\"
echo "    http://localhost:18789/api/diagnostics/prometheus | head -20"
echo ""
echo "  # Check ServiceMonitor:"
echo "  oc get servicemonitor -n <NS>"
echo ""
echo "  # In OpenShift Console -> Observe -> Metrics:"
echo "  #   Query: openclaw_model_call_total"
