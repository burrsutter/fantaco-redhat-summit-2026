#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <user-number|admin> [console-url]"
  echo "Example: $0 1"
  echo "Example: $0 admin"
  echo "Example: $0 1 https://console-openshift-console.apps.ocp.h76fw.sandbox5557.opentlc.com/"
  exit 1
fi

USER_ARG="$1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE"
  exit 1
fi

source "$ENV_FILE"

CONSOLE_URL="${2:-${OPENSHIFT_CONSOLE_URL:-}}"

if [[ -z "$CONSOLE_URL" ]]; then
  echo "Error: No console URL provided and OPENSHIFT_CONSOLE_URL not set in .env"
  exit 1
fi

# Derive API server URL from console URL
# https://console-openshift-console.apps.ocp.h76fw.sandbox5557.opentlc.com/
# → https://api.ocp.h76fw.sandbox5557.opentlc.com:6443
API_SERVER=$(echo "$CONSOLE_URL" | sed 's|https://console-openshift-console\.apps\.|https://api.|' | sed 's|/$||')
API_SERVER="${API_SERVER}:6443"

if [[ "$USER_ARG" == "admin" ]]; then
  if [[ -z "${ADMIN_USER:-}" || -z "${ADMIN_PASSWORD:-}" ]]; then
    echo "Error: ADMIN_USER and ADMIN_PASSWORD must be set in .env"
    exit 1
  fi
  echo "Logging in as ${ADMIN_USER} to ${API_SERVER}"
  oc login -u "$ADMIN_USER" -p "$ADMIN_PASSWORD" --server="$API_SERVER"
else
  if [[ -z "${STUDENT_OPENSHIFT_PASSWORD:-}" ]]; then
    echo "Error: STUDENT_OPENSHIFT_PASSWORD not set in .env"
    exit 1
  fi
  echo "Logging in as user${USER_ARG} to ${API_SERVER}"
  oc login -u "user${USER_ARG}" -p "$STUDENT_OPENSHIFT_PASSWORD" --server="$API_SERVER"

  echo "Switching to project agentic-user${USER_ARG}"
  oc project "agentic-user${USER_ARG}"
fi
