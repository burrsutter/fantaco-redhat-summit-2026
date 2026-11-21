#!/usr/bin/env bash
# deploy-rhoai-mlflow.sh — stand up the RHOAI MLflow CR that backs Gen AI
# studio's prompt registry ("Save prompt" in the Playground).
#
# WHY THIS EXISTS. With `mlflowoperator: Managed` in the DataScienceCluster the
# operator and the mlflow-ui pod both run, but there is no MLflow CR, so the UI
# logs every 30 seconds:
#     "MLflow CR auto-discovery failed, MLflow endpoints will return 503"
# and saving a prompt fails in the browser with "Service Unavailable". The CR is
# the missing piece; nothing else in the install creates it.
#
# THIS DOES NOT REPLACE THE STANDALONE MLflow in the `mlflow` namespace.
# RHOAI MLflow has NO OTLP ingestion endpoint — /v1/traces and /otlp/v1/traces
# both return 404 even when authenticated — so OpenClaw's diagnostics-otel still
# exports traces to the standalone server. The two coexist on purpose and this
# script deliberately gives RHOAI MLflow its own PostgreSQL so the trace store
# is never touched.
#
# Usage:
#   ./deploy-rhoai-mlflow.sh                 # deploy + label seats 1..100
#   ./deploy-rhoai-mlflow.sh 1 50            # deploy + label seats 1..50
#   ./deploy-rhoai-mlflow.sh --check         # report, change nothing
#   ./deploy-rhoai-mlflow.sh --smoke-test    # create+list+delete a real prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NS=redhat-ods-applications
WORKSPACE_LABEL="mlflow.opendatahub.io/workspace=true"
MODE=deploy
RANGE_START=1
RANGE_END=100

case "${1:-}" in
  --check)      MODE=check ;;
  --smoke-test) MODE=smoke ;;
  "")           ;;
  -*)           echo "Unknown flag: $1" >&2; exit 1 ;;
  *)            RANGE_START="$1"; RANGE_END="${2:?need an end seat}" ;;
esac

for c in oc python3; do command -v "$c" >/dev/null || { echo "Missing $c" >&2; exit 1; }; done
oc whoami >/dev/null

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; RST=$'\033[0m'
ok()   { echo "  ${GREEN}✓${RST} $*"; }
bad()  { echo "  ${RED}✗${RST} $*"; }
warn() { echo "  ${YEL}!${RST} $*"; }

