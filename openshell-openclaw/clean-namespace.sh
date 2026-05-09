#!/usr/bin/env bash
# clean-namespace.sh
#
# Removes all student-user OpenShell/OpenClaw resources so scripts 1-6
# can be re-run from scratch. Does NOT remove cluster-admin resources
# created by 0-cluster-admin-setup.sh.
#
# Usage:
#   ./clean-namespace.sh                    # current oc project
#   ./clean-namespace.sh <namespace>        # single namespace
#   ./clean-namespace.sh ns1,ns2,ns3        # comma-separated list
#   ./clean-namespace.sh "agentic-user*"    # wildcard pattern
#
# Optional:
#   GATEWAY_PORT  local port for gateway (default: 8081)
#   GATEWAY_NAME  CLI gateway name (default: local)

set -euo pipefail

GATEWAY_PORT="${GATEWAY_PORT:-8081}"
GATEWAY_NAME="${GATEWAY_NAME:-local}"
TEMP_PF_PID=""

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

cleanup_temp_pf() {
  if [ -n "$TEMP_PF_PID" ] && kill -0 "$TEMP_PF_PID" 2>/dev/null; then
    kill "$TEMP_PF_PID" 2>/dev/null || true
    TEMP_PF_PID=""
  fi
}
trap cleanup_temp_pf EXIT

# --- Resolve namespace list ---
if [ -z "${1:-}" ]; then
  # No argument: use current oc project
  NS="$(oc project -q 2>/dev/null || true)"
  if [ -z "$NS" ]; then
    echo "ERROR: No namespace given and no oc project set."
    echo "Usage: $0 <namespace>"
    exit 1
  fi
  NAMESPACES=("$NS")
