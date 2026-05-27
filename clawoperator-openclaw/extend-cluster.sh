#!/usr/bin/env bash
# extend-cluster.sh — Add N new agentic-user namespaces to the cluster
#
# Creates new namespaces (continuing from the current max), applies labels
# and annotations, then runs all per-namespace setup scripts to bring them
# to the same state as existing namespaces.
#
# Usage:
#   ./extend-cluster.sh 5            # Add 5 more namespaces (auto-detects next number)
#   ./extend-cluster.sh 5 --dry-run  # Show what would be created without doing it
#
# Cluster-wide scripts (Loki, Grafana, MLflow, Langfuse) do NOT need to re-run.

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
CURRENT_MAX=$(oc get ns --no-headers 2>/dev/null \
  | awk '{print $1}' \
  | grep "^${NAMESPACE_PREFIX}" \
  | sed "s/^${NAMESPACE_PREFIX}//" \
  | sort -n \
  | tail -1)

if [[ -z "$CURRENT_MAX" ]]; then
  echo "Error: No existing ${NAMESPACE_PREFIX}* namespaces found on cluster."
  echo "Run the initial cluster provisioning first."
  exit 1
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
fi

# ── Phase 1: Create namespaces ──────────────────────────────────────
echo -e "${BOLD}--- Phase 1: Create namespaces ---${RESET}"
CREATED=0
SKIPPED=0

for i in $(seq "$NEW_START" "$NEW_END"); do
  NS="${NAMESPACE_PREFIX}${i}"

  if oc get ns "$NS" &>/dev/null; then
    echo -e "  ${DIM}$NS already exists — skipping creation${RESET}"
    ((SKIPPED++))
    continue
  fi

  if $DRY_RUN; then
    echo -e "  ${DIM}[dry-run]${RESET} would create $NS"
  else
    echo -e "  Creating ${CYAN}$NS${RESET} ..."
    oc new-project "$NS" --display-name="Workspace" > /dev/null

    oc label namespace "$NS" \
      "app.kubernetes.io/instance=workspace-user${i}" \
      "pod-security.kubernetes.io/audit=baseline" \
      "pod-security.kubernetes.io/warn=baseline" \
      --overwrite > /dev/null

    oc annotate namespace "$NS" \
      "openshift.io/description=Agentic AI Namespace" \
      --overwrite > /dev/null

    echo -e "  ${GREEN}✓${RESET} $NS created"
  fi
  ((CREATED++))
done

echo -e "  Created: ${GREEN}${CREATED}${RESET}, Skipped: ${DIM}${SKIPPED}${RESET}"
echo ""

if $DRY_RUN; then
  echo -e "${BOLD}--- Phase 2: Would run setup scripts ---${RESET}"
  echo -e "  ${DIM}[dry-run]${RESET} ./0-admin-setup.sh $NEW_START $NEW_END"
  echo -e "  ${DIM}[dry-run]${RESET} ./audience-reset.sh $NEW_START $NEW_END"
  echo -e "  ${DIM}[dry-run]${RESET} ./set-namespace-quotas.sh $NEW_START $NEW_END"
  echo -e "  ${DIM}[dry-run]${RESET} ./enable-prometheus.sh $NEW_START $NEW_END"
  echo -e "  ${DIM}[dry-run]${RESET} ./update-broker.sh (rebuild routes.csv from ALL namespaces)"
  echo -e "  ${DIM}[dry-run]${RESET} ./demo-preflight.sh $NEW_START $NEW_END"
  echo ""
  echo -e "${YELLOW}=== DRY RUN complete ===${RESET}"
  echo -e "Would have added ${CYAN}${NAMESPACE_PREFIX}${NEW_START}${RESET} through ${CYAN}${NAMESPACE_PREFIX}${NEW_END}${RESET}"
  echo -e "Total namespaces would be: ${BOLD}${NEW_END}${RESET}"
  exit 0
fi

# ── Phase 2: RBAC setup ────────────────────────────────────────────
echo -e "${BOLD}--- Phase 2: RBAC setup (0-admin-setup.sh) ---${RESET}"
"$SCRIPT_DIR/0-admin-setup.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Phase 3: Full deploy (audience-reset.sh) ────────────────────────
echo -e "${BOLD}--- Phase 3: Deploy everything (audience-reset.sh) ---${RESET}"
echo -e "${YELLOW}Reminder: audience-reset.sh needs AWS for broker update.${RESET}"
echo -e "${YELLOW}Make sure you ran 'aws login' recently (sessions expire in 1 hour).${RESET}"
echo ""
"$SCRIPT_DIR/audience-reset.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Phase 4: Apply namespace quotas ───────────────────────────────
echo -e "${BOLD}--- Phase 4: Apply namespace quotas (set-namespace-quotas.sh) ---${RESET}"
"$SCRIPT_DIR/set-namespace-quotas.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Phase 5: Enable Prometheus metrics ──────────────────────────────
echo -e "${BOLD}--- Phase 5: Enable Prometheus (enable-prometheus.sh) ---${RESET}"
"$SCRIPT_DIR/enable-prometheus.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Phase 6: Rebuild broker routes from ALL namespaces ──────────────
# audience-reset.sh (Phase 3) updated the broker with only the new range.
# Re-sync now so routes.csv includes both old and new namespaces.
echo -e "${BOLD}--- Phase 6: Rebuild broker routes (update-broker.sh) ---${RESET}"
"$SCRIPT_DIR/update-broker.sh"
echo ""

# ── Phase 7: Verify ─────────────────────────────────────────────────
echo -e "${BOLD}--- Phase 7: Verify (demo-preflight.sh) ---${RESET}"
"$SCRIPT_DIR/demo-preflight.sh" "$NEW_START" "$NEW_END"
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}=== Extend Cluster complete ===${RESET}"
echo -e "Added ${CYAN}${NAMESPACE_PREFIX}${NEW_START}${RESET} through ${CYAN}${NAMESPACE_PREFIX}${NEW_END}${RESET}"
echo -e "Total namespaces: ${BOLD}${NEW_END}${RESET}"
