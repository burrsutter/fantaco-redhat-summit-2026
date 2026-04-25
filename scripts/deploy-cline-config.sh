#!/usr/bin/env bash
# deploy-cline-config.sh
#
# Deploys a cline-config Secret to each dev<N>-devspaces namespace.
# The Secret is auto-mounted into DevWorkspace pods via controller.devfile.io
# annotations, providing Cline extension configuration.
#
# Usage:
#   ./deploy-cline-config.sh              # deploys to dev1..dev20
#   START=17 END=17 ./deploy-cline-config.sh   # deploy to dev17 only
#
# Idempotent — uses oc apply. Skips namespaces that don't exist.
#
# Required: oc logged in to the target cluster

set -euo pipefail

START="${START:-1}"
END="${END:-20}"

if ! oc whoami &>/dev/null; then
  echo "Error: not logged in to OpenShift — run 'oc login' first" >&2
  exit 1
fi
echo "Logged in as: $(oc whoami)"

for i in $(seq "$START" "$END"); do
  NS="dev${i}-devspaces"

  if ! oc get namespace "$NS" &>/dev/null; then
    echo "SKIP  $NS (namespace does not exist)"
    continue
  fi

  echo -n "APPLY $NS ... "
  oc apply -n "$NS" -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: cline-config
  labels:
    controller.devfile.io/mount-to-devworkspace: "true"
  annotations:
    controller.devfile.io/mount-as: subpath
    controller.devfile.io/mount-path: /home/user/.cline-config
    controller.devfile.io/mount-to-devworkspace: "true"
    controller.devfile.io/watch-secret: "true"
type: Opaque
stringData:
  cline-settings.json: |
    {
      "apiProvider": "openai",
      "openAiBaseUrl": "https://litellm-prod.apps.maas.redhatworkshops.io/v1",
      "openAiApiKey": "sk-XxmN30_Da-H67Cnmw5zMFg",
      "openAiModelId": "claude-opus-4-6",
      "openAiCustomModelInfo": {
        "maxTokens": 16384,
        "contextWindow": 200000,
        "supportsImages": true,
        "supportsPromptCache": true
      }
    }
EOF

  echo "done"
done

echo ""
echo "Cline config deployment complete (dev${START}..dev${END})."
