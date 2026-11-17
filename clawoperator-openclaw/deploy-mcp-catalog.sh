#!/usr/bin/env bash
#
# deploy-mcp-catalog.sh — populate the RHOAI dashboard's MCP catalog with the
# FantaCo MCP servers, and stand up the Kuadrant MCP gateway/broker.
#
# ############################################################################
# THERE ARE TWO SEPARATE MCP MECHANISMS. DO NOT CONFLATE THEM.
# ############################################################################
#
# 1. Gen AI studio -> MCP catalog (what you see in the dashboard)
#    Driven ENTIRELY by a ConfigMap:
#        gen-ai-aa-mcp-servers  in  redhat-ods-applications
#    It does NOT read MCPServerRegistration CRs. The gen-ai BFF logs
#        failed to get ConfigMap "gen-ai-aa-mcp-servers" namespace=redhat-ods-applications
#    until that ConfigMap exists, and the catalog stays empty no matter how
#    many registrations are Ready.
#
#    It is PLATFORM-LEVEL: one list for the whole cluster, served from
#    /gen-ai/api/v1/aaa/mcps?namespace=<anything> regardless of the selected
#    project. Per-namespace copies ARE NOT READ — this cluster already had a
#    gen-ai-aa-mcp-servers in agentic-user1 and it had never done anything.
#    Because it is platform-level, in-cluster URLs must be FULLY QUALIFIED
#    (svc.cluster.local), not bare service names.
#
#    Schema per key (RHOAI 3.5 docs): the key is a case-sensitive unique name,
#    the value is JSON with "url" and "description". The BFF fills in
#    transport and probes status itself.
#
# 2. Kuadrant MCP gateway / broker (MCPGatewayExtension + MCPServerRegistration)
#    A real MCP broker that fronts servers behind one endpoint and aggregates
#    their tools. Useful, and set up below, but it does NOT feed the dashboard
#    catalog. Verified: 3 servers, 23 tools, healthyServers=3.
#
# This script does both. --catalog-only does just (1), which is all you need
# for the dashboard view.
#
# For mechanism 2, the chain is:
#
#   Gateway (gateway.networking.k8s.io)         <- a listener for MCP traffic
#     + ReferenceGrant                          <- REQUIRED, see below
#     + MCPGatewayExtension                     <- turns that listener into an
#                                                  MCP broker (deploys a pod)
#   HTTPRoute  -> the MCP server's Service
#     + MCPServerRegistration -> that HTTPRoute <- what appears in the catalog
#
# THREE THINGS THAT WILL STOP YOU, all hit on rosa-tztnl 2026-11-17:
#
#  1. ReferenceGrant. If the MCPGatewayExtension and the Gateway are in
#     different namespaces, the extension sits at
#       Ready=False "ReferenceGrant required in openshift-ingress to allow
#                    cross-namespace reference from mcp-gateway"
#     This is almost certainly what killed the earlier attempt on this cluster:
#     the controller log shows an MCPGatewayExtension created 2026-11-16
#     21:35:48 and deleted 21:36:52, about a minute later.
#
#  2. spec.prefix must match ^[a-z0-9][a-z0-9_]*$ — UNDERSCORES, NOT HYPHENS.
#     "sales-order" is rejected; "sales_order" is fine. The HTTPRoute path may
#     still use a hyphen; only the registration prefix is restricted.
#
#  3. The FantaCo MCP servers speak streamable HTTP on /mcp. A bare GET returns
#     406 ("Not Acceptable") because it wants the MCP Accept header — that 406
#     means the server is UP, not broken. 404 on /, /sse and /messages.
#
# Usage:
#   ./deploy-mcp-catalog.sh --check        # report state, change nothing
#   ./deploy-mcp-catalog.sh                # create/apply, idempotent (seat 1)
#   SEAT=7 ./deploy-mcp-catalog.sh         # register a different seat
#   ./deploy-mcp-catalog.sh --remove       # tear the catalog down
#
# Registering one seat is deliberate: the catalog is a shared, cluster-scoped
# view, and 100 seats x 3 servers would be 300 near-identical entries. Seat 1
# acts as the exemplar. Point SEAT at whichever seat you demo from.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAT="${SEAT:-1}"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
NS="${NAMESPACE_PREFIX}${SEAT}"
GW_NS="${GW_NS:-openshift-ingress}"
GW_NAME="${GW_NAME:-mcp-gateway}"
EXT_NS="${EXT_NS:-mcp-gateway}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

