#!/usr/bin/env bash

# Lists all MCP servers discovered in the current OpenShift namespace.
# Shows service name, port, direct URL, and whether a proxy route exists.
#
# Usage (from repository root):
#   ./scripts/list-mcp-servers.sh           # table view
#   ./scripts/list-mcp-servers.sh --json    # JSON output

set -euo pipefail

if [ -t 1 ]; then
  BOLD='\033[1m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' NC=''
fi

JSON_MODE=false
for arg in "$@"; do
  case "$arg" in
    --json|-j) JSON_MODE=true ;;
    --help|-h)
      echo "Usage: $0 [--json]"
      echo ""
      echo "  --json, -j   Output as JSON array"
      echo "  (default)    Pretty-printed table"
      exit 0
      ;;
  esac
done

if ! command -v oc >/dev/null 2>&1; then
  echo "Required command not found: oc" >&2
  exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "You are not logged in to OpenShift via oc." >&2
  exit 1
fi

NAMESPACE="$(oc project -q 2>/dev/null || true)"
if [[ -z "$NAMESPACE" ]]; then
  echo "Unable to determine the current namespace." >&2
  exit 1
fi

# Fetch services and proxy config in parallel
SERVICES_JSON="$(mktemp)"
PROXY_TEMPLATE="$(mktemp)"
trap 'rm -f "$SERVICES_JSON" "$PROXY_TEMPLATE"' EXIT

oc get svc -n "$NAMESPACE" -o json > "$SERVICES_JSON"

# Grab the proxy nginx template if it exists (ignore errors if not deployed)
oc get configmap openclaw-proxy-config -n "$NAMESPACE" \
  -o jsonpath='{.data.default\.conf\.template}' > "$PROXY_TEMPLATE" 2>/dev/null || true

python3 - "$SERVICES_JSON" "$PROXY_TEMPLATE" "$NAMESPACE" "$JSON_MODE" <<'PY'
import json
import re
import sys

services_path, proxy_path, namespace, json_mode = sys.argv[1:]
json_mode = json_mode == "true"

pattern = re.compile(r"^mcp-(.+)-service$")

with open(services_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

proxy_template = ""
try:
    with open(proxy_path, "r", encoding="utf-8") as fh:
        proxy_template = fh.read()
except (FileNotFoundError, OSError):
    pass

servers = []
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
    direct_url = f"http://{name}:{port}/mcp"
    proxy_url = f"http://openclaw-proxy:8080/mcp-{server_key}/mcp"
    has_proxy = f"location /mcp-{server_key}/" in proxy_template

    servers.append({
        "key": server_key,
        "service": name,
        "port": port,
        "directUrl": direct_url,
        "proxyUrl": proxy_url,
        "proxyConfigured": has_proxy,
    })

servers.sort(key=lambda s: s["service"])

if json_mode:
    print(json.dumps(servers, indent=2))
else:
    if not servers:
        print(f"No MCP services found in namespace '{namespace}'.")
        sys.exit(0)

    print(f"\nMCP servers in namespace: {namespace}")
    print(f"{'':->70}")
    print(f"  {'Key':<16} {'Service':<28} {'Port':<6} {'Proxy'}")
    print(f"{'':->70}")
    for s in servers:
        proxy_status = "\033[0;32m✔\033[0m" if s["proxyConfigured"] else "\033[0;33m✘\033[0m"
        print(f"  {s['key']:<16} {s['service']:<28} {s['port']:<6} {proxy_status}")
    print(f"{'':->70}")
    print(f"  {len(servers)} server(s) found\n")

    print("  Direct URLs:")
    for s in servers:
        print(f"    {s['key']:<16} {s['directUrl']}")

    proxied = [s for s in servers if s["proxyConfigured"]]
    unproxied = [s for s in servers if not s["proxyConfigured"]]

    if proxied:
        print("\n  Proxy URLs:")
        for s in proxied:
            print(f"    {s['key']:<16} {s['proxyUrl']}")
    if unproxied:
        print(f"\n  Run /fantaco:openclaw-inject-mcp-servers to add proxy routes for: {', '.join(s['key'] for s in unproxied)}")
    print()
PY
