#!/usr/bin/env bash
#
# deploy-genai-playground.sh — recreate the Gen AI studio Playground for ONE seat.
#
# This was never scripted. On rosa-tztnl it existed only in agentic-user1 and
# had been built by hand, so a cluster rebuild would have lost it silently —
# the Playground nav item appears regardless (it comes from the OGX operator),
# but sending a prompt fails because there is no OGXServer in the namespace:
#   "no OGXServer found in namespace ..."
# Captured from the live cluster 2026-11-17 before teardown.
#
# It is deliberately ONE seat: the playground is what you demo from, not
# something every attendee needs. Point SEAT at whichever seat you present
# from.
#
# What it creates:
#   genai-pgvector            PostgreSQL 16 + pgvector, the vector store
#     + its Service, PVC, init ConfigMap and a generated credentials Secret
#   llama-stack-config        the OGX/llama-stack config (templated)
#   OGXServer                 lsd-genai-playground — the operator turns this
#                             into the deployment and service the BFF talks to
#
# Requires:
#   - DSC component ogx: Managed (the Playground nav item needs it)
#   - a MaaS endpoint to talk to; taken from LLM_API_BASE_URL in ../.env, or
#     derived from the maas-default-gateway if that is unset
#
# Usage:
#   ./deploy-genai-playground.sh            # seat 1
#   SEAT=7 ./deploy-genai-playground.sh     # seat 7
#   ./deploy-genai-playground.sh --check
#   ./deploy-genai-playground.sh --remove
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
MANIFESTS="${SCRIPT_DIR}/genai-playground"
SEAT="${SEAT:-1}"
NS="${NAMESPACE_PREFIX:-agentic-user}${SEAT}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

MODE=apply
case "${1:-}" in
  --check)  MODE=check ;;
  --remove) MODE=remove ;;
  "")       ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

oc whoami >/dev/null 2>&1 || { bad "not logged in"; exit 1; }
oc get ns "$NS" >/dev/null 2>&1 || { bad "namespace $NS does not exist"; exit 1; }

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

MAAS_BASE_URL="${LLM_API_BASE_URL:-}"
if [ -z "$MAAS_BASE_URL" ]; then
  GW=$(oc get gateway maas-default-gateway -n openshift-ingress \
        -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null)
  [ -n "$GW" ] && MAAS_BASE_URL="https://${GW}/v1"
fi

bold "Gen AI Playground — $NS"
info "MaaS base URL: ${MAAS_BASE_URL:-<unset>}"

# ---------------------------------------------------------------- check
if [ "$MODE" = check ]; then
  for r in ogxserver/lsd-genai-playground configmap/llama-stack-config \
           deployment/genai-pgvector service/genai-pgvector \
           secret/genai-pgvector-credentials; do
    oc get "$r" -n "$NS" >/dev/null 2>&1 && ok "$r" || bad "$r missing"
  done
  P=$(oc get ogxserver lsd-genai-playground -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
  info "OGXServer phase: ${P:-absent}"
  exit 0
fi

# ---------------------------------------------------------------- remove
if [ "$MODE" = remove ]; then
  bold "Removing"
  for r in ogxserver/lsd-genai-playground configmap/llama-stack-config \
           configmap/genai-pgvector-init deployment/genai-pgvector \
           service/genai-pgvector secret/genai-pgvector-credentials; do
    oc delete "$r" -n "$NS" --ignore-not-found >/dev/null 2>&1
  done
  info "PVC genai-pgvector-storage kept — delete by hand if you want the data gone"
  ok "removed"
  exit 0
fi

# ---------------------------------------------------------------- apply
[ -d "$MANIFESTS" ] || { bad "missing $MANIFESTS"; exit 1; }
[ -n "$MAAS_BASE_URL" ] || { bad "no MaaS base URL — set LLM_API_BASE_URL in .env"; exit 1; }

bold "1/3  pgvector credentials"
if oc get secret genai-pgvector-credentials -n "$NS" >/dev/null 2>&1; then
  ok "secret exists (not regenerated)"
else
  # Not captured from the old cluster on purpose — credentials do not belong
  # in git. A fresh random password is fine: nothing outside this namespace
  # reads it, and the PVC is empty on a new cluster anyway.
  PW=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
  oc create secret generic genai-pgvector-credentials -n "$NS" \
     --from-literal=username=genai \
     --from-literal=password="$PW" \
     --from-literal=database=genai >/dev/null 2>&1 \
    && ok "generated a new password" || { bad "could not create secret"; exit 1; }
fi

bold "2/3  pgvector + config"
for f in configmap-genai-pgvector-init configmap-llama-stack-config \
         persistentvolumeclaim-genai-pgvector-storage \
         deployment-genai-pgvector service-genai-pgvector; do
  sed "s|{{MAAS_BASE_URL}}|${MAAS_BASE_URL}|g" "$MANIFESTS/$f.json" \
    | oc apply -n "$NS" -f - >/dev/null 2>&1 \
    && ok "$f" || bad "$f failed"
done

echo "  waiting for pgvector..."
oc rollout status deploy/genai-pgvector -n "$NS" --timeout=300s >/dev/null 2>&1 \
  && ok "pgvector ready" || bad "pgvector did not become ready"

bold "3/3  OGXServer"
oc apply -n "$NS" -f "$MANIFESTS/ogxserver-lsd-genai-playground.json" >/dev/null 2>&1 \
  && ok "applied" || bad "failed"

for i in $(seq 1 24); do
  P=$(oc get ogxserver lsd-genai-playground -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$P" = Ready ] && { ok "OGXServer Ready"; break; }
  printf '  [%02d/24] phase=%s\r' "$i" "${P:-pending}"
  sleep 10
done
echo

echo
echo "  Dashboard: Gen AI studio → Playground, with project ${NS} selected."
echo "  The model id is prefixed, e.g. maas-vllm-inference-1/qwen3-235b-a22b —"
echo "  the UI dropdown handles that; only direct API calls need the full id."
echo
echo "  If sending a prompt returns HTTP 500, check the DSC has trustyai:"
echo "  Managed. The send path probes for NemoGuardrails and turns a failed"
echo "  discovery into a 500, even with the guardrails dashboard flag false."
