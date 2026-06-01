#!/usr/bin/env bash
# review-novaspark-projects.sh — Query FantaCo customer DB for NovaSpark AI Labs (CUST200) projects
#
# Reads clusters.csv to resolve cluster IDs to kubeconfig paths.
# Defaults to the first cluster in clusters.csv.
#
# Usage:
#   ./review-novaspark-projects.sh                        # first cluster, agentic-user1
#   ./review-novaspark-projects.sh w6hwm                  # specify cluster
#   ./review-novaspark-projects.sh w6hwm agentic-user3    # specify cluster + namespace

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTERS_CSV="${SCRIPT_DIR}/clusters.csv"
NS="${2:-agentic-user1}"

if [[ ! -f "$CLUSTERS_CSV" ]]; then
  echo "Error: clusters.csv not found at $CLUSTERS_CSV" >&2
  exit 1
fi

# Read clusters.csv into parallel arrays (bash 3 compatible)
CLUSTER_IDS=()
CLUSTER_KCS=()
while IFS=, read -r cluster_id kubeconfig_path; do
  [[ "$cluster_id" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$cluster_id" ]] && continue
  cluster_id=$(echo "$cluster_id" | xargs)
  kubeconfig_path=$(echo "$kubeconfig_path" | xargs)
  CLUSTER_IDS+=("$cluster_id")
  CLUSTER_KCS+=("$kubeconfig_path")
done < "$CLUSTERS_CSV"

CLUSTER="${1:-${CLUSTER_IDS[0]}}"

# Look up kubeconfig for the requested cluster
KC=""
AVAILABLE=""
for i in "${!CLUSTER_IDS[@]}"; do
  [[ -n "$AVAILABLE" ]] && AVAILABLE+=", "
  AVAILABLE+="${CLUSTER_IDS[$i]}"
  if [[ "${CLUSTER_IDS[$i]}" == "$CLUSTER" ]]; then
    KC="${CLUSTER_KCS[$i]}"
  fi
done

if [[ -z "$KC" ]]; then
  echo "Error: cluster '$CLUSTER' not found in clusters.csv" >&2
  echo "Available: $AVAILABLE" >&2
  exit 1
fi

if [[ ! -f "$KC" ]]; then
  echo "Error: kubeconfig not found: $KC" >&2
  exit 1
fi

POD=$(KUBECONFIG="$KC" oc get pods -n "$NS" -l app=postgresql-customer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$POD" ]]; then
  echo "Error: no postgresql-customer pod found in $NS on cluster $CLUSTER" >&2
  exit 1
fi

echo "Cluster: $CLUSTER | Namespace: $NS | Pod: $POD"
echo ""

KUBECONFIG="$KC" oc exec "$POD" -n "$NS" -- bash -c "psql -U postgres -d fantaco_customer -c \"SELECT p.id, p.project_name, p.pod_theme, p.status, p.created_at FROM project p WHERE p.customer_id = 'CUST200' ORDER BY p.id DESC;\""
