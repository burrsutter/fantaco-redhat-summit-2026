# Claw operator MCP ordering fix

The pinned `claw-operator:554d988` image writes `mcpBucketAServers` from a Go map without sorting. With multiple URL based MCP servers, repeated reconciliations can change the gateway ConfigMap hash and restart gateway pods indefinitely. Apply [0001-sort-mcp-bucket-a.patch](0001-sort-mcp-bucket-a.patch) to the matching operator source before building an image for each cluster.

From `clawoperator-openclaw`, with `KUBECONFIG` pointing at the intended cluster:

```bash
export CLAW_OPERATOR_HOME="${CLAW_OPERATOR_HOME:-../../claw-operator}"
git -C "$CLAW_OPERATOR_HOME" apply "$PWD/operator-patches/0001-sort-mcp-bucket-a.patch"
oc new-build --binary=true --strategy=docker --name=claw-operator-fixed -n claw-operator
oc patch bc claw-operator-fixed -n claw-operator --type=merge -p '{"spec":{"strategy":{"dockerStrategy":{"dockerfilePath":"Containerfile"}}}}'
oc patch bc claw-operator-fixed -n claw-operator --type=merge -p '{"spec":{"resources":{"requests":{"ephemeral-storage":"10Gi","memory":"2Gi","cpu":"500m"},"limits":{"ephemeral-storage":"30Gi","memory":"8Gi","cpu":"4"}}}}'
oc start-build claw-operator-fixed -n claw-operator --from-dir="$CLAW_OPERATOR_HOME" --exclude='(^|/)(\.git|bin|build)(/|$)' --wait
oc set image deployment/claw-operator-controller-manager -n claw-operator manager=image-registry.openshift-image-registry.svc:5000/claw-operator/claw-operator-fixed:latest
oc rollout status deployment/claw-operator-controller-manager -n claw-operator --timeout=180s
```

Build and deploy independently on each cluster. The `git apply` step should be run once per checkout; skip it if already applied.
If build pods land on a control plane node with low free disk, set `spec.nodeSelector.kubernetes.io/hostname` on the BuildConfig to the name of a Ready worker node and start the build again.
