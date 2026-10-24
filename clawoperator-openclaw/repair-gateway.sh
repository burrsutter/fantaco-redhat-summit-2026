#!/usr/bin/env bash
# repair-gateway.sh — Fix gateways that cannot boot, without wiping their PVC
#
# Two failure modes are handled. Both leave the gateway in CrashLoopBackOff, and
# both are unreachable by `oc exec` for the same reason: there is no running
# container to exec into.
#
#   1. PLUGIN — a half-copied langfuse-tracer:
#
#        Gateway failed to start: Invalid config at .../openclaw.json:
#        plugins: plugin: plugin manifest not found:
#        /home/node/.openclaw/extensions/langfuse-tracer/openclaw.plugin.json
#
#      audience-reset.sh copies the plugin with two `oc cp` calls. When the
#      second fails the directory holds index.js and nothing else, and the
#      repatch then writes a config enabling a plugin that cannot load.
#
#   2. VERSION — a gateway pinned back to an older image:
#
#        Refusing to run automatic gateway startup migrations because this
#        OpenClaw binary (2026.6.35) is older than the config last written by
#        OpenClaw 2026.7.1.
#
#      openclaw.json lives on the PVC and records `meta.lastTouchedVersion`.
#      OpenClaw migrates forward but never backward, so pinning spec.image down
#      wedges any namespace that has already run a newer build. Measured on
#      hlm6k: the 7.1-written config is otherwise fully compatible with the 6.35
#      binary — identical top-level key set, all 11 plugins load — so the gate is
#      advisory and correcting the marker is enough. No PVC wipe, no re-seed.
#
# Getting at the PVC needs care on two counts:
#
#   * `oc scale deployment/instance --replicas=0` does not stick. The operator
#     reconciles it back to 1 within ~20s, so the PVC is never free.
#   * instance-home-pvc is ReadWriteOnce, so a second pod can only mount it if
#     it lands on the same node as the crashlooping one.
#
# Hence a repair pod pinned with nodeName to the instance pod's node, mounting
# the same PVC at /work (subPath `home`, matching the gateway's own mount).
#
# Usage:
#   ./repair-gateway.sh 1 50           # scan the range, repair what is broken
#   ./repair-gateway.sh 30             # one user
#   ./repair-gateway.sh --check 1 50   # report only, change nothing
#
# Healthy namespaces are skipped, so the whole range is safe to pass. A gateway
# down for any other reason is reported with its log tail and left alone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"
PLUGIN_SRC="${SCRIPT_DIR}/../claw_plugins/langfuse-tracer"
PLUGIN_SUBPATH="extensions/langfuse-tracer"
REPAIR_POD="plugin-repair"
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:2026.6.35-slim}"

# The version the binary actually is, derived from the image tag, so the marker
# written into openclaw.json cannot drift from the image the pod runs.
BINARY_VERSION="${OPENCLAW_IMAGE##*:}"
BINARY_VERSION="${BINARY_VERSION%-slim}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

CHECK_ONLY=false
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|-n) CHECK_ONLY=true; shift ;;
    -h|--help)  sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo -e "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    *)  POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 [--check] <start> [end]" >&2
  exit 1
fi
START="$1"; END="${2:-$1}"

for f in index.js openclaw.plugin.json; do
  if [[ ! -s "${PLUGIN_SRC}/${f}" ]]; then
    echo -e "${RED}ERROR: plugin source missing: ${PLUGIN_SRC}/${f}${RESET}" >&2
    exit 1
  fi
done

oc whoami &>/dev/null || { echo -e "${RED}ERROR: not logged in to OpenShift.${RESET}" >&2; exit 1; }

echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  OpenClaw gateway repair${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  Namespaces: ${NAMESPACE_PREFIX}${START}..${END}"
echo -e "  Image:      ${DIM}${OPENCLAW_IMAGE}${RESET} (binary ${BINARY_VERSION})"
$CHECK_ONLY && echo -e "  Mode:       ${YELLOW}--check (read-only)${RESET}"
echo ""

N_OK=0; N_FIXED=0; N_FAILED=0; N_SKIPPED=0; N_NEEDS=0
FAILED_NS=()

cleanup_repair_pod() {
  oc delete pod "$REPAIR_POD" -n "$1" --ignore-not-found --wait=false &>/dev/null || true
}

start_repair_pod() {
  local ns="$1" node="$2" fsgroup="$3"

  # A leftover pod from an interrupted run would be Completed or Terminating
  # and unusable; start from a known state.
  oc delete pod "$REPAIR_POD" -n "$ns" --ignore-not-found --wait=true &>/dev/null || true

  # The namespace ResourceQuota (namespace-quota) rejects any container that
  # does not declare all four of requests.cpu/memory and limits.cpu/memory.
  oc apply -n "$ns" -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${REPAIR_POD}
  labels:
    app.kubernetes.io/name: plugin-repair
spec:
  nodeName: ${node}
  restartPolicy: Never
  # instance-home-pvc is group-owned by the gateway pod's fsGroup (drwxrws---).
  # Without the same fsGroup the repair container runs as gid 1000 (node),
  # is not a member of that group, and every write to /work is denied — the
  # copy below then silently leaves the plugin half-written all over again.
  securityContext:
    fsGroup: ${fsgroup}
  containers:
  - name: repair
    image: ${OPENCLAW_IMAGE}
    command: ["sleep", "600"]
    resources:
      requests: {cpu: 10m, memory: 32Mi}
      limits:   {cpu: 100m, memory: 128Mi}
    volumeMounts:
    - name: claw-home
      mountPath: /work
      subPath: home
  volumes:
  - name: claw-home
    persistentVolumeClaim:
      claimName: instance-home-pvc
EOF

  if ! oc wait --for=condition=Ready "pod/${REPAIR_POD}" -n "$ns" --timeout=120s &>/dev/null; then
    echo -e "    ${RED}✗ repair pod never became Ready${RESET}"
    oc get pod "$REPAIR_POD" -n "$ns" -o jsonpath='{.status.conditions[*].message}' 2>/dev/null | head -c 300
    echo ""
    cleanup_repair_pod "$ns"
    return 1
  fi
}

# Write the missing plugin files into a PVC no running gateway can reach.
fix_plugin() {
  local ns="$1"
  oc exec "$REPAIR_POD" -n "$ns" -- mkdir -p "/work/${PLUGIN_SUBPATH}" >/dev/null 2>&1 || true
  for f in index.js openclaw.plugin.json; do
    # `oc cp` prints tar warnings on a successful copy and has been seen to
    # report success while leaving a file absent, so its exit code is ignored
    # either way — the verify below is the real test.
    oc cp "${PLUGIN_SRC}/${f}" "${ns}/${REPAIR_POD}:/work/${PLUGIN_SUBPATH}/${f}" &>/dev/null || true
  done
  oc exec "$REPAIR_POD" -n "$ns" -- \
    sh -c "test -s '/work/${PLUGIN_SUBPATH}/index.js' && test -s '/work/${PLUGIN_SUBPATH}/openclaw.plugin.json'" &>/dev/null
}

# Correct the version marker that blocks an intentional downgrade.
fix_version() {
  local ns="$1"
  oc exec "$REPAIR_POD" -n "$ns" -- node -e '
    const fs = require("fs"), f = "/work/openclaw.json";
    const want = process.argv[1];
    // Keep a copy: this is the only record of which build last wrote the
    // config, and it is worth having if the downgrade turns out to be wrong.
    if (!fs.existsSync(f + ".pre-downgrade")) fs.copyFileSync(f, f + ".pre-downgrade");
    const c = JSON.parse(fs.readFileSync(f));
    c.meta = c.meta || {};
    c.meta.lastTouchedVersion = want;
    fs.writeFileSync(f, JSON.stringify(c, null, 2));
  ' "$BINARY_VERSION" >/dev/null 2>&1 || return 1

  oc exec "$REPAIR_POD" -n "$ns" -- node -e '
    const c = JSON.parse(require("fs").readFileSync("/work/openclaw.json"));
    process.exit(c.meta && c.meta.lastTouchedVersion === process.argv[1] ? 0 : 1);
  ' "$BINARY_VERSION" &>/dev/null
}

for i in $(seq "$START" "$END"); do
  NS="${NAMESPACE_PREFIX}${i}"

  if ! oc get ns "$NS" &>/dev/null; then
    echo -e "  ${DIM}${NS}: namespace does not exist — skipping${RESET}"
    N_SKIPPED=$((N_SKIPPED + 1)); continue
  fi
  if ! oc get deployment instance -n "$NS" &>/dev/null; then
    echo -e "  ${DIM}${NS}: no OpenClaw instance — skipping${RESET}"
    N_SKIPPED=$((N_SKIPPED + 1)); continue
  fi

  READY=$(oc get deploy instance -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if [[ "${READY:-0}" -ge 1 ]]; then
    N_OK=$((N_OK + 1)); continue
  fi

  POD=$(oc get pods -n "$NS" -l claw.sandbox.redhat.com/instance=instance -l app=claw \
        --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)
  if [[ -z "$POD" ]]; then
    echo -e "  ${YELLOW}⚠ ${NS}: deployment has no pod — skipping${RESET}"
    N_SKIPPED=$((N_SKIPPED + 1)); continue
  fi

  # Classify before touching anything. A gateway down for another reason
  # (image pull, OOM, bad model config) must not be papered over by a repair
  # and a restart that hides the real error.
  LOG=$(oc logs "$POD" -n "$NS" -c gateway --tail=40 2>/dev/null || true)
  [[ -z "$LOG" ]] && LOG=$(oc logs "$POD" -n "$NS" -c gateway --tail=40 --previous 2>/dev/null || true)

  MODE=""
  if [[ "$LOG" == *"plugin manifest not found"* ]]; then
    MODE="plugin"
  elif [[ "$LOG" == *"older than the config last written"* || "$LOG" == *"Refusing to run automatic gateway startup migrations"* ]]; then
    MODE="version"
  fi

  if [[ -z "$MODE" ]]; then
    echo -e "  ${YELLOW}⚠ ${NS}: down for an unrecognised reason — leaving alone${RESET}"
    if [[ -n "$LOG" ]]; then
      echo -e "    ${DIM}$(echo "$LOG" | tail -3 | tr '\n' ' ' | cut -c1-200)${RESET}"
    else
      echo -e "    ${DIM}(no gateway log yet — pod may still be initialising)${RESET}"
    fi
    N_SKIPPED=$((N_SKIPPED + 1)); continue
  fi

  # `oc get pods -o wide | awk` is not usable here: when STATUS is
  # CrashLoopBackOff the columns shift and the node comes back as "40s".
  NODE=$(oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  if [[ -z "$NODE" ]]; then
    echo -e "  ${RED}✗ ${NS}: cannot determine node for ${POD}${RESET}"
    N_FAILED=$((N_FAILED + 1)); FAILED_NS+=("$NS"); continue
  fi

  FSGROUP=$(oc get pod "$POD" -n "$NS" -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null || true)
  if [[ -z "$FSGROUP" ]]; then
    echo -e "  ${RED}✗ ${NS}: cannot determine fsGroup for ${POD}${RESET}"
    N_FAILED=$((N_FAILED + 1)); FAILED_NS+=("$NS"); continue
  fi

  echo -e "  ${CYAN}${NS}${RESET}: ${BOLD}${MODE}${RESET} failure (node ${DIM}${NODE}${RESET})"
  N_NEEDS=$((N_NEEDS + 1))
  $CHECK_ONLY && continue

  if ! start_repair_pod "$NS" "$NODE" "$FSGROUP"; then
    N_FAILED=$((N_FAILED + 1)); FAILED_NS+=("$NS"); continue
  fi

  OK=false
  case "$MODE" in
    plugin)  fix_plugin  "$NS" && OK=true ;;
    version) fix_version "$NS" && OK=true ;;
  esac
  cleanup_repair_pod "$NS"

  if $OK; then
    oc rollout restart deployment/instance -n "$NS" >/dev/null 2>&1 || true
    echo -e "    ${GREEN}✓${RESET} repaired, gateway restarting"
    N_FIXED=$((N_FIXED + 1))
  else
    echo -e "    ${RED}✗${RESET} repair failed"
    N_FAILED=$((N_FAILED + 1)); FAILED_NS+=("$NS")
  fi
done

if (( N_FIXED > 0 )) && ! $CHECK_ONLY; then
  echo ""
  echo -e "  ${DIM}waiting for restarted gateways to settle...${RESET}"
  sleep 90
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
if $CHECK_ONLY; then
  echo -e "  ${GREEN}${N_OK}${RESET} ready, ${YELLOW}${N_NEEDS}${RESET} repairable, ${N_SKIPPED} skipped"
else
  echo -e "  ${GREEN}${N_OK}${RESET} already ready, ${GREEN}${N_FIXED}${RESET} repaired, ${RED}${N_FAILED}${RESET} failed, ${N_SKIPPED} skipped"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
(( ${#FAILED_NS[@]} > 0 )) && echo -e "  ${YELLOW}${FAILED_NS[*]}${RESET}"
echo ""

# A final census is worth more than the tally above: a gateway can be restarted
# successfully and still fail to come back for an unrelated reason.
if ! $CHECK_ONLY; then
  echo -e "${BOLD}Fleet readiness:${RESET}"
  NOT_READY=()
  for i in $(seq "$START" "$END"); do
    NS="${NAMESPACE_PREFIX}${i}"
    oc get deployment instance -n "$NS" &>/dev/null || continue
    R=$(oc get deploy instance -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${R:-0}" -ge 1 ]] || NOT_READY+=("$NS")
  done
  if (( ${#NOT_READY[@]} == 0 )); then
    echo -e "  ${GREEN}✓ all gateways in range are ready${RESET}"
  else
    echo -e "  ${YELLOW}⚠ still not ready: ${NOT_READY[*]}${RESET}"
  fi
fi
