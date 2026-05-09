#!/usr/bin/env bash
# port-forward-openclaw.sh
#
# Port forwards the OpenClaw gateway UI (18789) from the sandbox.
# Uses openshell forward to bridge into the sandbox network namespace.
# Ctrl+C to stop.

set -euo pipefail

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
if [ -z "$SANDBOX_NAME" ]; then
  echo "ERROR: No sandbox found. Run ./3-deploy-openclaw-sandbox.sh first."
  exit 1
fi

echo "Sandbox: $SANDBOX_NAME"
echo "Forwarding localhost:18789 -> sandbox:18789"
echo ""
echo "Open the UI: http://127.0.0.1:18789/"
echo ""
echo "Press Ctrl+C to stop."
echo ""

openshell forward start 18789 "$SANDBOX_NAME"
