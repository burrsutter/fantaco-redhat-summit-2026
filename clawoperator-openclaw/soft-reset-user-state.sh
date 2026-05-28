#!/usr/bin/env bash
# soft-reset-user-state.sh — Reset a user's chat state without touching routes or config
#
# Wipes chat history, memory, tasks, user-added skills, and Langfuse traces
# for the specified namespace(s). Does NOT change routes, config, plugins,
# broker mappings, or restart pods.
#
# Usage:
#   ./soft-reset-user-state.sh 1          # reset agentic-user1
#   ./soft-reset-user-state.sh 1 5        # reset user1 through user5
#
# Environment variables:
#   NAMESPACE_PREFIX — namespace prefix (default: agentic-user)

set -euo pipefail

NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_GUID=$(oc cluster-info 2>/dev/null | head -1 | sed 's|.*api\.ocp\.\([^.]*\)\..*|\1|')
if [[ -z "$CLUSTER_GUID" ]]; then
  echo "Error: could not extract cluster GUID from 'oc cluster-info'" >&2
  exit 1
fi

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Source Langfuse keys from cluster state ─────────────────────────
LANGFUSE_PUBLIC_KEY=""
LANGFUSE_SECRET_KEY=""
LANGFUSE_STATE="${SCRIPT_DIR}/.state/${CLUSTER_GUID}/langfuse.env"
if [[ -f "$LANGFUSE_STATE" ]]; then
  # shellcheck disable=SC1090
  source "$LANGFUSE_STATE"
  LANGFUSE_PUBLIC_KEY="${INIT_PUBLIC_KEY:-}"
  LANGFUSE_SECRET_KEY="${INIT_SECRET_KEY:-}"
fi
LANGFUSE_ROUTE=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)

# ── Argument parsing ────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <start> [end]    # agentic-user<start> through agentic-user<end>"
  exit 1
fi

NAMESPACES=()
START=$1
END=${2:-$START}
if [[ $START -gt $END ]]; then
  echo "Error: start ($START) must be <= end ($END)"
  exit 1
fi
for i in $(seq "$START" "$END"); do
  NAMESPACES+=("${NAMESPACE_PREFIX}${i}")
done

echo -e "${BOLD}Soft-resetting ${#NAMESPACES[@]} namespace(s)${RESET}"
echo ""

SUCCESS=0
FAIL=0

for NS in "${NAMESPACES[@]}"; do
  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance --no-headers 2>/dev/null \
    | grep "^instance-" | grep -v proxy | grep -v device-pairing | grep "Running" | awk '{print $1}' | head -1)
  if [[ -z "$POD" ]]; then
    echo -e "  ${YELLOW}$NS: no running gateway pod — skipping${RESET}"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Wipe chat history, memory, tasks, user-added skills
  CLEANED=$(cat <<'WIPE_EOF' | oc exec -i deployment/instance -n "$NS" -c gateway -- node 2>/dev/null
var execSync = require("child_process").execSync;
var fs = require("fs");
var path = require("path");
var HOME = "/home/node/.openclaw";
var removed = 0;

// Chat sessions
var dirs = [
  HOME + "/agents/default/sessions",
  HOME + "/agents/main/agent/codex-home/tmp",
  HOME + "/.cache",
  HOME + "/.local"
];
for (var i = 0; i < dirs.length; i++) {
  try { execSync("rm -rf " + JSON.stringify(dirs[i]), { stdio: "pipe" }); removed++; } catch (e) {}
}

// State files
var files = [
  HOME + "/memory/default.sqlite",
  HOME + "/memory/default.sqlite-wal",
  HOME + "/memory/default.sqlite-shm",
  HOME + "/tasks/runs.sqlite",
  HOME + "/tasks/runs.sqlite-wal",
  HOME + "/tasks/runs.sqlite-shm",
  HOME + "/workspace/.openclaw/workspace-state.json",
  HOME + "/workspace/USER.md"
];
for (var i = 0; i < files.length; i++) {
  try { fs.unlinkSync(files[i]); removed++; } catch (e) {}
}

// Codex state DBs
var codexHome = HOME + "/agents/main/agent/codex-home";
try {
  var entries = fs.readdirSync(codexHome);
  for (var i = 0; i < entries.length; i++) {
    if (/^(state_|logs_).*\.sqlite/.test(entries[i])) {
      fs.unlinkSync(path.join(codexHome, entries[i]));
      removed++;
    }
  }
} catch (e) {}

// User-added skills (keep platform + quote-builder)
var skillsDir = HOME + "/workspace/skills";
var keep = { platform: true, "quote-builder": true };
try {
  var entries = fs.readdirSync(skillsDir);
  for (var i = 0; i < entries.length; i++) {
    if (!keep[entries[i]]) {
      execSync("rm -rf " + JSON.stringify(path.join(skillsDir, entries[i])), { stdio: "pipe" });
      removed++;
    }
  }
} catch (e) {}

// Reset IDENTITY.md to default demo state
try {
  fs.writeFileSync(HOME + "/workspace/IDENTITY.md",
    "# IDENTITY.md - Who Am I?\n\n" +
    "- **Name:**\n" +
    "- **Creature:** An octopus juggling eight priorities at once\n" +
    "- **Vibe:** Calm under pressure\n" +
    '- **Emoji:** \u{1F419}\n' +
    "- **Avatar:**\n");
  removed++;
} catch (e) {}

// Reset HEARTBEAT.md if present
try { fs.unlinkSync(HOME + "/workspace/HEARTBEAT.md"); removed++; } catch (e) {}

// Reset SOUL.md if present
try { fs.unlinkSync(HOME + "/workspace/SOUL.md"); removed++; } catch (e) {}

// Tmp
try { execSync("rm -rf /tmp/openclaw", { stdio: "pipe" }); removed++; } catch (e) {}

console.log(removed);
WIPE_EOF
  )

  if [[ -n "$CLEANED" ]]; then
    echo -e "  ${GREEN}✓${RESET} $NS: wiped ($CLEANED items)"
    SUCCESS=$((SUCCESS + 1))
  else
    echo -e "  ${RED}✗${RESET} $NS: wipe failed"
    FAIL=$((FAIL + 1))
  fi

  # Clear Langfuse traces for this namespace
  if [[ -n "$LANGFUSE_ROUTE" && -n "$LANGFUSE_PUBLIC_KEY" && -n "$LANGFUSE_SECRET_KEY" ]]; then
    # Langfuse traces are tagged with the namespace — delete via ClickHouse
    CH_POD=$(oc get pod -n langfuse -l app.kubernetes.io/component=clickhouse -o name 2>/dev/null | head -1)
    if [[ -n "$CH_POD" ]]; then
      CH_PASS=$(oc get secret langfuse-clickhouse-auth -n langfuse -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
      # Delete traces where userId = namespace (set by langfuse-tracer plugin)
      for TABLE in traces observations scores; do
        oc exec -n langfuse "${CH_POD}" -- clickhouse-client \
          --user default --password "${CH_PASS}" \
          --query "ALTER TABLE ${TABLE} DELETE WHERE user_id = '${NS}'" 2>/dev/null || true
      done
      echo -e "  ${GREEN}✓${RESET} $NS: Langfuse traces cleared"
    fi
  fi
done

echo ""
echo -e "${BOLD}Done:${RESET} ${SUCCESS} wiped, ${FAIL} failed"
