#!/usr/bin/env bash
# open-openclaw.sh
#
# Prints the OpenClaw gateway URL with auth token and opens it in the browser.
#
# Optional:
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"

# --- Resolve pod name ---
if [ -z "${POD:-}" ]; then
  POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
  if [ -z "$POD" ]; then
    echo "ERROR: No pod found with label app=openclaw in namespace $NAMESPACE"
    exit 1
  fi
fi

# Extract token from openclaw.json inside the running pod
TOKEN=$(oc exec "$POD" -n "$NAMESPACE" -- grep -o '"token": *"[^"]*"' /sandbox/.openclaw/openclaw.json 2>/dev/null | tail -1 | sed 's/"token": *"//;s/"$//')
if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not extract token from pod $POD"
  echo "Run ./4-configure-openclaw.sh first."
  exit 1
fi

URL="http://127.0.0.1:18789/#token=${TOKEN}"

echo "$URL"
open "$URL"