MODE=apply
case "${1:-}" in
  --check)        MODE=check ;;
  --remove)       MODE=remove ;;
  --catalog-only) MODE=catalog ;;
  "")             ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

DASH_NS="${DASH_NS:-redhat-ods-applications}"

# ------------------------------------------------- AI hub -> MCP servers nav
# The nav item is gated by TWO things, and the second one is not documented
# anywhere obvious. From the dashboard bundle:
#
#   [MCP_CATALOG]: { featureFlags: ["mcpCatalog"],
#                    requiredComponents: [MODEL_REGISTRY] }
#
# So `mcpCatalog: true` in OdhDashboardConfig is NOT enough — the
# `modelregistry` component must also be Managed in the DataScienceCluster, or
# AI hub shows only "Models" and the MCP servers entry never renders. The same
# rule hides AI hub -> Catalog (MODEL_CATALOG has identical requiredComponents).
# Cost an hour on rosa-tztnl 2026-11-17 with both flags already set to true.
ensure_mcp_nav_prereqs() {
  bold "AI hub -> MCP servers nav prerequisites"
  local dsc flags
  dsc=$(oc get datasciencecluster -o name 2>/dev/null | head -1)
  [ -z "$dsc" ] && { bad "no DataScienceCluster found"; return 1; }

  for f in mcpCatalog mcpRegistry; do
    if [ "$(oc get odhdashboardconfig odh-dashboard-config -n "$DASH_NS" \
             -o jsonpath="{.spec.dashboardConfig.$f}" 2>/dev/null)" = true ]; then
      ok "$f = true"
    elif [ "$MODE" = check ]; then
      bad "$f is not true — nav item hidden"
    else
      oc patch odhdashboardconfig odh-dashboard-config -n "$DASH_NS" --type merge \
        -p "{\"spec\":{\"dashboardConfig\":{\"$f\":true}}}" >/dev/null 2>&1 \
        && ok "$f set to true" || bad "could not set $f"
    fi
  done

  local mr
  mr=$(oc get "$dsc" -o jsonpath='{.spec.components.modelregistry.managementState}' 2>/dev/null)
  if [ "$mr" = Managed ]; then
    ok "modelregistry = Managed (required by MCP_CATALOG)"
  elif [ "$MODE" = check ]; then
    bad "modelregistry = ${mr:-unset} — AI hub MCP servers + Catalog WILL BE HIDDEN"
  else
    oc patch "$dsc" --type merge \
      -p '{"spec":{"components":{"modelregistry":{"managementState":"Managed"}}}}' >/dev/null 2>&1 \
      && ok "modelregistry set to Managed" || bad "could not enable modelregistry"
    for i in $(seq 1 24); do
      [ "$(oc get modelregistries.components.platform.opendatahub.io \
            -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = True ] \
        && { ok "modelregistry component Ready"; break; }
      sleep 10
    done
  fi
  info "a browser refresh is needed for the nav change to show"
}

# ---------------------------------------------------------------- catalog
# Mechanism 1: the ConfigMap the Gen AI studio MCP catalog actually reads.
apply_catalog_configmap() {
  local ns="$1"
  bold "Gen AI studio MCP catalog (ConfigMap ${DASH_NS}/gen-ai-aa-mcp-servers)"
  cat <<EOF | oc apply -f - >/dev/null 2>&1 && ok "applied" || { bad "failed"; return 1; }
kind: ConfigMap
apiVersion: v1
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: ${DASH_NS}
data:
  FantaCo-Customer: |
    {
      "url": "http://mcp-customer-service.${ns}.svc.cluster.local:9001/mcp",
      "description": "FantaCo customer records: lookup, 360-degree profile and account history."
    }
  FantaCo-Product: |
    {
      "url": "http://mcp-product-service.${ns}.svc.cluster.local:9003/mcp",
      "description": "FantaCo product catalogue: search, pricing and stock levels."
    }
  FantaCo-Sales-Order: |
    {
      "url": "http://mcp-sales-order-service.${ns}.svc.cluster.local:9004/mcp",
      "description": "FantaCo sales orders: create, look up and track order status."
    }
EOF
  info "platform-level: shows under every project, so URLs are fully qualified"
  info "verify: curl .../gen-ai/api/v1/aaa/mcps?namespace=${ns}  -> status: healthy"
}

if [ "$MODE" = catalog ]; then
  ensure_mcp_nav_prereqs
  apply_catalog_configmap "$NS"
  exit 0
fi

oc whoami >/dev/null 2>&1 || { bad "not logged in"; exit 1; }
APPS=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
HOSTNAME="mcp.${APPS}"
CERT=$(oc get ingresscontroller default -n openshift-ingress-operator \
         -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null)

# name | service | port | prefix(no hyphens!) | tags | hint
SERVERS=(
  "fantaco-customer|mcp-customer-service|9001|customer|[\"crm\",\"demo\"]|FantaCo customer records: lookup, profile and account history."
  "fantaco-product|mcp-product-service|9003|product|[\"catalog\",\"demo\"]|FantaCo product catalogue: search, pricing and stock levels."
  "fantaco-sales-order|mcp-sales-order-service|9004|sales_order|[\"orders\",\"demo\"]|FantaCo sales orders: create, look up and track order status."
)

bold "MCP catalog — seat ${NS}"
info "gateway : ${GW_NS}/${GW_NAME}  host ${HOSTNAME}"
info "extension: ${EXT_NS}/${GW_NAME}"

# ---------------------------------------------------------------- remove
if [ "$MODE" = remove ]; then
  bold "Removing"
  for s in "${SERVERS[@]}"; do
    IFS='|' read -r name _svc _port prefix _tags _hint <<<"$s"
    oc delete mcpserverregistration "$name" -n "$NS" --ignore-not-found >/dev/null 2>&1
    oc delete httproute "mcp-${prefix//_/-}" -n "$NS" --ignore-not-found >/dev/null 2>&1
  done
  oc delete mcpgatewayextension "$GW_NAME" -n "$EXT_NS" --ignore-not-found >/dev/null 2>&1
  oc delete referencegrant mcp-gateway-extension -n "$GW_NS" --ignore-not-found >/dev/null 2>&1
  oc delete gateway "$GW_NAME" -n "$GW_NS" --ignore-not-found >/dev/null 2>&1
  oc delete cm gen-ai-aa-mcp-servers -n "$DASH_NS" --ignore-not-found >/dev/null 2>&1
  ok "removed"
  exit 0
fi

# ---------------------------------------------------------------- check
if [ "$MODE" = check ]; then
  ensure_mcp_nav_prereqs
  bold "State"
  if oc get cm gen-ai-aa-mcp-servers -n "$DASH_NS" >/dev/null 2>&1; then
    CM_N=$(oc get cm gen-ai-aa-mcp-servers -n "$DASH_NS" -o json 2>/dev/null \
           | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("data",{})))')
    ok "catalog ConfigMap present (${CM_N} entries)"
  else
    bad "catalog ConfigMap MISSING — the dashboard MCP catalog will be empty"
  fi
  oc get gateway "$GW_NAME" -n "$GW_NS" >/dev/null 2>&1 \
    && ok "Gateway programmed=$(oc get gateway "$GW_NAME" -n "$GW_NS" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')" \
    || bad "Gateway ${GW_NS}/${GW_NAME} missing"
  oc get referencegrant mcp-gateway-extension -n "$GW_NS" >/dev/null 2>&1 \
    && ok "ReferenceGrant present" || bad "ReferenceGrant missing (extension will not go Ready)"
  E=$(oc get mcpgatewayextension "$GW_NAME" -n "$EXT_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$E" = True ] && ok "MCPGatewayExtension Ready" \
    || bad "MCPGatewayExtension Ready=${E:-absent}: $(oc get mcpgatewayextension "$GW_NAME" -n "$EXT_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)"
  echo
  oc get mcpserverregistration -A 2>/dev/null | head -10
  exit 0
