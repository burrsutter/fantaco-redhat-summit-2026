#!/usr/bin/env bash
# Shared environment variables for the Route53/ALB setup.
# Source this file before running any other script:
#   source ./00-env.sh
#
# Multi-site support:
#   SITE_NAME=backup ./08-launch-ec2.sh
#   Creates separate state dir (.state/backup/) and loads site-specific
#   resource names (domain, S3 bucket, EC2 tag, SG, IAM role, ALB/TG).

export AWS_REGION=us-east-1
export HAPROXY_PORT=8080
export ROUTE_CATALOG_KEY=route-lb/routes.csv

# OpenShift — update these when the cluster changes
export OPENSHIFT_ROUTER_DNS=router-default.apps.ocp.hb7hq.sandbox1319.opentlc.com
export OPENSHIFT_PROBE_ROUTE_HOST=route-lb-probe.apps.ocp.hb7hq.sandbox1319.opentlc.com

# EC2
export INSTANCE_TYPE=c7i.large

# ── Site config ──────────────────────────────────────────────────
# Look for site env files in the clawoperator-openclaw/sites/ directory
_LB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SITE_ENV="${_LB_SCRIPT_DIR}/../../clawoperator-openclaw/sites/${SITE_NAME:-primary}.env"

if [[ -f "$_SITE_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$_SITE_ENV"
fi

# Apply defaults — match primary site values for backward compat
export DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
export CONFIG_BUCKET="${BROKER_S3_BUCKET:-yougetaclaw-route-lb-config}"
export EC2_TAG_NAME="${BROKER_EC2_TAG:-route-lb-haproxy}"
export HAPROXY_SG_NAME="${HAPROXY_SG_NAME:-route-lb-haproxy}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME:-route-lb-haproxy}"
export ALB_NAME="${ALB_NAME:-route-lb-alb}"
export TG_NAME="${TG_NAME:-route-lb-haproxy-tg}"

# Per-site state directory — keeps primary and backup state separate
export SITE_NAME="${SITE_NAME:-primary}"
export STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state/${SITE_NAME}"
mkdir -p "$STATE_DIR"
