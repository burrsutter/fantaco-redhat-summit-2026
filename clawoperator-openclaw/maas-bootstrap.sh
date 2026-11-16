#!/usr/bin/env bash
#
# maas-bootstrap.sh — make RHOAI Models-as-a-Service actually work.
#
# Enabling the component is NOT enough. A DataScienceCluster export cannot carry
# these, and each one only surfaces AFTER the previous is fixed, so a naive
# attempt looks like three unrelated failures:
#
#   1. Gateway `maas-default-gateway` in openshift-ingress   (docs §1.3; nobody creates it)
#   2. PostgreSQL + secret `maas-db-config`                  ("MaaS API cannot start without a database")
#   3. Namespace labels so HTTPRoutes can attach to the gateway
#   4. Red Hat Connectivity Link + a `Kuadrant` CR            (AuthConfig + TokenRateLimitPolicy)
#   5. The provider API-key secret must be LABELLED           (see the closing note)
#
# Learned the hard way on rosa-7s2hf 2026-11-12/13 (1-3), and on rosa-tztnl
# 2026-11-16 (4-5, found while wiring an external model end to end). The first
# version of this script claimed there were three prerequisites; there are five.
#
# Usage:
#   ./maas-bootstrap.sh              # run all steps, idempotent
#   ./maas-bootstrap.sh --check      # report state, change nothing
#
set -uo pipefail

NS_INFRA="${NS_INFRA:-redhat-ai-gateway-infra}"
NS_TENANT="${NS_TENANT:-models-as-a-service}"
GW_NS="${GW_NS:-openshift-ingress}"
GW_NAME="${GW_NAME:-maas-default-gateway}"
GW_LABEL="maas.opendatahub.io/gateway-access-${NS_TENANT}"
# Extra namespaces that must reach the gateway (model namespaces, demo namespaces)
EXTRA_NS="${EXTRA_NS:-}"

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }

# ---------------------------------------------------------------- preflight
bold "0/4  Preflight"

oc whoami >/dev/null 2>&1 || { bad "not logged in to a cluster"; exit 1; }
ok "logged in as $(oc whoami)"

DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
[ -z "$DOMAIN" ] && { bad "could not read cluster ingress domain"; exit 1; }
GW_HOST="${GW_HOST:-maas.${DOMAIN}}"
ok "cluster domain: $DOMAIN"
info "gateway hostname will be: $GW_HOST"

