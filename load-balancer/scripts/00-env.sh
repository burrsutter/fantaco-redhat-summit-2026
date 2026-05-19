#!/usr/bin/env bash
# Shared environment variables for the yougetaclaw.com Route53/ALB setup.
# Source this file before running any other script:
#   source ./00-env.sh

export AWS_REGION=us-east-1
export DOMAIN=yougetaclaw.com
export CONFIG_BUCKET=yougetaclaw-route-lb-config
export ROUTE_CATALOG_KEY=route-lb/routes.csv
export HAPROXY_PORT=8080

# These are written by earlier scripts and read by later ones.
export STATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state"
mkdir -p "$STATE_DIR"
