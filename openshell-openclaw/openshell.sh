#!/usr/bin/env bash
# openshell.sh — namespace-aware wrapper for the openshell CLI
#
# Detects the current oc project and ensures a port-forward to the
# gateway in that namespace is running. Reuses an existing port-forward
# if the namespace hasn't changed. Automatically restarts when you
# switch namespaces.
#
# Usage:
#   ./openshell.sh status
#   ./openshell.sh sandbox list
#   ./openshell.sh provider create --name anthropic --type generic --credential ANTHROPIC_API_KEY
#
# Optional:
#   OPENSHELL_BIN    path to openshell binary (default: auto-detect)
#   GATEWAY_PORT     local port (default: 8081)
#   GATEWAY_NAME     CLI gateway name (default: local)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATEWAY_PORT="${GATEWAY_PORT:-8081}"
GATEWAY_NAME="${GATEWAY_NAME:-local}"
PF_STATE="/tmp/openshell-pf-${GATEWAY_PORT}.ns"

# --- Find the openshell binary ---
if [ -n "${OPENSHELL_BIN:-}" ]; then
  OPENSHELL="$OPENSHELL_BIN"
elif command -v openshell &>/dev/null; then
  OPENSHELL="$(command -v openshell)"
else
  # Default: look in the sibling OpenShell repo
  OPENSHELL="${SCRIPT_DIR}/../../OpenShell/target/release/openshell"
fi

if [ ! -x "$OPENSHELL" ]; then
  echo "ERROR: openshell binary not found at $OPENSHELL"
  echo "Set OPENSHELL_BIN or add openshell to PATH."
  exit 1
fi

# --- Detect namespace ---
NAMESPACE="$(oc project -q 2>/dev/null || true)"
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: Not logged in to an oc project. Run: oc project <namespace>"
  exit 1
fi

# --- Check if gateway pod exists ---
if ! oc get pods -l app.kubernetes.io/name=openshell -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q Running; then
  echo "ERROR: No running openshell gateway pod in $NAMESPACE"
  exit 1
fi

# --- Check if existing port-forward matches current namespace ---
NEED_RESTART=true
if [ -f "$PF_STATE" ]; then
  SAVED_NS=$(cat "$PF_STATE" 2>/dev/null || true)
  PF_PID=$(lsof -ti :"$GATEWAY_PORT" 2>/dev/null | head -1 || true)
  if [ "$SAVED_NS" = "$NAMESPACE" ] && [ -n "$PF_PID" ]; then
    NEED_RESTART=false
  fi
fi

if [ "$NEED_RESTART" = true ]; then
  # Kill any existing port-forward on this port
  lsof -ti :"$GATEWAY_PORT" 2>/dev/null | xargs kill 2>/dev/null || true
  sleep 1

  # Start port-forward for current namespace
  kubectl -n "$NAMESPACE" port-forward svc/openshell "${GATEWAY_PORT}:8080" &>/dev/null &
  sleep 2

  PF_PID=$(lsof -ti :"$GATEWAY_PORT" 2>/dev/null | head -1 || true)
  if [ -z "$PF_PID" ]; then
    echo "ERROR: Port forward failed to start for $NAMESPACE"
    exit 1
  fi

  # Register gateway
  "$OPENSHELL" gateway remove "$GATEWAY_NAME" 2>/dev/null || true
  "$OPENSHELL" gateway add "http://127.0.0.1:${GATEWAY_PORT}" --local --name "$GATEWAY_NAME" &>/dev/null
  "$OPENSHELL" gateway select "$GATEWAY_NAME" &>/dev/null

  # Save namespace for reuse
  echo "$NAMESPACE" > "$PF_STATE"
fi

# --- Run the actual command ---
"$OPENSHELL" "$@"
