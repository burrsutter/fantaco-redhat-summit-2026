#!/usr/bin/env bash
# resolve-site.sh — Load per-site config (domain, S3 bucket, AWS resource names)
#
# Source this after argument parsing in any script that supports --site:
#   source "${SCRIPT_DIR}/sites/resolve-site.sh"
#
# Expects:
#   SITE_NAME   — set by --site flag (default: primary)
#   SCRIPT_DIR  — set by the calling script
#
# Sets / overrides:
#   BROKER_DOMAIN, BROKER_S3_BUCKET, BROKER_EC2_TAG
#   ALB_NAME, TG_NAME, HAPROXY_SG_NAME, IAM_ROLE_NAME
#   CLUSTERS_CSV (points to sites/<name>.clusters.csv if it exists)

SITE_NAME="${SITE_NAME:-primary}"

_SITES_DIR="${SCRIPT_DIR}/sites"
_SITE_ENV="${_SITES_DIR}/${SITE_NAME}.env"

if [[ -f "$_SITE_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$_SITE_ENV"
else
  if [[ "$SITE_NAME" != "primary" ]]; then
    echo "Error: site config not found: ${_SITE_ENV}" >&2
    exit 1
  fi
fi

# Use per-site clusters.csv if it exists, otherwise fall back to repo root
_SITE_CLUSTERS="${_SITES_DIR}/${SITE_NAME}.clusters.csv"
if [[ -f "$_SITE_CLUSTERS" ]]; then
  CLUSTERS_CSV="$_SITE_CLUSTERS"
else
  CLUSTERS_CSV="${CLUSTERS_CSV:-${SCRIPT_DIR}/clusters.csv}"
fi

# Per-site routes.csv — keeps primary and backup routes distinct
ROUTES_CSV="${SCRIPT_DIR}/routes-${SITE_NAME}.csv"

# Apply defaults for any vars not set by the site env file
BROKER_DOMAIN="${BROKER_DOMAIN:-yougetaclaw.com}"
BROKER_S3_BUCKET="${BROKER_S3_BUCKET:-yougetaclaw-route-lb-config}"
BROKER_EC2_TAG="${BROKER_EC2_TAG:-route-lb-haproxy}"
ALB_NAME="${ALB_NAME:-route-lb-alb}"
TG_NAME="${TG_NAME:-route-lb-haproxy-tg}"
HAPROXY_SG_NAME="${HAPROXY_SG_NAME:-route-lb-haproxy}"
IAM_ROLE_NAME="${IAM_ROLE_NAME:-route-lb-haproxy}"
