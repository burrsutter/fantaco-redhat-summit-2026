#!/usr/bin/env bash
# open-openclaw.sh
#
# Opens the OpenClaw UI in the browser via the OpenShift Route.
# Students enter the password when prompted in the UI.
#
# Optional:
#   NAMESPACE env var (default: current oc project)

set -euo pipefail

NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"

# --- Get Route URL ---
ROUTE_HOST=$(oc get route openclaw-ui -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$ROUTE_HOST" ]; then
  echo "ERROR: Route 'openclaw-ui' not found in namespace $NAMESPACE"
  echo "Run ./4-configure-openclaw.sh first."
  exit 1
fi

URL="https://${ROUTE_HOST}/"

echo "$URL"
echo "Students enter the password when prompted."
open "$URL"