fi

ensure_mcp_nav_prereqs
apply_catalog_configmap "$NS"

# ---------------------------------------------------------------- 1. Gateway
bold "1/4  Gateway ${GW_NS}/${GW_NAME}"
cat <<EOF | oc apply -f - >/dev/null 2>&1 && ok "applied" || bad "failed"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GW_NAME}
  namespace: ${GW_NS}
spec:
  gatewayClassName: data-science-gateway-class
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      hostname: ${HOSTNAME}
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            group: ""
            name: ${CERT}
EOF
for i in $(seq 1 24); do
  [ "$(oc get gateway "$GW_NAME" -n "$GW_NS" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)" = True ] \
    && { ok "Programmed"; break; }
  sleep 10
done

# ------------------------------------------------- 2. ReferenceGrant + ext
bold "2/4  ReferenceGrant + MCPGatewayExtension"
# Without this the extension never leaves ReferenceGrantRequired.
cat <<EOF | oc apply -f - >/dev/null 2>&1 && ok "ReferenceGrant" || bad "ReferenceGrant failed"
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: mcp-gateway-extension
  namespace: ${GW_NS}
spec:
  from:
    - group: mcp.kuadrant.io
      kind: MCPGatewayExtension
      namespace: ${EXT_NS}
  to:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: ${GW_NAME}
