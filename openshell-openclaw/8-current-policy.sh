#!/usr/bin/env bash
# 8-current-policy.sh
#
# Displays a concise summary of the active sandbox network policy:
# which hosts are reachable and what HTTP methods are allowed.
#
# Run before and after policy add/remove scripts to see the difference.
#
# Usage:
#   ./8-current-policy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSHELL="${SCRIPT_DIR}/openshell.sh"

# --- Colors ---
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

# --- Resolve sandbox name ---
strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }
SANDBOX_NAME=$("$OPENSHELL" sandbox list 2>/dev/null | strip_ansi | grep -v '^NAME' | awk '{print $1}' | head -1)
if [ -z "$SANDBOX_NAME" ]; then
  echo "ERROR: No sandbox found."
  exit 1
fi

# --- Fetch live policy from sandbox ---
POLICY=$("$OPENSHELL" policy get "$SANDBOX_NAME" --full 2>/dev/null)

# Extract version info
VERSION=$(echo "$POLICY" | grep '^Version:' | awk '{print $2}')
STATUS=$(echo "$POLICY" | grep '^Status:' | awk '{print $2}')

# Extract the YAML portion (after the --- separator)
YAML=$(echo "$POLICY" | sed -n '/^---$/,$ p' | tail -n +2)

echo ""
echo -e "${BOLD}============================================${RESET}"
echo -e "${BOLD}  Sandbox Network Policy${RESET} ${DIM}(v${VERSION} — ${STATUS})${RESET}"
echo -e "${BOLD}  Sandbox:${RESET} ${CYAN}${SANDBOX_NAME}${RESET}"
echo -e "${BOLD}============================================${RESET}"
echo ""

# Parse the YAML and produce a formatted table
echo "$YAML" | python3 -c "
import sys, yaml

doc = yaml.safe_load(sys.stdin.read())
policies = doc.get('network_policies', {})

rows = []
for policy_key, policy in policies.items():
    name = policy.get('name', policy_key)
    endpoints = policy.get('endpoints', [])
    binaries = policy.get('binaries', [])

    bin_names = []
    for b in binaries:
        p = b.get('path', '')
        bin_names.append(p.split('/')[-1])

    for ep in endpoints:
        host = ep.get('host', '?')
        port = ep.get('port', '?')
        rules = ep.get('rules', [])
        access = ep.get('access', '')

        if access == 'full':
            methods = 'ALL'
        elif rules:
            methods = ', '.join(
                r['allow']['method']
                for r in rules
                if 'allow' in r and 'method' in r['allow']
            )
        else:
            methods = 'ALL'

        via = ', '.join(bin_names) if bin_names else 'any'
        rows.append((f'{host}:{port}', methods, via))

# Calculate column widths
if rows:
    w1 = max(len(r[0]) for r in rows)
    w2 = max(len(r[1]) for r in rows)

    # Header
    print(f'  \033[1m{\"ENDPOINT\":<{w1}}  {\"METHODS\":<{w2}}  VIA\033[0m')
    print(f'  {\"─\" * w1}  {\"─\" * w2}  {\"─\" * 20}')

    for endpoint, methods, via in rows:
        # Color: green for ALL, yellow for restricted
        if methods == 'ALL':
            mc = '\033[0;32m'
        else:
            mc = '\033[1;33m'
        print(f'  {endpoint:<{w1}}  {mc}{methods:<{w2}}\033[0m  \033[2m{via}\033[0m')
" 2>/dev/null || {
  # Fallback if python3/pyyaml not available: simple grep-based output
  echo "  (python3 with PyYAML not available — raw endpoint list)"
  echo ""
  echo "$YAML" | grep -E '^\s+- host:' | sed 's/.*host: /  /' | sort -u
}

echo ""
echo -e "  ${DIM}Policy: default-deny (only listed hosts are reachable)${RESET}"
echo ""
