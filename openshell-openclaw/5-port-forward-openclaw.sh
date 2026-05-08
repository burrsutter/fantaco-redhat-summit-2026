#!/usr/bin/env bash
# port-forward-openclaw.sh
#
# Port forwards the OpenClaw gateway UI (18789) from the sandbox pod.
# Ctrl+C to stop.
#
# Optional:
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"

if [ -z "${POD:-}" ]; then
  POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
  if [ -z "$POD" ]; then
    echo "ERROR: No pod found with label app=openclaw in namespace $NAMESPACE"
    exit 1
  fi
fi

echo "Pod: $POD"
echo "Forwarding localhost:18789 -> $POD:18789"
echo ""
echo "Open the UI: http://127.0.0.1:18789/"
echo ""
echo "Press Ctrl+C to stop."
echo ""

oc port-forward "$POD" 18789:18789 -n "$NAMESPACE"
