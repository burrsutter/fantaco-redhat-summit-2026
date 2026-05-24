#!/usr/bin/env bash
# 6-inject-enterprise-skills.sh — Inject claw_skills into OpenClaw gateway pods
#
# Copies SKILL.md files from claw_skills/ into the gateway pod's workspace
# so they appear as slash commands in the OpenClaw UI.
#
# Currently injects: quote-builder
#
# Usage:
#   ./6-inject-enterprise-skills.sh              # inject into current namespace (student mode)
#   ./6-inject-enterprise-skills.sh 2 5          # inject into agentic-user2 through agentic-user5
#   ./6-inject-enterprise-skills.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${SCRIPT_DIR}/../claw_skills"
SKILLS_DEST="/home/node/.openclaw/workspace/skills"

# ── Skills to inject ────────────────────────────────────────────────
SKILLS=(
  quote-builder
)

# ── Argument parsing ────────────────────────────────────────────────
NAMESPACES=()
if [[ $# -eq 0 ]]; then
  CURRENT_NS=$(oc project -q 2>/dev/null) || { echo "Error: cannot detect current namespace. Run 'oc project <ns>' first."; exit 1; }
  NAMESPACES+=("$CURRENT_NS")
elif [[ $# -le 2 ]]; then
  START=$1
  END=${2:-$START}
  if [[ $START -gt $END ]]; then
    echo "Error: start ($START) must be <= end ($END)"
    exit 1
  fi
  for i in $(seq "$START" "$END"); do
    NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
  done
else
  echo "Usage: $0                # inject into current namespace"
  echo "       $0 <start> [end]  # inject into agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

# ── Verify skills exist locally ─────────────────────────────────────
for SKILL in "${SKILLS[@]}"; do
  if [[ ! -f "$SKILLS_DIR/$SKILL/SKILL.md" ]]; then
    echo "Error: Skill not found: $SKILLS_DIR/$SKILL/SKILL.md"
    exit 1
  fi
done

echo "============================================"
echo "  Inject Enterprise Skills"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo "Namespaces:   ${NAMESPACES[*]}"
echo "Skills:       ${SKILLS[*]}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Namespace: $NS ==="

  # Find the gateway pod name (oc cp needs pod name, not deployment)
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
    | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)

  if [[ -z "$POD" ]]; then
    echo "  WARN: No running gateway pod found in $NS — skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  Gateway pod: $POD"

  INJECTED=0
  for SKILL in "${SKILLS[@]}"; do
    # Create the skill directory in the pod
    oc exec "$POD" -n "$NS" -c gateway -- mkdir -p "${SKILLS_DEST}/${SKILL}" 2>/dev/null

    # Copy SKILL.md into the pod
    if oc cp "$SKILLS_DIR/$SKILL/SKILL.md" "$POD:${SKILLS_DEST}/${SKILL}/SKILL.md" -n "$NS" -c gateway 2>/dev/null; then
      echo "  ✓ $SKILL injected"
      INJECTED=$((INJECTED + 1))
    else
      echo "  ⚠ $SKILL injection failed"
    fi
  done

  # Verify
  echo "  Installed skills:"
  oc exec "$POD" -n "$NS" -c gateway -- find "$SKILLS_DEST" -name SKILL.md 2>/dev/null \
    | sed "s|${SKILLS_DEST}/||" | sed 's|/SKILL.md||' | sed 's/^/    /' || true

  if [[ $INJECTED -eq ${#SKILLS[@]} ]]; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
done

echo "============================================"
echo "  Skill Injection Summary"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo ""
echo "Skills are available immediately — no pod restart needed."
echo "Try: /quote_builder NovaSpark AI Labs, Enchanted Forest"
