#!/usr/bin/env bash
#
# maas-publish-model.sh — publish the upstream RHDP MaaS model through THIS
# cluster's MaaS ("MaaS over MaaS").
#
# This is the step that maas-bootstrap.sh stops short of. maas-bootstrap.sh
# makes the MaaS platform work; this script puts a model on it. Run it second.
#
#   RHDP MaaS (upstream, maas-rhdp.apps.maas.redhatworkshops.io)
#        │  authenticated with ONE virtual key you already hold
#        ▼
#   secret qwen-upstream-maas  (models-as-a-service)
#        │
#   ExternalProvider ──► ExternalModel ──► MaaSModelRef
#        │
#   MaaSSubscription + MaaSAuthPolicy   (quota + gateway access)
#        │
#        ▼
#   https://maas.<apps-domain>/v1   ← seats call this with per-seat keys
#                                     (see maas-mint-seat-keys.sh)
#
# THE TRAP THIS SCRIPT EXISTS TO PREVENT
# --------------------------------------
# Without the label `inference.llm-d.ai/ipp-managed=true` on the upstream
# secret, every CR reports Ready, /v1/models lists the model, and API keys
# issue fine — and only the first REAL inference fails, with
#   inference error: Internal - authType 'apikey' credentials not found
# The label is in the docs procedure but in no CRD field description, so
# `oc explain` will not save you. This script applies the label and then
# proves the path with an actual inference call, because "Ready" is a lie here.
#
# Usage:
#   ./maas-publish-model.sh --check     # report state, change nothing
#   ./maas-publish-model.sh             # create/apply, idempotent
#   ./maas-publish-model.sh --verify    # just re-run the inference smoke test
#   ./maas-publish-model.sh --render    # print the rendered YAML, apply nothing
#
# The files in operator-patches/ are TEMPLATES ({{PLACEHOLDER}} syntax) so that
# the script and the YAML cannot drift apart. `--render` is how you read or
# hand-apply them:
#   ./maas-publish-model.sh --render | oc apply -f -
#
# Reads from ../.env (see .env.example):
#   MAAS_UPSTREAM_API_KEY   required. The RHDP virtual key. Never pass on argv.
#   MAAS_UPSTREAM_ENDPOINT  default maas-rhdp.apps.maas.redhatworkshops.io
#                           FQDN ONLY — no scheme, no path. The CRD rejects
#                           "https://host/v1"; the /v1 lives in the
#                           ExternalModel path, not the provider endpoint.
#   MAAS_MODEL              default qwen3-235b-a22b
#   MAAS_TOKEN_LIMIT        default 50000000   (fleet-wide, not per seat)
#   MAAS_TOKEN_WINDOW       default 1h
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

NS_TENANT="${NS_TENANT:-models-as-a-service}"
SECRET_NAME="${SECRET_NAME:-qwen-upstream-maas}"
IPP_LABEL="inference.llm-d.ai/ipp-managed=true"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

MODE=apply
case "${1:-}" in
  --check)  MODE=check ;;
  --verify) MODE=verify ;;
  --render) MODE=render ;;
  "")       ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- env
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

MAAS_UPSTREAM_ENDPOINT="${MAAS_UPSTREAM_ENDPOINT:-maas-rhdp.apps.maas.redhatworkshops.io}"
MAAS_MODEL="${MAAS_MODEL:-qwen3-235b-a22b}"
MAAS_TOKEN_LIMIT="${MAAS_TOKEN_LIMIT:-50000000}"
MAAS_TOKEN_WINDOW="${MAAS_TOKEN_WINDOW:-1h}"

# Guard the documented CRD gotcha rather than letting it fail 10 minutes later.
case "$MAAS_UPSTREAM_ENDPOINT" in
  *://*|*/*)
    bad "MAAS_UPSTREAM_ENDPOINT must be an FQDN only (no scheme, no path)"
    info "got:      $MAAS_UPSTREAM_ENDPOINT"
    info "expected: maas-rhdp.apps.maas.redhatworkshops.io"
    exit 1 ;;
esac