# GatewayClass: prefer openshift-default (what the docs name), else any class on
# the OpenShift gateway controller — on RHOAI clusters that is usually
# data-science-gateway-class.
GW_CLASS=$(oc get gatewayclass -o json 2>/dev/null | python3 -c "
import sys, json
items = json.load(sys.stdin).get('items', [])
ctrl = 'openshift.io/gateway-controller/v1'
names = [i['metadata']['name'] for i in items if i['spec'].get('controllerName') == ctrl]
print('openshift-default' if 'openshift-default' in names else (names[0] if names else ''))
" 2>/dev/null)
[ -z "$GW_CLASS" ] && { bad "no GatewayClass on controller openshift.io/gateway-controller/v1"; \
                        info "Gateway API must be enabled on the cluster first"; exit 1; }
ok "gatewayclass: $GW_CLASS"

# TLS: prefer the cluster's DEFAULT INGRESS WILDCARD cert over service-ca.
#
# service-ca was the original choice here and it is wrong for anything outside
# the cluster. It mints a cert whose subject is the internal Service name and
# whose issuer is openshift-service-serving-signer, so every external client
# fails verification and needs curl -k. On ROSA the default ingress cert is a
# real Let's Encrypt wildcard for *.apps.<domain>, which covers the gateway
# hostname and is trusted everywhere. That matters the moment real users (or
# 100 demo seats) call the gateway rather than just you with -k.
#
# The secret is type Opaque rather than kubernetes.io/tls, which looks like it
# should be rejected by Gateway API — it is accepted, and the listener reports
# ResolvedRefs=True. Copying it into a kubernetes.io/tls secret is unnecessary.
DEFAULT_CERT=$(oc get ingresscontroller default -n openshift-ingress-operator \
  -o jsonpath='{.spec.defaultCertificate.name}' 2>/dev/null)
if [ -n "$DEFAULT_CERT" ] && oc get secret "$DEFAULT_CERT" -n "$GW_NS" >/dev/null 2>&1; then
  TLS_SECRET="$DEFAULT_CERT"
  USE_SERVICE_CA=0
  ok "TLS: using default ingress wildcard cert ($TLS_SECRET)"
else
  TLS_SECRET="${GW_NAME}-service-tls"
  USE_SERVICE_CA=1
  bad "no default ingress certificate found — falling back to service-ca"
  info "clients will need to trust the service CA, or use curl -k"
fi

if oc get crd aitenants.maas.opendatahub.io >/dev/null 2>&1; then
  ok "MaaS CRDs present (aigateway.modelsAsAService is Managed)"
else
  bad "MaaS CRDs missing — enable the component first:"
  info "oc patch dsc <name> --type=merge -p '{\"spec\":{\"components\":{\"aigateway\":{\"managementState\":\"Managed\",\"modelsAsAService\":{\"managementState\":\"Managed\"}}}}}'"
  info "NOTE: kserve.modelsAsService is deprecated and cannot be re-enabled once Removed."
  [ "$CHECK_ONLY" = 1 ] || exit 1
fi

if [ "$CHECK_ONLY" = 1 ]; then
  bold "check only — current state"
  oc get gateway "$GW_NAME" -n "$GW_NS" 2>/dev/null || bad "gateway $GW_NAME missing"
  oc get secret maas-db-config -n "$NS_INFRA" >/dev/null 2>&1 && ok "maas-db-config present" || bad "maas-db-config missing"
  oc get aitenant -A 2>/dev/null
  exit 0
fi

# ---------------------------------------------------------------- 1. gateway
bold "1/4  Gateway $GW_NAME"

if oc get gateway "$GW_NAME" -n "$GW_NS" >/dev/null 2>&1; then
  ok "already exists"
else
  oc apply -f - >/dev/null <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: $GW_NAME
  namespace: $GW_NS
  annotations:
    # Stops the ODH Model Controller overriding MaaS-managed auth policies
    opendatahub.io/managed: "false"
    # Enables TLS between the Gateway and Authorino
    security.opendatahub.io/authorino-tls-bootstrap: "true"
spec:
  gatewayClassName: $GW_CLASS
  listeners:
    - name: https
      hostname: "$GW_HOST"
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              $GW_LABEL: "true"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: ${TLS_SECRET}
EOF
  ok "created"
fi

# Only needed on the fallback path. The docs reference router-certs-default,
# which does not exist on ROSA; service-ca is the workable substitute, but see
# the note above about why it is second choice.
if [ "$USE_SERVICE_CA" = 0 ]; then
  bold "1b/4  TLS"
  ok "using $TLS_SECRET — nothing to mint"
else
bold "1b/4  TLS via service-ca (fallback)"
for i in $(seq 1 24); do
  SVC=$(oc get svc -n "$GW_NS" -l "gateway.networking.k8s.io/gateway-name=$GW_NAME" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -n "$SVC" ] && break
  sleep 5
done
if [ -z "${SVC:-}" ]; then
  bad "gateway controller never created a Service — cannot mint a cert"
else
  oc annotate svc "$SVC" -n "$GW_NS" \
    "service.beta.openshift.io/serving-cert-secret-name=${TLS_SECRET}" --overwrite >/dev/null
  ok "annotated $SVC"
  for i in $(seq 1 24); do
    oc get secret "${TLS_SECRET}" -n "$GW_NS" >/dev/null 2>&1 && { ok "cert secret minted"; break; }
    sleep 5
  done
fi
fi

# ---------------------------------------------------------------- 2. database
bold "2/4  PostgreSQL + maas-db-config"

oc get ns "$NS_INFRA" >/dev/null 2>&1 || oc create ns "$NS_INFRA" >/dev/null

if oc get secret maas-db-config -n "$NS_INFRA" >/dev/null 2>&1; then
  ok "maas-db-config already exists — leaving database alone"
else
  PW=$(openssl rand -hex 16)
  oc apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: maas-postgres-pvc, namespace: $NS_INFRA}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 10Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: postgres, namespace: $NS_INFRA}
spec:
  replicas: 1
  selector: {matchLabels: {app: postgres}}
  template:
    metadata: {labels: {app: postgres}}
    spec:
      containers:
      - name: postgres
        image: registry.redhat.io/rhel9/postgresql-16
        env:
        - {name: POSTGRESQL_USER,     value: maas}
        - {name: POSTGRESQL_PASSWORD, value: "$PW"}
        - {name: POSTGRESQL_DATABASE, value: maas}
        ports: [{containerPort: 5432}]
        volumeMounts: [{name: data, mountPath: /var/lib/pgsql/data}]
        resources:
          requests: {cpu: 100m, memory: 512Mi}
          limits:   {cpu: "1",  memory: 2Gi}
      volumes:
      - name: data
        persistentVolumeClaim: {claimName: maas-postgres-pvc}
---
apiVersion: v1
kind: Service
metadata: {name: postgres, namespace: $NS_INFRA}
spec:
  selector: {app: postgres}
  ports: [{port: 5432, targetPort: 5432}]
---
apiVersion: v1
kind: Secret
metadata: {name: maas-db-config, namespace: $NS_INFRA}
stringData:
  DB_CONNECTION_URL: "postgresql://maas:$PW@postgres.$NS_INFRA.svc.cluster.local:5432/maas?sslmode=disable"
EOF
  ok "deployed postgres and wrote maas-db-config"
fi

oc rollout status deploy/postgres -n "$NS_INFRA" --timeout=180s >/dev/null 2>&1 \
  && ok "postgres ready" || bad "postgres not ready yet"

# ---------------------------------------------------------------- 3. labels
bold "3/4  Namespace labels for gateway access"
for ns in "$NS_INFRA" "$NS_TENANT" $EXTRA_NS; do
  if oc get ns "$ns" >/dev/null 2>&1; then
    oc label ns "$ns" "$GW_LABEL=true" --overwrite >/dev/null && ok "$ns"
  else
    info "$ns does not exist yet — label it when it does"
  fi
