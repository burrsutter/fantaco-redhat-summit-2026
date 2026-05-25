#!/usr/bin/env bash
# reset-openclaw.sh — Reset OpenClaw gateway to fresh state
#
# Wipes all user state (chat sessions, agent memory, cron jobs, custom skills,
# config) from the gateway PVC and restarts the deployment so it re-initializes
# cleanly from the operator ConfigMap.
#
# Usage:
#   ./reset-openclaw.sh              # reset current namespace (student mode)
#   ./reset-openclaw.sh 2 5          # reset agentic-user2 through agentic-user5
#   ./reset-openclaw.sh 3            # just agentic-user3
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)
#
# Config re-patching (model, diagnostics, allowedOrigins) is handled by
# post-restart-repatch.sh which sources .env directly.

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  echo "Usage: $0                # reset current namespace"
  echo "       $0 <start> [end]  # reset agentic-user<start> through agentic-user<end>"
  exit 1
fi

# ── Verify oc login ─────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo "Error: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

echo "============================================"
echo "  OpenClaw Gateway Reset"
echo "============================================"
echo ""
echo "Logged in as: $(oc whoami)"
echo ""
echo "Namespaces to reset:"
for NS in "${NAMESPACES[@]}"; do
  echo "  - ${NS}"
done
echo ""
echo "This wipes all user state (chats, memory, cron, custom skills, config)"
echo "and restarts the gateway so it re-initializes from the operator ConfigMap."
echo ""

# ── Per-namespace reset ─────────────────────────────────────────────
SUCCESS_COUNT=0
FAIL_COUNT=0

for NS in "${NAMESPACES[@]}"; do
  echo "=== Resetting namespace: $NS ==="

  # Verify gateway pod is running
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo "  WARN: No gateway pod found in $NS — skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo ""
    continue
  fi
  echo "  Gateway pod: $POD"

  # Wipe user state via oc exec
  echo "  Wiping user state..."
  oc exec deployment/instance -n "$NS" -c gateway -- node -e "
    const { execSync } = require('child_process');
    const fs = require('fs');
    const path = require('path');
    const HOME = '/home/node/.openclaw';

    const dirsToRemove = [
      // Chat sessions
      HOME + '/agents/default/sessions',
      // Agent temp files
      HOME + '/agents/main/agent/codex-home/tmp',
      // Cron job runs
      HOME + '/cron/runs',
      // Caches
      HOME + '/.cache',
      HOME + '/.local',
    ];

    const filesToRemove = [
      // Agent state DBs (glob patterns handled below)
      // Agent identity
      HOME + '/agents/main/agent/codex-home/installation_id',
      HOME + '/agents/main/agent/codex-home/.personality_migration',
      // Cron config
      HOME + '/cron/jobs.json',
      HOME + '/cron/jobs.json.bak',
      HOME + '/cron/jobs-state.json',
      // Memory
      HOME + '/memory/default.sqlite',
      HOME + '/memory/default.sqlite-wal',
      HOME + '/memory/default.sqlite-shm',
      // Task history
      HOME + '/tasks/runs.sqlite',
      HOME + '/tasks/runs.sqlite-wal',
      HOME + '/tasks/runs.sqlite-shm',
      // Workspace state
      HOME + '/workspace/.openclaw/workspace-state.json',
      // Workspace docs
      HOME + '/workspace/USER.md',
      HOME + '/workspace/HEARTBEAT.md',
      HOME + '/workspace/IDENTITY.md',
      HOME + '/workspace/SOUL.md',
      // Device identity
      HOME + '/identity/device.json',
      // Config (will be re-seeded from operator ConfigMap on restart)
      HOME + '/openclaw.json',
      HOME + '/openclaw.json.last-good',
      // Update check
      HOME + '/update-check.json',
      // Config health
      HOME + '/logs/config-health.json',
    ];

    let removed = 0;

    // Remove directories
    for (const d of dirsToRemove) {
      try {
        execSync('rm -rf ' + JSON.stringify(d), { stdio: 'pipe' });
        removed++;
      } catch (e) { /* dir may not exist */ }
    }

    // Remove individual files
    for (const f of filesToRemove) {
      try {
        fs.unlinkSync(f);
        removed++;
      } catch (e) { /* file may not exist */ }
    }

    // Remove agent state/log SQLite files (glob: state_*.sqlite*, logs_*.sqlite*)
    const codexHome = HOME + '/agents/main/agent/codex-home';
    try {
      const entries = fs.readdirSync(codexHome);
      for (const e of entries) {
        if (/^(state_|logs_).*\\.sqlite/.test(e)) {
          fs.unlinkSync(path.join(codexHome, e));
          removed++;
        }
      }
    } catch (e) { /* dir may not exist */ }

    // Remove user-created skills (preserve platform/)
    const skillsDir = HOME + '/workspace/skills';
    try {
      const entries = fs.readdirSync(skillsDir);
      for (const e of entries) {
        if (e !== 'platform') {
          execSync('rm -rf ' + JSON.stringify(path.join(skillsDir, e)), { stdio: 'pipe' });
          removed++;
        }
      }
    } catch (e) { /* dir may not exist */ }

    // Remove temp logs
    try {
      execSync('rm -rf /tmp/openclaw', { stdio: 'pipe' });
      removed++;
    } catch (e) { /* may not exist */ }

    console.log('Removed ' + removed + ' items');
  "

  # Restart the deployment
  echo "  Restarting gateway deployment..."
  oc rollout restart deployment/instance -n "$NS"

  # Wait for rollout
  echo "  Waiting for rollout to complete..."
  if oc rollout status deployment/instance -n "$NS" --timeout=120s 2>/dev/null; then
    echo "  Gateway restarted successfully."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "  WARN: Rollout did not complete within 120s."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo ""
done

# ── Re-patch all config (model, diagnostics, allowedOrigins) ──────────
# The reset wipes openclaw.json and the operator re-seeds from ConfigMap.
# Re-install plugins that were on the PVC, then re-patch all config.
echo "--- Re-patching config ---"
for NS in "${NAMESPACES[@]}"; do
  # Re-install prometheus plugin if ServiceMonitor exists
  if oc get servicemonitor openclaw-gateway -n "$NS" &>/dev/null; then
    oc exec deployment/instance -n "$NS" -c gateway -- \
      node /app/dist/index.js plugins install @openclaw/diagnostics-prometheus 2>&1 \
      | grep -E "^(Installed|Already|Error)" || true
  fi
  # Re-install OTEL plugin if it was previously configured
  OTEL_ENV=$(oc set env deployment/instance -n "$NS" --list -c gateway 2>/dev/null | grep "^OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=" || true)
  if [[ -n "$OTEL_ENV" ]]; then
    oc exec deployment/instance -n "$NS" -c gateway -- \
      node /app/dist/index.js plugins install @openclaw/diagnostics-otel 2>&1 \
      | grep -E "^(Installed|Already|Error)" || true
  fi
done
for NS in "${NAMESPACES[@]}"; do
  "${SCRIPT_DIR}/post-restart-repatch.sh" "$NS"
done
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "============================================"
echo "  Reset complete!"
echo "============================================"
echo ""
echo "  Succeeded: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  Failed:    $FAIL_COUNT"
fi
echo "  Config:    re-patched via post-restart-repatch.sh"
echo ""
echo "The gateway will re-initialize with a clean state."
echo "Connect to the UI to verify: empty chats, no custom skills, no cron jobs."
