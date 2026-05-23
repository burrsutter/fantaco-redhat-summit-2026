#!/usr/bin/env bash
# list-claw-routes.sh — List all OpenClaw Routes across agentic-user namespaces
#
# Usage:
#   ./list-claw-routes.sh

set -euo pipefail

if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

oc get routes -A -l app=claw,audience-route=true \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host'