else
  # Resolve comma-separated + wildcard patterns (same as 0-cluster-admin-setup.sh)
  ALL_NAMESPACES=$(oc get namespaces -o jsonpath='{.items[*].metadata.name}')
  RESOLVED=()
  IFS=',' read -ra PATTERNS <<< "$1"
  for pattern in "${PATTERNS[@]}"; do
    pattern=$(echo "$pattern" | xargs)
    matched=false
    for ns in $ALL_NAMESPACES; do
      case "$ns" in
        $pattern) RESOLVED+=("$ns"); matched=true ;;
      esac
    done
    if [ "$matched" = false ]; then
      echo "WARNING: No namespaces matched pattern '$pattern'"
    fi
  done
  NAMESPACES=($(printf '%s\n' "${RESOLVED[@]}" | sort -u))
  if [ ${#NAMESPACES[@]} -eq 0 ]; then
    echo "ERROR: No namespaces matched."
    exit 1
  fi
fi

echo "============================================"
echo "  OpenShell Namespace Cleanup"
echo "============================================"
echo ""
echo "Namespaces to clean (${#NAMESPACES[@]}):"
for ns in "${NAMESPACES[@]}"; do
  echo "  - $ns"
done
echo ""
echo "This removes student-user resources (scripts 1-6)."
echo "Cluster-admin resources (script 0) are preserved."
echo ""

# --- Step 1: Kill OpenClaw UI port-forward ---
echo "--- Stopping OpenClaw UI port-forward ---"
lsof -ti :18789 2>/dev/null | xargs kill 2>/dev/null || true
echo "Done."
echo ""

# --- Per-namespace cleanup ---
clean_namespace() {
  local NS="$1"
  echo "=== Cleaning namespace: $NS ==="

  # Check if the gateway pod is running (needed for sandbox CR deletion)
  GATEWAY_POD=$(oc get pods -l app.kubernetes.io/name=openshell -n "$NS" --no-headers 2>/dev/null | grep -i running | head -1 | awk '{print $1}' || true)

  if [ -n "$GATEWAY_POD" ]; then
    # Gateway is running — ensure we have a port-forward to delete sandboxes
    echo "  Gateway pod found: $GATEWAY_POD"

    # Kill any existing port-forward on the gateway port
    lsof -ti :"$GATEWAY_PORT" 2>/dev/null | xargs kill 2>/dev/null || true
    sleep 1

    # Start a temporary port-forward
    echo "  Starting temporary port-forward..."
    kubectl -n "$NS" port-forward "svc/openshell" "${GATEWAY_PORT}:8080" &>/dev/null &
    TEMP_PF_PID=$!
    sleep 3

    if kill -0 "$TEMP_PF_PID" 2>/dev/null; then
      # Ensure CLI gateway registration points to our port-forward
      openshell gateway remove "$GATEWAY_NAME" 2>/dev/null || true
      openshell gateway add "http://127.0.0.1:${GATEWAY_PORT}" --local --name "$GATEWAY_NAME" 2>/dev/null || true
      openshell gateway select "$GATEWAY_NAME" 2>/dev/null || true

      # Give the gateway time to reconcile existing Sandbox CRs
      echo "  Waiting for gateway to discover sandboxes..."
      sleep 15

      # Delete all sandboxes via CLI (this removes the Sandbox CR properly)
      echo "  Deleting sandboxes via CLI..."
      SANDBOXES=$(openshell sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' || true)
      if [ -n "$SANDBOXES" ]; then
        for sb in $SANDBOXES; do
          openshell sandbox delete "$sb" 2>/dev/null && echo "    Deleted sandbox: $sb" || true
        done
      else
        echo "    No sandboxes found via CLI."
      fi

      # Wait for sandbox pods to terminate
      echo "  Waiting for sandbox pods to terminate..."
      for i in $(seq 1 12); do
        REMAINING=$(oc get pods -l app=openclaw -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$REMAINING" = "0" ]; then
          break
        fi
        sleep 5
      done
      echo "    Sandbox pods cleared."

      # Kill the temporary port-forward (suppress "Terminated" message)
      kill "$TEMP_PF_PID" 2>/dev/null || true
      wait "$TEMP_PF_PID" 2>/dev/null || true
      TEMP_PF_PID=""
    else
      echo "    Port-forward failed — will force-delete pods."
      TEMP_PF_PID=""
    fi
  else
    echo "  No gateway pod running."
  fi

  # Fallback: force-delete any remaining sandbox pods
  REMAINING_PODS=$(oc get pods -l app=openclaw -n "$NS" --no-headers 2>/dev/null | awk '{print $1}' || true)
  if [ -n "$REMAINING_PODS" ]; then
    echo "  Force-deleting remaining sandbox pods..."
    for pod in $REMAINING_PODS; do
      echo "    Deleting pod: $pod"
      oc delete pod "$pod" -n "$NS" --grace-period=30 2>/dev/null || true
      oc delete service "$pod" -n "$NS" 2>/dev/null || true
    done
    echo "  Waiting for pods to terminate..."
    for i in $(seq 1 12); do
      COUNT=$(oc get pods -l app=openclaw -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [ "$COUNT" = "0" ]; then
        break
      fi
      sleep 5
    done
    echo "    Pods cleared."
  fi

  # Kill any remaining port-forward on the gateway port
  lsof -ti :"$GATEWAY_PORT" 2>/dev/null | xargs kill 2>/dev/null || true

  # Uninstall Helm release
  echo "  Uninstalling Helm release..."
  if helm status openshell -n "$NS" &>/dev/null; then
    helm uninstall openshell -n "$NS" --wait --timeout 60s 2>/dev/null || true
    echo "    Helm release removed."
  else
    echo "    No Helm release found."
  fi

  # Wait for Helm-managed pods to terminate
  echo "  Waiting for gateway pod to terminate..."
  kubectl wait --for=delete pod -l app.kubernetes.io/name=openshell -n "$NS" --timeout=60s 2>/dev/null || true
  echo "    Done."

  echo "  Namespace $NS cleaned."
  echo ""
}

for ns in "${NAMESPACES[@]}"; do
  clean_namespace "$ns"
done

# --- Remove CLI state (once, not per-namespace) ---
echo "--- Removing OpenShell CLI state ---"
openshell provider delete anthropic 2>/dev/null || true
openshell provider delete openai 2>/dev/null || true
openshell provider delete vllm 2>/dev/null || true
openshell gateway remove "$GATEWAY_NAME" 2>/dev/null || true
echo "Done."
echo ""

echo "============================================"
echo "  Cleanup complete!"
echo "============================================"
echo ""
echo "Re-run the deployment:"
for ns in "${NAMESPACES[@]}"; do
  echo "  oc project $ns"
  echo "  ./1-install-openshell.sh"
  echo "  ./2-port-forward-openshell.sh"
  echo "  ./3-deploy-openclaw-sandbox.sh"
  echo "  ./4-configure-openclaw.sh --bot-token <token>"
  echo "  ./5-port-forward-openclaw.sh"
  echo "  ./6-open-openclaw.sh"
  echo ""
done
