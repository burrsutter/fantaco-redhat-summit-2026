#!/usr/bin/env bash
# extend-cluster.sh — Add N new agentic-user namespaces to the cluster
#
# Creates new namespaces (continuing from the current max), applies labels,
# annotations, RBAC, and resource quotas. Does NOT run audience-reset.sh —
# run that separately afterwards to deploy backends, configure instances, etc.
#
# Usage:
#   ./extend-cluster.sh 5            # Add 5 more namespaces (auto-detects next number)
#   ./extend-cluster.sh 5 --dry-run  # Show what would be created without doing it
#
# After extending:
#   ./audience-reset.sh              # Resets ALL namespaces (old + new)
#   ./update-broker.sh --rotate-status-key
#   ./demo-preflight.sh 1 <new-total>

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Argument parsing ────────────────────────────────────────────────
DRY_RUN=false
COUNT=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *)
      if [[ -z "$COUNT" ]]; then
        COUNT="$arg"
      else
        echo "Error: unexpected argument '$arg'"
        echo "Usage: $0 <count> [--dry-run]"
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$COUNT" ]]; then
  echo "Usage: $0 <count> [--dry-run]"
  echo "  $0 5            — add 5 new namespaces"
  echo "  $0 5 --dry-run  — show what would be created"
  exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "Error: count must be a positive integer (got '$COUNT')"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Detect current max namespace number ─────────────────────────────
# `|| true` matters: under `set -euo pipefail` a grep that matches nothing
# fails the whole pipeline, and the script died with NO output at all — the
# error message below was unreachable on exactly the cluster it was written
# for. Keep the guard even though the empty case is now legal.
#
# Only count a purely numeric suffix, so agentic-user-scratch cannot be read
# as a seat number.
CURRENT_MAX=$(oc get ns --no-headers 2>/dev/null \
  | awk '{print $1}' \
  | sed -n "s/^${NAMESPACE_PREFIX}\([0-9][0-9]*\)$/\1/p" \
  | sort -n \
  | tail -1 || true)

if [[ -z "$CURRENT_MAX" ]]; then
  # Bootstrap: a bare cluster (ROSA sandbox, self-provisioned) has no seats at
  # all. RHDP pre-provisions them, so this path only shows up when building a
  # cluster by hand — which is now the normal case for one-off events.
  echo "No existing ${NAMESPACE_PREFIX}* namespaces — bootstrapping from zero."
  CURRENT_MAX=0
fi

NEW_START=$((CURRENT_MAX + 1))
NEW_END=$((CURRENT_MAX + COUNT))

echo -e "${BOLD}=== Extend Cluster ===${RESET}"
echo -e "Logged in as: ${CYAN}$(oc whoami)${RESET}"
echo -e "Current max namespace: ${CYAN}${NAMESPACE_PREFIX}${CURRENT_MAX}${RESET}"
echo -e "Will create: ${CYAN}${NAMESPACE_PREFIX}${NEW_START}${RESET} through ${CYAN}${NAMESPACE_PREFIX}${NEW_END}${RESET} (${COUNT} new)"
echo ""

if $DRY_RUN; then
  echo -e "${YELLOW}── DRY RUN — no changes will be made ──${RESET}"
  echo ""
  echo -e "${BOLD}Would run:${RESET}"
  echo -e "  1. Create namespaces ${NAMESPACE_PREFIX}${NEW_START} through ${NAMESPACE_PREFIX}${NEW_END}"
  echo -e "  2. ./0-admin-setup.sh $NEW_START $NEW_END  (RBAC)"
  echo -e "  3. ./set-namespace-quotas.sh $NEW_START $NEW_END  (resource quotas)"
  echo ""
  echo -e "${BOLD}Then manually:${RESET}"
  echo -e "  ./audience-reset.sh              # deploy + configure all namespaces"
  echo -e "  ./update-broker.sh --rotate-status-key"
  echo -e "  ./demo-preflight.sh 1 $NEW_END"
  echo ""
  echo -e "${YELLOW}=== DRY RUN complete ===${RESET}"
  echo -e "Would have added ${CYAN}${NAMESPACE_PREFIX}${NEW_START}${RESET} through ${CYAN}${NAMESPACE_PREFIX}${NEW_END}${RESET}"
  echo -e "Total namespaces would be: ${BOLD}${NEW_END}${RESET}"
  exit 0
fi

# ── Phase 1: Create namespaces ──────────────────────────────────────
echo -e "${BOLD}--- Phase 1: Create namespaces ---${RESET}"
CREATED=0
SKIPPED=0

for i in $(seq "$NEW_START" "$NEW_END"); do
  NS="${NAMESPACE_PREFIX}${i}"

  if oc get ns "$NS" &>/dev/null; then
    echo -e "  ${DIM}$NS already exists — skipping creation${RESET}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo -e "  Creating ${CYAN}$NS${RESET} ..."
  # Display name must be the namespace name, NOT a shared literal.
  # This used to be --display-name="Workspace", which gave all 100 seats the
  # SAME display name. Every project-scoped page in the RHOAI dashboard then
  # shows 100 identical "Workspace" entries in its Project selector, with no
  # way to tell them apart or to spot models-as-a-service among them. That is
  # how the External models tab looked empty on 2026-11-17: the selector was
  # on some seat rather than models-as-a-service, and nothing in the UI said so.
  oc new-project "$NS" --display-name="$NS" > /dev/null

  oc label namespace "$NS" \
    "app.kubernetes.io/instance=workspace-user${i}" \
    "pod-security.kubernetes.io/audit=baseline" \
    "pod-security.kubernetes.io/warn=baseline" \
    --overwrite > /dev/null

  oc annotate namespace "$NS" \
    "openshift.io/description=Agentic AI Namespace" \
    --overwrite > /dev/null

  echo -e "  ${GREEN}✓${RESET} $NS created"
  CREATED=$((CREATED + 1))
done

echo -e "  Created: ${GREEN}${CREATED}${RESET}, Skipped: ${DIM}${SKIPPED}${RESET}"
echo ""

# ── Phase 2: RBAC setup ────────────────────────────────────────────
echo -e "${BOLD}--- Phase 2: RBAC setup (0-admin-setup.sh) ---${RESET}"
"$SCRIPT_DIR/0-admin-setup.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Phase 3: Apply namespace quotas ───────────────────────────────
echo -e "${BOLD}--- Phase 3: Apply namespace quotas (set-namespace-quotas.sh) ---${RESET}"
"$SCRIPT_DIR/set-namespace-quotas.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}=== Extend Cluster complete ===${RESET}"
echo -e "Added ${CYAN}${NAMESPACE_PREFIX}${NEW_START}${RESET} through ${CYAN}${NAMESPACE_PREFIX}${NEW_END}${RESET}"
echo -e "Total namespaces: ${BOLD}${NEW_END}${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  ./audience-reset.sh              # deploy + configure all namespaces"
echo -e "  ./update-broker.sh --rotate-status-key"
echo -e "  ./demo-preflight.sh 1 $NEW_END"
