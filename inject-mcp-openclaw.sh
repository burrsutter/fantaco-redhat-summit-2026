#!/usr/bin/env bash

set -euo pipefail

# Temporary helper for patching an OpenClaw pod in the current namespace.
# This intentionally edits the live pod filesystem, which may be ephemeral.
# That is acceptable here because the goal is a quick, repeatable workaround.

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

cleanup() {
  rm -f "${PODS_JSON:-}" "${SERVICES_JSON:-}" "${NETPOL_JSON:-}" "${PROXY_CM:-}"
}

select_one() {
  local prompt="$1"
  shift
  local options=("$@")

  if [[ ${#options[@]} -eq 0 ]]; then
    echo "No options available for: $prompt" >&2
    exit 1
  fi

  if [[ ${#options[@]} -eq 1 ]]; then
    echo "${options[0]}"
    return 0
  fi

  echo "$prompt" >&2
  local i=1
  for option in "${options[@]}"; do
    printf "  %d) %s\n" "$i" "$option" >&2
    ((i++))
  done

  while true; do
    printf "Enter choice [1-%d]: " "${#options[@]}" >&2
    read -r reply </dev/tty
    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#options[@]} )); then
      echo "${options[reply-1]}"
      return 0
    fi
    echo "Invalid selection." >&2
  done
}

require_cmd oc
require_cmd python3

if ! oc whoami >/dev/null 2>&1; then
  echo "You are not logged in to OpenShift/Kubernetes via oc." >&2
  exit 1
fi

NAMESPACE="$(oc project -q 2>/dev/null || true)"
if [[ -z "$NAMESPACE" ]]; then
  echo "Unable to determine the current namespace from 'oc project -q'." >&2
  exit 1
fi

echo "Current namespace: $NAMESPACE"

PODS_JSON="$(mktemp)"
SERVICES_JSON="$(mktemp)"
NETPOL_JSON="$(mktemp)"
PROXY_CM="$(mktemp)"
trap cleanup EXIT

oc get pods -n "$NAMESPACE" -o json > "$PODS_JSON"
oc get svc -n "$NAMESPACE" -o json > "$SERVICES_JSON"

# Find candidate OpenClaw pods dynamically in the current namespace.
# We match on pod name or label values containing "openclaw" so the script
# can target any OpenClaw instance it finds without assuming a single label.
OPENCLAW_PODS_OUTPUT=$(python3 - "$PODS_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

matches = []
for item in data.get("items", []):
    metadata = item.get("metadata", {})
    status = item.get("status", {})
    phase = status.get("phase", "")
    name = metadata.get("name", "")
    labels = metadata.get("labels", {}) or {}

    haystacks = [name.lower()]
    haystacks.extend(str(v).lower() for v in labels.values())

    if phase != "Running":
        continue
    if any("openclaw" in value for value in haystacks):
        matches.append(name)

for name in sorted(set(matches)):
    print(name)
PY
)
OPENCLAW_PODS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && OPENCLAW_PODS+=("$line")
done <<< "$OPENCLAW_PODS_OUTPUT"

if [[ ${#OPENCLAW_PODS[@]} -eq 0 ]]; then
  echo "No running OpenClaw pods found in namespace '$NAMESPACE'." >&2
  exit 1
fi

SELECTED_POD="$(select_one "Select the OpenClaw pod to patch:" "${OPENCLAW_PODS[@]}")"
echo "Selected pod: $SELECTED_POD"

# Discover MCP services generically from service names that follow the in-cluster
# convention mcp-<domain>-service. This supports current servers and future ones
# without hardcoding customer/finance/product/sales-orders/hr-recruiting.
MCP_CHOICES_OUTPUT=$(python3 - "$SERVICES_JSON" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^mcp-(.+)-service$")

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

rows = []
for item in data.get("items", []):
    metadata = item.get("metadata", {})
    spec = item.get("spec", {})
    name = metadata.get("name", "")
    match = pattern.match(name)
    if not match:
        continue

    ports = spec.get("ports", []) or []
    if not ports:
        continue

    port = ports[0].get("port")
    if port is None:
        continue

    server_key = match.group(1)
    url = f"http://{name}:{port}/mcp"
    rows.append((server_key, name, port, url))

for server_key, name, port, url in sorted(rows, key=lambda row: row[1]):
    print(f"{server_key}|{name}|{port}|{url}")
PY
)
MCP_CHOICES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && MCP_CHOICES+=("$line")
done <<< "$MCP_CHOICES_OUTPUT"

if [[ ${#MCP_CHOICES[@]} -eq 0 ]]; then
  echo "No MCP services found in namespace '$NAMESPACE'." >&2
  exit 1
fi

DISPLAY_CHOICES=()
for entry in "${MCP_CHOICES[@]}"; do
  IFS='|' read -r server_key service_name service_port service_url <<< "$entry"
  DISPLAY_CHOICES+=("${server_key} (${service_name} -> ${service_url})")
done

SELECTED_DISPLAY="$(select_one "Select one MCP server to inject:" "${DISPLAY_CHOICES[@]}")"

SELECTED_ENTRY=""
for i in "${!DISPLAY_CHOICES[@]}"; do
  if [[ "${DISPLAY_CHOICES[i]}" == "$SELECTED_DISPLAY" ]]; then
    SELECTED_ENTRY="${MCP_CHOICES[i]}"
    break
  fi
done

IFS='|' read -r SERVER_KEY SERVICE_NAME SERVICE_PORT SERVICE_URL <<< "$SELECTED_ENTRY"

# The proxy URL is the path OpenClaw will use to reach the MCP server
PROXY_URL="http://openclaw-proxy:8080/mcp-${SERVER_KEY}/mcp"

echo "Selected MCP server:"
echo "  Key: $SERVER_KEY"
echo "  Service: $SERVICE_NAME (direct: $SERVICE_URL)"
echo "  Proxy URL: $PROXY_URL"

# ---------------------------------------------------------------------------
# Section A: Patch the proxy NetworkPolicy to allow in-cluster egress
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1/3: Patching proxy NetworkPolicy ---"
oc get networkpolicy openclaw-proxy-egress -n "$NAMESPACE" -o json > "$NETPOL_JSON"

python3 - "$NETPOL_JSON" <<'PY'
import json
import sys

netpol_path = sys.argv[1]

with open(netpol_path, "r", encoding="utf-8") as fh:
    policy = json.load(fh)

spec = policy.get("spec", {})
egress_rules = spec.get("egress", [])

# Check if a podSelector:{} rule already exists
already_present = False
for rule in egress_rules:
    to_list = rule.get("to", [])
    # A rule with just podSelector:{} and no ports means "allow all in-namespace"
    if any(
        peer.get("podSelector") == {} and len(peer) == 1
        for peer in to_list
    ):
        already_present = True
        break

if already_present:
    print("NetworkPolicy already allows in-cluster egress — skipping.")
else:
    egress_rules.append({"to": [{"podSelector": {}}]})
    spec["egress"] = egress_rules
    policy["spec"] = spec
    with open(netpol_path, "w", encoding="utf-8") as fh:
        json.dump(policy, fh, indent=2)
        fh.write("\n")
    print("Added in-cluster egress rule to NetworkPolicy.")
PY

oc apply -n "$NAMESPACE" -f "$NETPOL_JSON"
echo "NetworkPolicy openclaw-proxy-egress updated."

# ---------------------------------------------------------------------------
# Section B: Patch the proxy ConfigMap (nginx template) with MCP location block
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2/3: Patching proxy ConfigMap ---"
oc get configmap openclaw-proxy-config -n "$NAMESPACE" -o json > "$PROXY_CM"

python3 - "$PROXY_CM" "$SERVER_KEY" "$SERVICE_NAME" "$SERVICE_PORT" "$NAMESPACE" <<'PY'
import json
import sys

cm_path, server_key, service_name, service_port, namespace = sys.argv[1:]

# Nginx resolver does not use /etc/resolv.conf search domains, so we must
# use the fully-qualified in-cluster hostname for dynamic upstream resolution.
service_fqdn = f"{service_name}.{namespace}.svc.cluster.local"
var_name = f"upstream_mcp_{server_key.replace('-', '_')}"

with open(cm_path, "r", encoding="utf-8") as fh:
    cm = json.load(fh)

template = cm["data"]["default.conf.template"]
location_marker = f"location /mcp-{server_key}/"

if location_marker in template:
    print(f"Nginx location block for /mcp-{server_key}/ already exists — skipping.")
else:
    location_block = f"""
    # MCP: {server_key}
    location /mcp-{server_key}/ {{
        set ${var_name} {service_fqdn};
        rewrite ^/mcp-{server_key}/(.*) /$1 break;
        proxy_pass http://${var_name}:{service_port};
        proxy_set_header Host {service_name};
        proxy_set_header X-Forwarded-For "";
    }}
"""
    # Insert before the final closing brace of the server block
    last_brace = template.rfind("}")
    if last_brace == -1:
        raise SystemExit("Could not find closing brace in nginx template")
    template = template[:last_brace] + location_block + template[last_brace:]
    cm["data"]["default.conf.template"] = template

    with open(cm_path, "w", encoding="utf-8") as fh:
        json.dump(cm, fh, indent=2)
        fh.write("\n")
    print(f"Injected nginx location block for /mcp-{server_key}/ (upstream: {service_fqdn}).")
PY

oc apply -n "$NAMESPACE" -f "$PROXY_CM"
echo "ConfigMap openclaw-proxy-config updated."

# ---------------------------------------------------------------------------
# Section C: Restart the proxy pod and wait for readiness
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3/3: Restarting proxy pod ---"
oc delete pod -n "$NAMESPACE" -l app=openclaw-proxy
echo "Waiting for proxy to become ready..."
oc rollout status deployment/openclaw-proxy -n "$NAMESPACE" --timeout=60s
echo "Proxy pod restarted and ready."

# ---------------------------------------------------------------------------
# NOTE: Previous versions of this script injected a top-level "mcpServers"
# key into openclaw.json. OpenClaw does not recognize that key and it causes
# config validation to fail. The proxy routing set up above is sufficient —
# MCP servers are reachable at http://openclaw-proxy:8080/mcp-<key>/mcp.
#
# TODO: Once the correct OpenClaw config schema for registering MCP tool
# providers is known (likely under agents.list[].tools or a plugin config),
# add native registration here so tools appear in OpenClaw without raw curl.
# ---------------------------------------------------------------------------

echo ""
echo "Done. Proxy routing for MCP server '${SERVER_KEY}' is now active."
echo ""
echo "  Route: /mcp-${SERVER_KEY}/ -> ${SERVICE_NAME}:${SERVICE_PORT}"
echo "  URL:   ${PROXY_URL}"
echo ""
echo "Verify proxy routing:"
echo "  oc get networkpolicy openclaw-proxy-egress -n $NAMESPACE -o yaml | grep podSelector"
echo "  oc get configmap openclaw-proxy-config -n $NAMESPACE -o jsonpath='{.data.default\\.conf\\.template}' | grep 'mcp-${SERVER_KEY}'"
echo ""
echo "Test MCP through proxy (from any pod in the namespace):"
echo "  oc exec -n $NAMESPACE $SELECTED_POD -c gateway -- curl -s ${PROXY_URL} \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}'"
