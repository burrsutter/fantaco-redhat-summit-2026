#!/usr/bin/env bash
# approve-telegram-pairing.sh
#
# Approves a Telegram pairing code on the OpenClaw gateway.
#
# Usage:
#   ./scripts/approve-telegram-pairing.sh <PAIRING_CODE>
#
# Optional:
#   NAMESPACE env var (default: current oc project)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <PAIRING_CODE>" >&2
  exit 1
fi

PAIRING_CODE="$1"
NAMESPACE="${NAMESPACE:-$(oc project -q)}"

POD=$(oc get pod -l app=openclaw -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$POD" ]]; then
  echo "Error: No openclaw pod found in namespace $NAMESPACE" >&2
  exit 1
fi

echo "Namespace: $NAMESPACE"
echo "Pod:       $POD"
echo "Code:      $PAIRING_CODE"

oc exec "$POD" -c gateway -n "$NAMESPACE" -- openclaw pairing approve "$PAIRING_CODE"
