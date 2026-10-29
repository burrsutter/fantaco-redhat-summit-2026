#!/usr/bin/env bash
# Compatibility entry point for the PostgreSQL-backed OpenShift broker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/deploy-broker-pg-ocp.sh" "$@"
