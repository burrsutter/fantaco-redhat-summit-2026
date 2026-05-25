#!/usr/bin/env bash
# cleanup-loki-s3.sh — Delete orphaned Loki S3 buckets from terminated clusters
#
# Lists all openclaw-loki-* buckets, identifies which belong to the current
# cluster (if logged in), and deletes the rest.
#
# Usage:
#   ./cleanup-loki-s3.sh           # Interactive — prompts before deleting
#   ./cleanup-loki-s3.sh --dry-run # List buckets only, don't delete
#   ./cleanup-loki-s3.sh --all     # Delete ALL openclaw-loki-* buckets (including current cluster)
#
# Requires: aws CLI configured with permissions to list/delete S3 buckets

set -euo pipefail

DRY_RUN=false
DELETE_ALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --all)     DELETE_ALL=true ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [--all]"
      echo "  --dry-run  List buckets only, don't delete"
      echo "  --all      Delete ALL openclaw-loki-* buckets (including current cluster)"
      exit 0
      ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Get current cluster's bucket (if logged into OpenShift) ---
CURRENT_BUCKET=""
if oc whoami &>/dev/null; then
  CLUSTER_ID=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "")
  if [[ -n "$CLUSTER_ID" ]]; then
    CLUSTER_SUFFIX="${CLUSTER_ID: -8}"
    CURRENT_BUCKET="openclaw-loki-${CLUSTER_SUFFIX}"
    echo -e "Current cluster bucket: ${GREEN}${CURRENT_BUCKET}${RESET}"
  fi
else
  echo -e "${YELLOW}Not logged into OpenShift — cannot identify current cluster bucket${RESET}"
fi

# --- List all openclaw-loki-* buckets ---
echo ""
echo "=== Scanning S3 for openclaw-loki-* buckets ==="
BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `openclaw-loki-`)].{Name:Name,Created:CreationDate}' --output text 2>/dev/null || true)

if [[ -z "$BUCKETS" ]]; then
  echo "No openclaw-loki-* buckets found."
  exit 0
fi

# Parse into arrays
ORPHANED=()
KEPT=()
while IFS=$'\t' read -r created name; do
  if [[ "$name" == "$CURRENT_BUCKET" ]] && [[ "$DELETE_ALL" == "false" ]]; then
    KEPT+=("$name")
    echo -e "  ${GREEN}KEEP${RESET}   $name  (created $created — current cluster)"
  else
    ORPHANED+=("$name")
    if [[ "$name" == "$CURRENT_BUCKET" ]]; then
      echo -e "  ${RED}DELETE${RESET} $name  (created $created — current cluster, --all flag)"
    else
      echo -e "  ${RED}DELETE${RESET} $name  (created $created — orphaned)"
    fi
  fi
done <<< "$BUCKETS"

echo ""
echo "Found ${#ORPHANED[@]} bucket(s) to delete, ${#KEPT[@]} to keep."

if [[ ${#ORPHANED[@]} -eq 0 ]]; then
  echo "Nothing to clean up."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}Dry run — no buckets deleted.${RESET}"
  exit 0
fi

# --- Confirm ---
echo ""
echo -e "${BOLD}This will permanently delete ${#ORPHANED[@]} bucket(s) and all their contents.${RESET}"
read -r -p "Proceed? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Delete ---
for bucket in "${ORPHANED[@]}"; do
  echo ""
  echo -e "Deleting ${RED}${bucket}${RESET}..."
  # Empty the bucket first (required before deletion)
  aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true
  # Delete the bucket
  if aws s3api delete-bucket --bucket "$bucket" 2>/dev/null; then
    echo -e "  ${GREEN}Deleted${RESET}"
  else
    echo -e "  ${RED}Failed to delete${RESET} (may have versioning — try: aws s3 rb s3://${bucket} --force)"
  fi
done

echo ""
echo -e "${GREEN}Cleanup complete.${RESET} Deleted ${#ORPHANED[@]} bucket(s)."
