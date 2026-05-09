#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-$(oc project -q 2>/dev/null)}"

if [[ -z "$NAMESPACE" ]]; then
  echo "Error: no namespace provided and could not detect current oc project" >&2
  exit 1
fi

POD=$(oc get pods -n "$NAMESPACE" -l app=openclaw -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "$POD" ]]; then
  echo "Error: no pod with label app=openclaw found in namespace $NAMESPACE" >&2
  exit 1
fi

IDENTITY_PATH="/sandbox/.openclaw/workspace/IDENTITY.md"
USER_PATH="/sandbox/.openclaw/workspace/USER.md"

CLAW_NAME=$(oc exec -n "$NAMESPACE" "$POD" -- cat "$IDENTITY_PATH" 2>/dev/null \
  | grep '\*\*Name:\*\*' | head -1 | sed 's/.*\*\*Name:\*\* //')

USER_NAME=$(oc exec -n "$NAMESPACE" "$POD" -- cat "$USER_PATH" 2>/dev/null \
  | grep '\*\*Name:\*\*' | head -1 | sed 's/.*\*\*Name:\*\* //')

echo "Namespace:  $NAMESPACE"
echo "Pod:        $POD"
echo "Claw Name:  ${CLAW_NAME:-<not found>}"
echo "User Name:  ${USER_NAME:-<not found>}"
