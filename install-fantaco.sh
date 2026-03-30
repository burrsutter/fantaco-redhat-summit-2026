#!/bin/bash

LITELLM_URL="https://litellm-prod.apps.maas.redhatworkshops.io"

if [ -z "$API_KEY" ]; then
  echo "Error: API_KEY environment variable is required."
  echo "Usage: API_KEY=<your-litellm-key> ./install-fantaco.sh"
  exit 1
fi

# Verify connectivity
echo "Verifying LiteLLM connectivity..."
HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" \
  "$LITELLM_URL/v1/models" \
  -H "Authorization: Bearer $API_KEY")

if [ "$HTTP_STATUS" != "200" ]; then
  echo "Error: LiteLLM returned HTTP $HTTP_STATUS. Check your API_KEY."
  exit 1
fi
echo "LiteLLM connection verified."

helm install fantaco-app ./helm/fantaco-app
helm install fantaco-mcp ./helm/fantaco-mcp
helm install fantaco-agent ./helm/fantaco-agent --set langgraphFastapi.env.apiKey="$API_KEY"