EOF
cat <<EOF | oc apply -f - >/dev/null 2>&1 && ok "MCPGatewayExtension" || bad "extension failed"
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPGatewayExtension
metadata:
  name: ${GW_NAME}
  namespace: ${EXT_NS}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: ${GW_NAME}
    namespace: ${GW_NS}
    sectionName: https
  httpRouteManagement: Enabled
EOF
for i in $(seq 1 24); do
  S=$(oc get mcpgatewayextension "$GW_NAME" -n "$EXT_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  [ "$S" = True ] && { ok "extension Ready (broker pod up)"; break; }
  printf '  [%02d/24] %s\r' "$i" "$(oc get mcpgatewayextension "$GW_NAME" -n "$EXT_NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)"
  sleep 10
done
echo

# ------------------------------------------- 3. HTTPRoutes + registrations
bold "3/4  Registering FantaCo MCP servers from ${NS}"
for s in "${SERVERS[@]}"; do
  IFS='|' read -r name svc port prefix tags hint <<<"$s"
  route="mcp-${prefix//_/-}"
  cat <<EOF | oc apply -f - >/dev/null 2>&1 || { bad "$name"; continue; }
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${route}
  namespace: ${NS}
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: ${GW_NAME}
      namespace: ${GW_NS}
      sectionName: https
  hostnames: ["${HOSTNAME}"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /${prefix//_/-}}}]
      backendRefs: [{name: ${svc}, port: ${port}}]
---
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPServerRegistration
metadata:
  name: ${name}
  namespace: ${NS}
spec:
  targetRef: {group: gateway.networking.k8s.io, kind: HTTPRoute, name: ${route}}
  path: /mcp
  prefix: ${prefix}
  state: Enabled
  category: ["FantaCo"]
  tags: ${tags}
  hint: "${hint}"
EOF
  ok "$name  (prefix ${prefix}, ${svc}:${port})"
done

# ---------------------------------------------------------------- 4. verify
bold "4/4  Verify — count tools, do not trust Ready alone"
for i in $(seq 1 18); do
  READY=$(oc get mcpserverregistration -n "$NS" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c True)
  [ "$READY" -ge "${#SERVERS[@]}" ] && break
  printf '  [%02d/18] %s/%s ready\r' "$i" "$READY" "${#SERVERS[@]}"
  sleep 10
done
echo
oc get mcpserverregistration -n "$NS" 2>&1
TOOLS=$(oc get mcpserverregistration -n "$NS" -o jsonpath='{range .items[*]}{.status.tools}{"+"}{end}' 2>/dev/null)
echo
oc logs deploy/mcp-gateway -n "$EXT_NS" --tail=60 2>/dev/null \
  | grep 'Server validation completed' | tail -1
echo
echo "  Dashboard: Gen AI studio → MCP catalog"
echo "  A registration stuck at \"mcp server is not present in gateway yet\" for"
echo "  more than ~90s usually means the HTTPRoute did not attach — check"
echo "  'oc get httproute -n ${NS}' for Accepted/ResolvedRefs=True."
