#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-env.sh"

BROKER_DIR="$SCRIPT_DIR/../broker"

if [[ ! -f "$BROKER_DIR/package.json" ]]; then
  echo "ERROR: broker/package.json not found. Build the broker first." >&2
  exit 1
fi

echo "==> Packaging broker (source only, deps installed on EC2)"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Copy broker source files (no node_modules — native deps must build on target arch)
mkdir -p "$TMPDIR/broker/pages"
cp "$BROKER_DIR/package.json" "$BROKER_DIR/package-lock.json" "$TMPDIR/broker/"
cp "$BROKER_DIR/server.js" "$BROKER_DIR/app.js" "$BROKER_DIR/db.js" "$BROKER_DIR/routes-csv.js" "$TMPDIR/broker/"
cp "$BROKER_DIR/pages/"*.html "$TMPDIR/broker/pages/"

# Create tarball
tar -czf "$TMPDIR/broker.tar.gz" -C "$TMPDIR" broker/

echo "==> Uploading broker.tar.gz to s3://$CONFIG_BUCKET/route-lb/broker.tar.gz"
aws s3 cp "$TMPDIR/broker.tar.gz" "s3://$CONFIG_BUCKET/route-lb/broker.tar.gz"

SIZE=$(wc -c < "$TMPDIR/broker.tar.gz")
echo "Uploaded ($SIZE bytes)"
