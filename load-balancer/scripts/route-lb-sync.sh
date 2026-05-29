#!/bin/bash
# route-lb-sync — Download routes.csv from S3 and rebuild HAProxy config
#
# Generates a complete haproxy.cfg with per-route backends. Each backend
# derives its router DNS from the route hostname, so routes from different
# OpenShift clusters are routed to the correct cluster's router.
#
# Deployed to EC2 at /usr/local/bin/route-lb-sync by update-broker.sh
# Also baked into EC2 user-data by 08-launch-ec2.sh (initial deploy)
set -euo pipefail

source /etc/route-lb/env

DOMAIN="${COOKIE_DOMAIN:-yougetaclaw.com}"
HAPROXY_PORT="${HAPROXY_PORT:-8080}"

TMPCSV=$(mktemp)
trap 'rm -f "$TMPCSV"' EXIT

aws s3 cp "s3://${CONFIG_BUCKET}/${ROUTE_CATALOG_KEY}" "$TMPCSV"

# Build routes.map and per-route backends from CSV
TMPMAP=$(mktemp)
trap 'rm -f "$TMPCSV" "$TMPMAP"' EXIT

BACKENDS=""
while IFS=, read -r public_host openshift_route_host enabled _rest; do
  [[ "$public_host" =~ ^#.* ]] && continue
  [[ "$public_host" == "public_host" ]] && continue
  [[ "$enabled" != "true" ]] && continue

  BK_NAME="bk_${public_host//[^a-zA-Z0-9]/_}"
  echo "${public_host} ${BK_NAME}" >> "$TMPMAP"

  # Derive router DNS from route host: strip first label, prepend router-default
  ROUTER_DNS=$(echo "$openshift_route_host" | sed 's/^[^.]*\./router-default./')

  BACKENDS+="
backend ${BK_NAME}
    http-request set-header Host ${openshift_route_host}
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Host ${public_host}
    server s1 ${ROUTER_DNS}:443 ssl verify none sni str(${openshift_route_host}) init-addr last,libc,none
"
done < "$TMPCSV"

# Atomically update routes.map
cp "$TMPMAP" /etc/haproxy/routes.map.new
mv /etc/haproxy/routes.map.new /etc/haproxy/routes.map

# Generate complete haproxy.cfg
cat > /etc/haproxy/haproxy.cfg.new <<HAPCFG
global
    log stdout format raw local0
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  forwardfor
    timeout connect 5s
    timeout client  60s
    timeout server  60s
    timeout tunnel  4h

frontend http_in
    bind *:${HAPROXY_PORT}

    # Bare domain goes to session broker
    acl is_bare_domain hdr(host) -i ${DOMAIN}
    use_backend broker if is_bare_domain

    # Route to per-cluster backend based on host→backend map
    use_backend %[req.hdr(host),lower,map_str(/etc/haproxy/routes.map)]
    default_backend bk_default

backend bk_default
    http-request return status 404 content-type text/plain string "no route configured for this host"

backend broker
    server broker 127.0.0.1:3000

listen health
    bind *:8081
    http-request return status 200 content-type text/plain string "ready"
${BACKENDS}
HAPCFG

mv /etc/haproxy/haproxy.cfg.new /etc/haproxy/haproxy.cfg

# Reload HAProxy
systemctl reload haproxy || systemctl restart haproxy
echo "route-lb-sync complete: $(wc -l < /etc/haproxy/routes.map) routes"
