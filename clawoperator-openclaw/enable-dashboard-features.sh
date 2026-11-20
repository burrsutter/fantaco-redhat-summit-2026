#!/usr/bin/env bash
# enable-dashboard-features.sh — turn on the RHOAI dashboard pages the demo uses.
#
# WHY THIS EXISTS. Every one of these flags defaults to FALSE in
# OdhDashboardConfig, and until 2026-11-18 **no script set them**. They were
# applied by hand on rosa-wv5l4, which meant:
#   - a scripted reinstall came up without Gen AI studio, and
#   - the GitOps deployment came up without it too.
# Enabling the DataScienceCluster components is NOT sufficient; the dashboard
# reads these flags separately.
#
# Flags set here, and what each one is for:
#   genAiStudio            Gen AI studio section (Playground, AI asset endpoints)
#   externalModels         External models page — where the MaaS model appears
#   modelAsService         Models-as-a-Service pages
#   promptManagement       Prompt registry (needs the RHOAI MLflow CR as well —
#                          see deploy-rhoai-mlflow.sh, or Save prompt 503s)
#   observabilityDashboard Observe & monitor → Dashboard (needs the metrics
#                          stack — see deploy-rhoai-observability.sh)
#   mcpCatalog             AI hub → MCP servers
#   mcpRegistry            MCP registry. Gated on requiredComponents: [MLFLOW],
#                          NOT MODEL_REGISTRY — so it also wants the MLflow CR
#                          from deploy-rhoai-mlflow.sh (found on sv68v).
#
# TWO TRAPS:
#  1. **The dashboard caches the CR.** Changing a flag does nothing visible
#     until `oc rollout restart deploy/rhods-dashboard`, and then the browser
#     needs a refresh. This script does the restart.
#  2. **Most of these flags gate a page whose BACKEND is a separate concern.**
#     The flag reveals the nav item; something else has to make the page work:
#       mcpCatalog             -> modelregistry: Managed  (requiredComponents)
#       mcpRegistry            -> MLFLOW, i.e. the MLflow CR
#       promptManagement       -> the MLflow CR (deploy-rhoai-mlflow.sh)
#       observabilityDashboard -> a real metrics stack, and its nav entry also
#                                 carries a customCondition on dsciStatus
#     Enabling a flag without its backend exposes a broken page rather than a
#     working one. This script sets all seven because the scripts path deploys
#     all the backends; do not copy the list somewhere that does not.
#
#     For mcpCatalog specifically the bundle
#     declares `requiredComponents: [MODEL_REGISTRY]`. Same rule hides
#     AI hub → Catalog. deploy-mcp-catalog.sh asserts this too.
#
# Usage:
#   ./enable-dashboard-features.sh           # set the flags and restart
#   ./enable-dashboard-features.sh --check   # report, change nothing

set -euo pipefail

NS=redhat-ods-applications
CFG=odh-dashboard-config
FLAGS=(genAiStudio externalModels modelAsService promptManagement
       observabilityDashboard mcpCatalog mcpRegistry)
MODE=apply
case "${1:-}" in
  --check) MODE=check ;;
  "")      ;;
  *)       echo "Unknown flag: $1" >&2; exit 1 ;;
esac

command -v oc >/dev/null || { echo "Missing oc" >&2; exit 1; }
oc whoami >/dev/null

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; RST=$'\033[0m'
ok()   { echo "  ${GREEN}✓${RST} $*"; }
bad()  { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YEL}!${RST} $*"; }

report() {
  echo "── dashboard feature flags ─────────────────────────"
  local json
  json=$(oc get odhdashboardconfig "$CFG" -n "$NS" -o json 2>/dev/null) || {
    bad "OdhDashboardConfig/$CFG not found in $NS"; return 1; }
  for f in "${FLAGS[@]}"; do
    v=$(printf '%s' "$json" | python3 -I -c "
import json,sys
print(json.load(sys.stdin)['spec'].get('dashboardConfig',{}).get('$f'))")
    [[ "$v" == "True" ]] && ok "$f" || bad "$f = $v"
  done
  local mr
  mr=$(oc get datasciencecluster -o jsonpath='{.items[0].spec.components.modelregistry.managementState}' 2>/dev/null)
  [[ "$mr" == "Managed" ]] && ok "modelregistry: Managed (required by mcpCatalog)" \
                           || bad "modelregistry: ${mr:-unset} — AI hub nav will be missing"
}

if [[ "$MODE" == check ]]; then report; exit 0; fi

echo "── setting flags ───────────────────────────────────"
PATCH=$(python3 -I -c "
import json
flags='${FLAGS[*]}'.split()
print(json.dumps({'spec':{'dashboardConfig':{f: True for f in flags}}}))")
oc patch odhdashboardconfig "$CFG" -n "$NS" --type=merge -p "$PATCH" >/dev/null
ok "patched ${#FLAGS[@]} flags to true"

# mcpCatalog/MODEL_CATALOG are gated on this component, not just the flag.
DSC=$(oc get datasciencecluster -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$DSC" ]]; then
  oc patch datasciencecluster "$DSC" --type=merge \
    -p '{"spec":{"components":{"modelregistry":{"managementState":"Managed"}}}}' >/dev/null 2>&1 \
    && ok "modelregistry set Managed" || warn "could not patch modelregistry"
fi

echo "── restarting the dashboard (it caches the CR) ─────"
oc rollout restart deploy/rhods-dashboard -n "$NS" >/dev/null 2>&1 || true
oc rollout status deploy/rhods-dashboard -n "$NS" --timeout=300s >/dev/null 2>&1 \
  && ok "dashboard restarted" || warn "dashboard rollout did not settle in 300s"

echo
report
echo
echo "Refresh the browser — the nav is rendered client-side and will not"
echo "update on its own."
