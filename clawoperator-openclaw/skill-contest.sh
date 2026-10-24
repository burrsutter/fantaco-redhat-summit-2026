#!/usr/bin/env bash
# skill-contest.sh — Collect every attendee-authored skill so a winner can be picked
#
# At the end of a demo run the audience has built skills of their own on top of
# the FantaCo world (Sally Sellers, the customer MCP, Imagination Pods). Picking
# a winner means reading all of them, which was previously done by hand: the
# July 7 and July 9 contest files in this directory were assembled pod by pod
# across three clusters. This script is that job, automated.
#
# Where the skills live matters. The seeded enterprise skills are copied to
#   /home/node/.openclaw/workspace/skills
# but anything the *agent* authors on a user's behalf lands in
#   /home/node/.openclaw/workspace/main/skills
# so the second path is the contest entry list. Seeded names are excluded by
# name as well, because a user who edits a seeded skill gets a copy in their own
# workspace and that is not an original entry.
#
# Usage:
#   ./skill-contest.sh                          # current cluster, all agentic-user*
#   ./skill-contest.sh --full                   # also dump every SKILL.md body
#   ./skill-contest.sh --clusters clusters.csv  # sweep several clusters
#   ./skill-contest.sh 1 50                     # restrict to a namespace range
#   ./skill-contest.sh --exclude 1,2            # skip instructor / staff namespaces
#
# Output lands in .state/<cluster-guid>/contest/<timestamp>/ :
#   contest-skills.txt   the human-readable report, same shape as the July files
#   contest-skills.csv   cluster,user,skill,description — for sorting or a spreadsheet
#   contest-skills.md    full SKILL.md bodies (only with --full)
#
# Electing the winner is deliberately NOT automated. The script gathers and
# formats; a human (or an LLM handed contest-skills.md) judges. --full is what
# you want for real judging: descriptions alone flatter skills that are
# well-described and punish good ones that are terse.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE_PREFIX="${NAMESPACE_PREFIX:-agentic-user}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

AGENT_SKILLS_DIR="/home/node/.openclaw/workspace/main/skills"

# Seeded skills (claw_skills/) plus the ones every guided demo produces. A user
# who never went off-script has none of the rest, which is exactly the signal
# the contest is looking for.
DEFAULT_EXCLUDES="customer-360,customer-lookup,invoice-lookup,order-status,product-search,quote-builder,watchlist-manager,platform,friendly-greeter,browser-automation"

# Not excluded, only tagged. The guided MCP prompt ("a skill that manages
# personal customer notes") gives everyone one of these, so it is rarely the
# winner — but attendees do extend it in interesting ways, and silently
# dropping those would hide real work from the judge.
GUIDED_PATTERN='note|notes-manager|customer-note'

# ── Arguments ─────────────────────────────────────────────────────────
FULL=false
CLUSTERS_FILE=""
EXCLUDE_USERS="1"
EXCLUDE_SKILLS="$DEFAULT_EXCLUDES"
CONCURRENCY=8
OUT_DIR=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site)           SITE_NAME="$2"; shift 2 ;;
    --full)           FULL=true; shift ;;
    --clusters)       CLUSTERS_FILE="$2"; shift 2 ;;
    --exclude)        EXCLUDE_USERS="$2"; shift 2 ;;
    --exclude-skill)  EXCLUDE_SKILLS="${EXCLUDE_SKILLS},$2"; shift 2 ;;
    --concurrency|-c) CONCURRENCY="$2"; shift 2 ;;
    --out|-o)         OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo -e "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    *)  POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/sites/resolve-site.sh"