done

# ------------------------------------------------- 3b. Connectivity Link
# MaaS needs AuthConfig (authorino.kuadrant.io/v1beta3) and TokenRateLimitPolicy
# (kuadrant.io/v1alpha1). Both come from Red Hat Connectivity Link (RHCL).
#
# Naming confusion worth stating plainly: RHCL *is* the supported Kuadrant. The
# operator package is `rhcl-operator` in redhat-operators, but its API group is
# kuadrant.io and the CR that activates the control plane is `kind: Kuadrant`.
# Using the Community `kuadrant-operator` instead is the wrong choice.
#
# DO NOT pre-install authorino-operator on its own. RHCL pins an exact Authorino
# version (rhcl 1.4.3 -> authorino 1.4.3). A standalone subscription resolving to
# 1.4.4 makes RHCL unresolvable with ConstraintsNotSatisfiable, and you then have
# to delete the subscription AND its CSV to recover. Let RHCL pull it in.
bold "3b/4  Red Hat Connectivity Link"

if oc get crd tokenratelimitpolicies.kuadrant.io >/dev/null 2>&1; then
  ok "Connectivity Link CRDs present"
else
  info "installing rhcl-operator (pulls Authorino + Limitador as dependencies)"
  oc apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhcl-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: rhcl-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
  for i in $(seq 1 30); do
    oc get crd tokenratelimitpolicies.kuadrant.io >/dev/null 2>&1 && break
    sleep 15
  done
  oc get crd tokenratelimitpolicies.kuadrant.io >/dev/null 2>&1 \
    && ok "Connectivity Link installed" || bad "Connectivity Link did not install in time"
fi

# The Kuadrant CR actually deploys Authorino and Limitador. Without it the
# MaaSAuthPolicy sits at Ready=Unknown saying "kuadrant is not installed".
oc get ns kuadrant-system >/dev/null 2>&1 || oc create ns kuadrant-system >/dev/null
oc apply -f - >/dev/null <<'EOF'
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
EOF
oc wait Kuadrant -n kuadrant-system kuadrant --for=condition=Ready --timeout=10m >/dev/null 2>&1 \
  && ok "Kuadrant ready" || bad "Kuadrant not ready"

# Authorino needs TLS on its listener, via a service-ca cert. This one IS
# internal traffic only, so service-ca is correct here.
oc annotate svc/authorino-authorino-authorization -n kuadrant-system \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert --overwrite >/dev/null 2>&1
sleep 3
oc apply -f - >/dev/null <<'EOF'
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
  name: authorino
  namespace: kuadrant-system
spec:
  replicas: 1
  clusterWide: true
  listener:
    tls:
      enabled: true
      certSecretRef:
        name: authorino-server-cert
  oidcServer:
    tls:
      enabled: false
EOF
oc wait --for=condition=ready pod -l authorino-resource=authorino -n kuadrant-system --timeout=180s >/dev/null 2>&1 \
  && ok "authorino ready" || bad "authorino not ready"

# RHOAI is almost always installed BEFORE Connectivity Link, and its controllers
# cache the absence of the Kuadrant APIs. Without this restart the MaaSAuthPolicy
# never leaves Ready=Unknown. Documented, easy to miss, cheap to always do.
oc delete pod -n redhat-ods-applications -l app=odh-model-controller >/dev/null 2>&1
oc delete pod -n redhat-ods-applications -l control-plane=kserve-controller-manager >/dev/null 2>&1
ok "restarted odh-model-controller and kserve-controller-manager"

# ---------------------------------------------------------------- 4. wait
bold "4/4  Waiting for MaaS to go Ready"
DSC=$(oc get dsc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
for i in $(seq 1 30); do
  A=$(oc get aitenant "$NS_TENANT" -n ai-tenants -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  M=$(oc get dsc "$DSC" -o json 2>/dev/null | python3 -c "
import sys, json
try:
    for c in json.load(sys.stdin)['status']['conditions']:
        if 'AsAService' in c['type']:
            print(c['status']); break
except Exception:
    pass" 2>/dev/null)
  printf '  [%02d] AITenantReady=%-5s ModelsAsAServiceReady=%-5s\n' "$i" "${A:-?}" "${M:-?}"
  [ "$A" = "True" ] && { ok "MaaS is ready"; break; }
  sleep 15
done

bold "Endpoint"
echo "  https://${GW_HOST}/v1/models"
echo
echo "  Next: register the external model (ExternalProvider -> ExternalModel -> MaaSModelRef),"
echo "  then a MaaSSubscription and MaaSAuthPolicy so users can actually call it."
echo "  See operator-patches/maas-over-maas-qwen.yaml and maas-over-maas-governance.yaml."
echo
echo "  REMEMBER: label the provider API-key secret, or inference fails with"
echo "  \"authType 'apikey' credentials not found\" while every CR still reads Ready:"
echo "    oc label secret <name> inference.llm-d.ai/ipp-managed=true -n <model-ns>"