report() {
  echo "── RHOAI MLflow status ─────────────────────────────"
  if oc get mlflow mlflow >/dev/null 2>&1; then
    local av
    av=$(oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    [[ "$av" == "True" ]] && ok "MLflow CR Available=True" || bad "MLflow CR Available=$av"
    oc get mlflow mlflow -o jsonpath='{.status.version}{"\n"}' 2>/dev/null \
      | sed 's/^/    version: /'
  else
    bad "No MLflow CR — prompt save will return 503"
  fi
  local n
  n=$(oc get ns -l "$WORKSPACE_LABEL" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ok "namespaces labelled as MLflow workspaces: $n"
  if oc logs -n "$NS" deploy/mlflow-ui --since=2m 2>/dev/null | grep -q "auto-discovery failed"; then
    warn "mlflow-ui still reports auto-discovery failures in the last 2m"
  else
    ok "mlflow-ui is not reporting auto-discovery failures"
  fi
}

smoke() {
  # Exercise the exact endpoint the Playground's Save prompt button calls.
  local seat="agentic-user${RANGE_START}" tok rc
  tok=$(oc whoami -t)
  oc port-forward -n "$NS" svc/odh-dashboard-mlflow-ui 18343:8343 >/dev/null 2>&1 &
  local pf=$!
  trap 'kill '"$pf"' 2>/dev/null || true' RETURN
  sleep 6
  echo "── smoke test against $seat ────────────────────────"
  rc=$(curl -sk -o /tmp/.mlf-smoke -w '%{http_code}' --max-time 30 -X POST \
        -H "x-forwarded-access-token: $tok" -H 'Content-Type: application/json' \
        -d '{"name":"fantaco-smoke-test","template":"Summarise the account for {{customer}}.","commit_message":"deploy verification"}' \
        "https://localhost:18343/api/v1/prompts?workspace=$seat" || true)
  if [[ "$rc" == "201" ]]; then
    ok "prompt created (HTTP 201)"
  else
    bad "prompt create returned HTTP $rc: $(head -c 200 /tmp/.mlf-smoke)"
    rm -f /tmp/.mlf-smoke; return 1
  fi
  rc=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 25 -X DELETE \
        -H "x-forwarded-access-token: $tok" \
        "https://localhost:18343/api/v1/prompts/fantaco-smoke-test?workspace=$seat" || true)
  [[ "$rc" == "204" ]] && ok "prompt deleted (HTTP 204)" || warn "cleanup returned HTTP $rc"
  rm -f /tmp/.mlf-smoke
}

if [[ "$MODE" == check ]]; then report; exit 0; fi
if [[ "$MODE" == smoke ]]; then smoke; exit $?; fi

echo "── backend store secret ────────────────────────────"
if oc get secret rhoai-mlflow-db -n "$NS" >/dev/null 2>&1; then
  ok "secret rhoai-mlflow-db already exists (password left untouched)"
else
  # sslmode=disable is MANDATORY: the operator requires SSL on the backend
  # store and the stock postgresql image does not serve it, so without this the
  # migration Job dies with "server does not support SSL, but SSL was required".
  PGPASS=$(python3 -I -c "import secrets;print(secrets.token_urlsafe(24).replace('-','').replace('_',''))")
  oc create secret generic rhoai-mlflow-db -n "$NS" \
    --from-literal=database-user=mlflow \
    --from-literal=database-password="$PGPASS" \
    --from-literal=database-name=mlflow \
    --from-literal=backend-store-uri="postgresql://mlflow:${PGPASS}@rhoai-mlflow-db.${NS}.svc.cluster.local:5432/mlflow?sslmode=disable" \
    >/dev/null
  unset PGPASS
  ok "secret rhoai-mlflow-db created (generated password, never printed)"
fi

echo "── dedicated PostgreSQL ────────────────────────────"
oc apply -f "$SCRIPT_DIR/operator-patches/rhoai-mlflow-db.yaml" >/dev/null
oc rollout status deploy/rhoai-mlflow-db -n "$NS" --timeout=300s >/dev/null
ok "rhoai-mlflow-db is ready"

echo "── workspace labels (seats $RANGE_START..$RANGE_END) ──"
# The CR is workspace-scoped: a namespace that does not match
# workspaceLabelSelector errors with "Workspace '<ns>' not found". A DEDICATED
# label is used rather than opendatahub.io/dashboard so that labelling the seats
# does not also turn all of them into RHOAI Data Science Projects.
LABELLED=0
for n in $(seq "$RANGE_START" "$RANGE_END"); do
  if oc label ns "agentic-user$n" "$WORKSPACE_LABEL" --overwrite >/dev/null 2>&1; then
    LABELLED=$((LABELLED + 1))
  fi
done
ok "labelled $LABELLED namespaces"

echo "── MLflow CR ───────────────────────────────────────"
# Must be named literally `mlflow` (singleton) and use backendStoreUriFrom.
oc apply -f "$SCRIPT_DIR/operator-patches/rhoai-mlflow-cr.yaml" >/dev/null
echo "  waiting for migration + deployment (about 60-90s)…"
for _ in $(seq 1 40); do
  AV=$(oc get mlflow mlflow -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
  [[ "$AV" == "True" ]] && break
  sleep 10
done
if [[ "${AV:-}" == "True" ]]; then
  ok "MLflow CR Available=True"
else
  bad "MLflow CR did not become Available"
  oc get mlflow mlflow -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}' 2>/dev/null
  echo "  If the migration Job failed, delete it and re-annotate the CR:" >&2
  echo "    oc delete job -n $NS -l app.kubernetes.io/name=mlflow" >&2
  echo "    oc annotate mlflow mlflow mlflow.opendatahub.io/force-migrate=\$(date +%s) --overwrite" >&2
  exit 1
fi

echo
report
echo
echo "Run './deploy-rhoai-mlflow.sh --smoke-test' to prove a prompt actually saves."