RANGE_START=1
RANGE_END=50
if [[ $# -eq 1 ]]; then
  RANGE_START="$1"; RANGE_END="$1"
elif [[ $# -eq 2 ]]; then
  RANGE_START="$1"; RANGE_END="$2"
elif [[ $# -gt 2 ]]; then
  echo -e "${RED}ERROR: expected at most <start> <end>.${RESET}" >&2
  exit 1
fi

if ! command -v oc >/dev/null 2>&1; then
  echo -e "${RED}ERROR: 'oc' not found in PATH.${RESET}" >&2
  exit 1
fi

# ── Cluster list ──────────────────────────────────────────────────────
# Each entry is "id<TAB>kubeconfig" — an empty kubeconfig means the ambient
# login, which is the single-cluster case.
CLUSTER_IDS=()
CLUSTER_KUBECONFIGS=()

if [[ -n "$CLUSTERS_FILE" ]]; then
  [[ -f "$CLUSTERS_FILE" ]] || CLUSTERS_FILE="${SCRIPT_DIR}/${CLUSTERS_FILE}"
  if [[ ! -f "$CLUSTERS_FILE" ]]; then
    echo -e "${RED}ERROR: clusters file not found: ${CLUSTERS_FILE}${RESET}" >&2
    exit 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    cid="${line%%,*}"; kcfg="${line#*,}"
    cid=$(echo "$cid" | xargs); kcfg=$(echo "$kcfg" | xargs)
    if [[ ! -r "$kcfg" ]]; then
      echo -e "${YELLOW}⚠ skipping cluster ${cid}: kubeconfig unreadable (${kcfg})${RESET}" >&2
      continue
    fi
    CLUSTER_IDS+=("$cid")
    CLUSTER_KUBECONFIGS+=("$kcfg")
  done < "$CLUSTERS_FILE"
  if (( ${#CLUSTER_IDS[@]} == 0 )); then
    echo -e "${RED}ERROR: no usable clusters in ${CLUSTERS_FILE}.${RESET}" >&2
    exit 1
  fi
else
  if ! oc whoami &>/dev/null; then
    echo -e "${RED}ERROR: not logged in to OpenShift. Run 'oc login' first.${RESET}" >&2
    exit 1
  fi
  GUID=$(oc whoami --show-server 2>/dev/null | sed -E 's|^https?://api\.(ocp\.)?(cluster-)?([^.:]+).*|\3|')
  [[ -z "$GUID" ]] && GUID="current"
  CLUSTER_IDS+=("$GUID")
  CLUSTER_KUBECONFIGS+=("")
fi

PRIMARY_GUID="${CLUSTER_IDS[0]}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
[[ -z "$OUT_DIR" ]] && OUT_DIR="${SCRIPT_DIR}/.state/${PRIMARY_GUID}/contest/${TIMESTAMP}"
mkdir -p "$OUT_DIR"

RAW_DIR="${OUT_DIR}/raw"
mkdir -p "$RAW_DIR"

# ── Banner ────────────────────────────────────────────────────────────
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  FantaCo skill contest — collecting entries${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Clusters:    ${CYAN}${CLUSTER_IDS[*]}${RESET}"
echo -e "  Namespaces:  ${NAMESPACE_PREFIX}${RANGE_START}..${RANGE_END}"
echo -e "  Skipping:    users ${EXCLUDE_USERS}"
echo -e "  Output:      ${DIM}${OUT_DIR}${RESET}"
$FULL && echo -e "  Mode:        ${YELLOW}--full (SKILL.md bodies included)${RESET}"
echo ""

is_excluded_user() {
  local n="$1"
  local IFS=','
  for e in $EXCLUDE_USERS; do
    [[ "$(echo "$e" | xargs)" == "$n" ]] && return 0
  done
  return 1
}

# ── Collect ───────────────────────────────────────────────────────────
# One `oc exec` per namespace, not one per skill: at 50 namespaces the
# per-exec handshake dominates everything else.
collect_ns() {
  local cid="$1" kcfg="$2" ns="$3" dest="$4"
  local -a env_prefix=()
  [[ -n "$kcfg" ]] && env_prefix=(env "KUBECONFIG=$kcfg")

  # An expired token makes every API call fail, and the obvious `|| MISSING`
  # turns that into "all 50 namespaces are gone" — a clean-looking report that
  # is entirely false. Tell the two apart and abort loudly on auth.
  local ns_err
  if ! ns_err=$("${env_prefix[@]}" oc get ns "$ns" 2>&1 >/dev/null); then
    if [[ "$ns_err" == *Unauthorized* || "$ns_err" == *"must be logged in"* || "$ns_err" == *"credentials"* ]]; then
      echo "AUTHFAIL" > "${dest}.status"
    else
      echo "MISSING" > "${dest}.status"
    fi
    return 0
  fi

  # No gateway deployment means the namespace exists but OpenClaw was never
  # provisioned into it. That is a very different fact from "this user built
  # no skills", and reporting both as EMPTY hides a half-provisioned fleet.
  if ! "${env_prefix[@]}" oc get deployment instance -n "$ns" &>/dev/null; then
    echo "NOPOD" > "${dest}.status"
    return 0
  fi

  local out
  # `|| true` is deliberate: a pod that is gone, starting, or wedged must not
  # abort the sweep for the other 49 namespaces.
  out=$(timeout 60 "${env_prefix[@]}" oc exec deployment/instance -n "$ns" -c gateway -- \
    sh -c "for d in ${AGENT_SKILLS_DIR}/*/; do
             [ -f \"\$d/SKILL.md\" ] || continue
             echo \"===OPENCLAW-SKILL:\$(basename \"\$d\")===\"
             cat \"\$d/SKILL.md\"
             echo
           done" 2>/dev/null) || true

  if [[ -z "$out" ]]; then
    # Reachable and provisioned, but nothing authored — a genuine zero.
    echo "NOSKILLS" > "${dest}.status"
  else
    printf '%s' "$out" > "$dest"
    echo "OK" > "${dest}.status"
  fi
}

TOTAL_NS=0
for ci in "${!CLUSTER_IDS[@]}"; do
  cid="${CLUSTER_IDS[$ci]}"
  kcfg="${CLUSTER_KUBECONFIGS[$ci]}"
  echo -e "${BOLD}--- ${cid} ---${RESET}"

  running=0
  for n in $(seq "$RANGE_START" "$RANGE_END"); do
    is_excluded_user "$n" && continue
    ns="${NAMESPACE_PREFIX}${n}"
    collect_ns "$cid" "$kcfg" "$ns" "${RAW_DIR}/${cid}__${ns}.md" &
    running=$((running + 1))
    TOTAL_NS=$((TOTAL_NS + 1))
    if (( running % CONCURRENCY == 0 )); then wait; fi
  done
  wait

  # Report the breakdown, not just the hits. A sweep that finds nothing because
  # the fleet is half-built looks identical to one where nobody entered.
  # `|| true` on every one: grep exits 1 when a status simply never occurred,
  # and under `set -euo pipefail` that aborts the whole script mid-sweep.
  n_auth=$(grep -lx AUTHFAIL "${RAW_DIR}/${cid}__"*.status 2>/dev/null | wc -l || true)
  n_missing=$(grep -lx MISSING  "${RAW_DIR}/${cid}__"*.status 2>/dev/null | wc -l || true)
  n_nopod=$(grep -lx NOPOD      "${RAW_DIR}/${cid}__"*.status 2>/dev/null | wc -l || true)
  n_none=$(grep -lx NOSKILLS    "${RAW_DIR}/${cid}__"*.status 2>/dev/null | wc -l || true)
  found=$(find "$RAW_DIR" -name "${cid}__*.md" -type f 2>/dev/null | wc -l)

  if (( n_auth > 0 )); then
    echo -e "  ${RED}✗ ${n_auth} namespace(s) returned Unauthorized — the session token has expired.${RESET}"
    echo -e "  ${RED}  Log in again and re-run; this report would be missing entries.${RESET}" >&2
    exit 1
  fi

  echo -e "  entries from ${GREEN}${found}${RESET} namespace(s)"
  (( n_none > 0 ))    && echo -e "  ${DIM}${n_none} provisioned but no skills authored${RESET}"
  (( n_nopod > 0 ))   && echo -e "  ${YELLOW}⚠ ${n_nopod} namespace(s) have no OpenClaw instance — not provisioned${RESET}"
  (( n_missing > 0 )) && echo -e "  ${DIM}${n_missing} namespace(s) do not exist${RESET}"
done
echo ""

# ── Parse ─────────────────────────────────────────────────────────────
# YAML frontmatter is parsed in Python, not sed: descriptions are routinely
# quoted, folded across lines with `>`, or contain colons, and every one of
# those breaks a line-oriented shell parser in a way that silently truncates
# an entry rather than failing loudly.
PARSER="${OUT_DIR}/.parse.py"
cat > "$PARSER" <<'PYEOF'
import csv, os, re, sys

raw_dir, out_dir, excl_csv, guided_re, full = sys.argv[1:6]
full = full == "true"
excluded = {s.strip() for s in excl_csv.split(",") if s.strip()}
guided = re.compile(guided_re, re.I)

SPLIT = re.compile(r"^===OPENCLAW-SKILL:(.+?)===$", re.M)


def frontmatter(text):
    """Return (name, description) from SKILL.md YAML frontmatter."""
    m = re.match(r"\s*---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not m:
        return None, None
    block = m.group(1)
    fields = {}
    key = None
    for line in block.split("\n"):
        km = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if km:
            key = km.group(1).lower()
            fields[key] = km.group(2).strip()
        elif key and line.strip():
            # continuation of a folded or block scalar
            fields[key] = (fields[key] + " " + line.strip()).strip()
    def clean(v):
        if v is None:
            return None
        v = v.strip()
        if v[:1] in (">", "|"):
            v = v[1:].lstrip("-+ ").strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            v = v[1:-1]
        return re.sub(r"\s+", " ", v).strip()
    return clean(fields.get("name")), clean(fields.get("description"))


entries = []
for fn in sorted(os.listdir(raw_dir)):
    if not fn.endswith(".md") or fn.endswith(".status"):
        continue
    cluster, ns = fn[:-3].split("__", 1)
    user = ns.split("agentic-")[-1] if "agentic-" in ns else ns
    with open(os.path.join(raw_dir, fn), encoding="utf-8", errors="replace") as fh:
        blob = fh.read()
    parts = SPLIT.split(blob)
    # parts = [preamble, name1, body1, name2, body2, ...]
    for i in range(1, len(parts) - 1, 2):
        dirname = parts[i].strip()
        body = parts[i + 1]
        if dirname in excluded:
            continue
        name, desc = frontmatter(body)
        name = name or dirname
        if name in excluded:
            continue
        entries.append({
            "cluster": cluster,
            "user": user,
            "skill": dirname,
            "name": name,
            "description": desc or "(no description in frontmatter)",
            "guided": bool(guided.search(dirname) or guided.search(name)),
            "body": body.strip(),
            "bytes": len(body),
        })

entries.sort(key=lambda e: (e["cluster"], int(re.sub(r"\D", "", e["user"]) or 0), e["skill"]))

# ---- CSV ----
with open(os.path.join(out_dir, "contest-skills.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["cluster", "user", "skill", "description", "guided", "bytes"])
    for e in entries:
        w.writerow([e["cluster"], e["user"], e["skill"], e["description"],
                    "yes" if e["guided"] else "", e["bytes"]])

# ---- TXT report, same shape as the July contest files ----
from datetime import datetime, timezone
clusters = sorted({e["cluster"] for e in entries})
lines = []
lines.append("FantaCo Skill Contest - All Custom Skills")
lines.append("=" * 61)
lines.append("Generated: " + datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
lines.append("Clusters: " + (", ".join(clusters) if clusters else "(none)"))
lines.append("Excluded: default skills (" + ", ".join(sorted(excluded)) + ")")
lines.append("Tagged [guided]: skills the scripted demo prompts produce for everyone")
lines.append("")

for c in clusters:
    ce = [e for e in entries if e["cluster"] == c]
    users = sorted({e["user"] for e in ce})
    lines.append("=" * 80)
    lines.append("CLUSTER: %s  (%d custom skills, %d users)" % (c, len(ce), len(users)))
    lines.append("=" * 80)
    lines.append("")
    for e in ce:
        lines.append("USER: " + e["user"])
        lines.append("SKILL: " + e["skill"] + ("   [guided]" if e["guided"] else ""))
        lines.append("DESCRIPTION: " + e["description"])
        lines.append("")

# ---- Stats: who built the most, which is a useful tiebreak ----
from collections import Counter
per_user = Counter((e["cluster"], e["user"]) for e in entries if not e["guided"])
lines.append("=" * 80)
lines.append("MOST PROLIFIC BUILDERS (guided skills not counted)")
lines.append("=" * 80)
lines.append("")
for (c, u), n in per_user.most_common(15):
    lines.append("  %-8s (%s): %d skills" % (u, c, n))
lines.append("")

original = [e for e in entries if not e["guided"]]
lines.append("=" * 80)
lines.append("JUDGING RUBRIC")
lines.append("=" * 80)
lines.append("")
lines.append("The criteria used to pick previous winners, kept so results stay")
lines.append("comparable between runs:")
lines.append("")
lines.append("  1. CREATIVE     - a concept nobody else attempted")
lines.append("  2. USEFUL       - a real sales-enablement tool, not a toy")
lines.append("  3. DATA-DRIVEN  - uses actual MCP data, not mock or hypothetical")
lines.append("  4. COMPLETE     - thought through past the happy path")
lines.append("")
lines.append("%d entries from %d users, %d after removing guided-demo skills."
             % (len(entries), len({(e["cluster"], e["user"]) for e in entries}), len(original)))
lines.append("")
lines.append("Descriptions alone favour whoever wrote the best description.")
lines.append("Re-run with --full and judge from contest-skills.md before deciding.")
lines.append("")

with open(os.path.join(out_dir, "contest-skills.txt"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))

# ---- Full bodies ----
if full:
    md = ["# FantaCo Skill Contest - full entries", ""]
    md.append("%d skills. [guided] marks skills the scripted demo produces for everyone."
              % len(entries))
    md.append("")
    for e in entries:
        md.append("## %s / %s - `%s`%s" %
                  (e["cluster"], e["user"], e["skill"], "  [guided]" if e["guided"] else ""))
        md.append("")
        md.append("> " + e["description"])
        md.append("")
        md.append("```markdown")
        md.append(e["body"])
        md.append("```")
        md.append("")
    with open(os.path.join(out_dir, "contest-skills.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(md))

print("%d|%d|%d" % (len(entries), len(original),
                    len({(e["cluster"], e["user"]) for e in entries})))
PYEOF

STATS=$(python3 "$PARSER" "$RAW_DIR" "$OUT_DIR" "$EXCLUDE_SKILLS" "$GUIDED_PATTERN" "$FULL") || {
  echo -e "${RED}ERROR: parsing failed. Raw pod output kept at ${RAW_DIR}${RESET}" >&2
  exit 1
}
rm -f "$PARSER"

N_ALL="${STATS%%|*}"
N_REST="${STATS#*|}"
N_ORIG="${N_REST%%|*}"
N_USERS="${N_REST#*|}"

# ── Summary ───────────────────────────────────────────────────────────
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo -e "  Entries:  ${GREEN}${N_ALL}${RESET} skills from ${GREEN}${N_USERS}${RESET} users"
echo -e "            ${N_ORIG} after setting aside guided-demo skills"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Report:${RESET}  ${OUT_DIR}/contest-skills.txt"
echo -e "  ${BOLD}CSV:${RESET}     ${OUT_DIR}/contest-skills.csv"
if $FULL; then
  echo -e "  ${BOLD}Full:${RESET}    ${OUT_DIR}/contest-skills.md"
else
  echo ""
  echo -e "  ${DIM}Descriptions only. For real judging re-run with --full.${RESET}"
fi
echo ""
echo -e "${DIM}To have Claude pick a winner:${RESET}"
echo -e "${DIM}  claude -p \"Judge this FantaCo skill contest against the rubric at the${RESET}"
echo -e "${DIM}  end of the file. Pick one winner and five honorable mentions, with a${RESET}"
echo -e "${DIM}  short rationale each.\" < ${OUT_DIR}/contest-skills.md${RESET}"
echo ""

if (( N_ALL == 0 )); then
  echo -e "${YELLOW}No entries found. Either nobody has built a skill yet, or the${RESET}"
  echo -e "${YELLOW}gateway pods are not reachable — check ${RAW_DIR}/*.status${RESET}"
fi
