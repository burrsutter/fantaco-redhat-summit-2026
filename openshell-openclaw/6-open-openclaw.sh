#!/usr/bin/env bash
# open-openclaw.sh
#
# Prints the OpenClaw gateway URL with auth token and opens it in the browser.
#
# Optional:
#   NAMESPACE env var (default: current oc project)
#   POD env var (default: auto-detect via app=openclaw label)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${NAMESPACE:-$(oc project -q 2>/dev/null || echo openshell)}"
CONFIG_FILE="${SCRIPT_DIR}/openclaw.json"

# Extract token from local config
TOKEN=$(grep -o '"token": *"[^"]*"' "$CONFIG_FILE" | tail -1 | sed 's/"token": *"//;s/"$//')
if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not extract token from $CONFIG_FILE"
  exit 1
fi

URL="http://127.0.0.1:18789/#token=${TOKEN}"

echo "$URL"
open "$URL"