render() {
  sed -e "s|{{MAAS_UPSTREAM_ENDPOINT}}|${MAAS_UPSTREAM_ENDPOINT}|g" \
      -e "s|{{MAAS_MODEL}}|${MAAS_MODEL}|g" \
      -e "s|{{MAAS_TOKEN_LIMIT}}|${MAAS_TOKEN_LIMIT}|g" \
      -e "s|{{MAAS_TOKEN_WINDOW}}|${MAAS_TOKEN_WINDOW}|g" "$1"
}

if [ "$MODE" = render ]; then
  render "${SCRIPT_DIR}/operator-patches/maas-over-maas-qwen.yaml"
  render "${SCRIPT_DIR}/operator-patches/maas-over-maas-governance.yaml"
  exit 0
fi

bold "0/5  Preflight"
oc whoami >/dev/null 2>&1 || { bad "not logged in to a cluster"; exit 1; }
ok "logged in as $(oc whoami)"

APPS_DOMAIN=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
GW_HOST=$(oc get gateway maas-default-gateway -n openshift-ingress \
            -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null)
[ -z "$GW_HOST" ] && GW_HOST="maas.${APPS_DOMAIN}"
ok "MaaS gateway: https://${GW_HOST}"
info "model: ${MAAS_MODEL}   upstream: ${MAAS_UPSTREAM_ENDPOINT}"

if ! oc get ns "$NS_TENANT" >/dev/null 2>&1; then
  bad "namespace $NS_TENANT does not exist — run ./maas-bootstrap.sh first"
  exit 1
fi
ok "namespace $NS_TENANT exists"

# ---------------------------------------------------------------- 1. secret
bold "1/5  Upstream credential (secret/${SECRET_NAME})"

secret_exists() { oc get secret "$SECRET_NAME" -n "$NS_TENANT" >/dev/null 2>&1; }
secret_labelled() {
  [ "$(oc get secret "$SECRET_NAME" -n "$NS_TENANT" \
       -o jsonpath='{.metadata.labels.inference\.llm-d\.ai/ipp-managed}' 2>/dev/null)" = "true" ]
}

if [ "$MODE" = check ]; then
  if secret_exists; then
    ok "secret exists"
    secret_labelled && ok "labelled $IPP_LABEL" || bad "MISSING LABEL $IPP_LABEL — inference will fail"
  else
    bad "secret missing"
  fi
elif [ "$MODE" = apply ]; then
  if secret_exists; then
    ok "secret already exists (not overwritten)"
    info "to rotate: oc set data secret/$SECRET_NAME -n $NS_TENANT --from-literal=api-key='<new>'"
  else
    if [ -z "${MAAS_UPSTREAM_API_KEY:-}" ]; then
      bad "MAAS_UPSTREAM_API_KEY is not set"
      info "Add it to $ENV_FILE (chmod 600), it is your RHDP virtual key:"
      info "  MAAS_UPSTREAM_API_KEY=sk-..."
      info "Do not pass it on the command line — it would land in your shell history."
      exit 1
    fi
    # The key name MUST be literally "api-key": the CRD requires it.
    oc create secret generic "$SECRET_NAME" -n "$NS_TENANT" \
       --from-literal=api-key="$MAAS_UPSTREAM_API_KEY" >/dev/null \
      && ok "created secret" || { bad "could not create secret"; exit 1; }
  fi
  # Always (re)assert the label — this is the single worst trap here.
  oc label secret "$SECRET_NAME" -n "$NS_TENANT" "$IPP_LABEL" --overwrite >/dev/null 2>&1 \
    && ok "labelled $IPP_LABEL" || bad "could not label secret"
fi

# ---------------------------------------------------------------- 2-3. CRs
render_and_apply() {
  local file="$1" label="$2"
  [ -f "$file" ] || { bad "missing $file"; return 1; }
  render "$file" | oc apply -f - >/dev/null 2>&1 \
    && ok "applied $label" || { bad "failed to apply $label"; return 1; }
}

bold "2/5  Model chain (ExternalProvider → ExternalModel → MaaSModelRef)"
if [ "$MODE" = apply ]; then
  render_and_apply "${SCRIPT_DIR}/operator-patches/maas-over-maas-qwen.yaml" "model chain"
