#!/bin/bash
# Converts CHAT_URL to CHAT_TRACE_URL
# Usage: source ./convert_url.sh
#        or: ./convert_url.sh
#
# Input (from env var):
#   CHAT_URL=http://chatbot-agentic-user1.apps.cluster-s5kx7.dynamic.redhatworkshops.io
#
# Output:
#   CHAT_TRACE_URL=https://chatbot-8002-showroom-s5kx7-1-user1.apps.cluster-s5kx7.dynamic.redhatworkshops.io/
#
# Exports: CHAT_TRACE_URL

if [ -z "$CHAT_URL" ]; then
    echo "Error: CHAT_URL environment variable is not set"
    exit 1
fi

# Extract cluster ID from the URL (e.g., s5kx7 from cluster-s5kx7)
CLUSTER_ID=$(echo "$CHAT_URL" | sed -n 's/.*\.apps\.cluster-\([^.]*\)\..*/\1/p')

if [ -z "$CLUSTER_ID" ]; then
    echo "Error: Could not extract cluster ID from CHAT_URL"
    echo "Expected pattern: ...apps.cluster-<cluster_id>.dynamic..."
    exit 1
fi

# Extract user from the URL (e.g., user1 from agentic-user1)
USER=$(echo "$CHAT_URL" | sed -n 's/.*agentic-\([^.]*\)\..*/\1/p')

if [ -z "$USER" ]; then
    echo "Error: Could not extract user from CHAT_URL"
    echo "Expected pattern: ...agentic-<user>.apps..."
    exit 1
fi

# Construct the CHAT_TRACE_URL
# Format: https://chatbot-8002-showroom-<cluster_id>-1-<user>.apps.cluster-<cluster_id>.dynamic.redhatworkshops.io/
CHAT_TRACE_URL="https://chatbot-8002-showroom-${CLUSTER_ID}-1-${USER}.apps.cluster-${CLUSTER_ID}.dynamic.redhatworkshops.io/"

export CHAT_TRACE_URL

echo "CHAT_TRACE_URL=${CHAT_TRACE_URL}"