else
  for k in externalprovider externalmodel maasmodelref; do
    n=$(oc get "$k" -n "$NS_TENANT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && ok "$k present ($n)" || bad "$k missing"
  done
fi

bold "3/5  Governance (MaaSSubscription + MaaSAuthPolicy)"
if [ "$MODE" = apply ]; then
  render_and_apply "${SCRIPT_DIR}/operator-patches/maas-over-maas-governance.yaml" "governance"
  info "token limit ${MAAS_TOKEN_LIMIT} / ${MAAS_TOKEN_WINDOW} — FLEET-WIDE, all seats share it"
else
  for k in maassubscription maasauthpolicy; do
    n=$(oc get "$k" -n "$NS_TENANT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && ok "$k present ($n)" || bad "$k missing"
  done
fi

# ---------------------------------------------------------------- 4. ready
bold "4/5  Waiting for the model to appear on the gateway"
TOK=$(oc whoami -t 2>/dev/null)
MODEL_SEEN=0
# --check must never block: probe once, do not wait for reconciliation.
[ "$MODE" = check ] && ATTEMPTS=1 || ATTEMPTS=40
for i in $(seq 1 "$ATTEMPTS"); do
  if curl -sk -m 15 -H "Authorization: Bearer $TOK" "https://${GW_HOST}/v1/models" 2>/dev/null \
       | grep -q "$MAAS_MODEL"; then
    MODEL_SEEN=1; ok "/v1/models lists ${MAAS_MODEL}"; break
  fi
  printf "  [%02d/%02d] not listed yet…\r" "$i" "$ATTEMPTS"; [ "$i" -lt "$ATTEMPTS" ] && sleep 15
done
[ "$MODEL_SEEN" = 1 ] || warn "model not listed after 10 minutes — check the operator logs"

# ---------------------------------------------------------------- 5. prove it
bold "5/5  Inference smoke test"
echo "  Ready means nothing here. Only a real completion proves the credential."

SUBS=$(curl -sk -m 20 -H "Authorization: Bearer $TOK" "https://${GW_HOST}/v1/subscriptions" 2>/dev/null)
if echo "$SUBS" | grep -q "$MAAS_MODEL"; then
  ok "subscription covers ${MAAS_MODEL}"
else
  bad "no subscription covers ${MAAS_MODEL} — keys will issue but inference will 403"
fi

# ------------------------------------------------- write the cluster's own
# LLM_API_BASE_URL and LLM_MODEL_NAME are CLUSTER-SPECIFIC and nothing else
# derives them. A fresh clone inherits whatever was in .env.example (an RHDP
# LiteLLM URL), the seats then point at the wrong endpoint, and it surfaces as
# "the agent cannot reach the model" rather than as a config error.
# audience-reset.sh also derives the proxy allowlist domain from this value, so
# a stale entry silently misconfigures egress too.
#
# We know both values here, so write them back. Same pattern as
# switch-provider.sh --update-env and update-broker-ocp.sh's broker.env.
if [ "$MODE" = apply ] && [ -f "$ENV_FILE" ]; then
  bold "Writing cluster values back to .env"
  NEW_BASE="https://${GW_HOST}/v1"
  python3 - "$ENV_FILE" "$NEW_BASE" "$MAAS_MODEL" <<'PY'
import re, sys, pathlib
env, base, model = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = env.read_text(encoding="utf-8")
for key, val in (("LLM_API_BASE_URL", base), ("LLM_MODEL_NAME", model),
                 ("LLM_PROVIDER", "litellm")):
    pat = re.compile(rf"^{key}=.*$", re.M)
    if pat.search(text):
        if pat.search(text).group(0) == f"{key}={val}":
            print(f"  = {key} already correct"); continue
        text = pat.sub(f"{key}={val}", text); print(f"  ~ {key} -> {val}")
    else:
        text = text.rstrip("\n") + f"\n{key}={val}\n"; print(f"  + {key} = {val}")
env.write_text(text, encoding="utf-8")
PY
  info "seats pick this up on the next audience-reset / post-restart-repatch"
fi

echo
echo "  To prove end to end, mint a key and call the model:"
echo "    ./maas-mint-seat-keys.sh --smoke-test"
echo
echo "  If that returns \"authType 'apikey' credentials not found\", the upstream"
echo "  secret label is missing. Re-run this script to reassert it."
echo
echo "  Next: ./maas-mint-seat-keys.sh 1 100   # per-seat keys, then apply them"
