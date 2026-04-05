---
name: openclaw-workspace-viewer
description: Add or remove the filebrowser sidecar for browsing the OpenClaw workspace
argument-hint: "[add | remove]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# OpenClaw Workspace File Browser (Sidecar)

Manages a [filebrowser](https://filebrowser.org) sidecar container on the OpenClaw deployment to provide a read-only web UI for browsing the workspace filesystem.

If `$ARGUMENTS` is empty or `add`, run the **Add** flow.
If `$ARGUMENTS` is `remove`, run the **Remove** flow.

---

## Add Flow

### Step 1: Verify OpenShift connectivity

```bash
oc whoami
oc project -q
```

Report the current user and namespace. **Stop if either command fails.**

### Step 2: Verify OpenClaw deployment exists

```bash
oc get deployment openclaw -o name
```

**Stop if the deployment does not exist** — tell the user to run `/fantaco:deploy-openclaw` first.

### Step 3: Check if filebrowser sidecar already exists

```bash
oc get deployment openclaw -o jsonpath='{.spec.template.spec.containers[*].name}'
```

If `filebrowser` is already in the container list, tell the user the sidecar is already deployed, show the route URL, and stop.

### Step 4: Patch the deployment

Add the `filebrowser-tmp` emptyDir volume and the `filebrowser` sidecar container via JSON patch:

```bash
oc patch deployment openclaw --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "filebrowser-tmp",
      "emptyDir": {}
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/-",
    "value": {
      "name": "filebrowser",
      "image": "docker.io/filebrowser/filebrowser:latest",
      "command": ["sh", "-c"],
      "args": [
        "rm -f /database/filebrowser.db && /bin/filebrowser config init --database /database/filebrowser.db --signup=false && /bin/filebrowser users add admin openclaw-demo --database /database/filebrowser.db --perm.admin=false --perm.create=false --perm.delete=false --perm.execute=false --perm.modify=false --perm.rename=false --lockPassword && exec /bin/filebrowser --database /database/filebrowser.db --port 8080 --address 0.0.0.0 --root /srv --log stdout"
      ],
      "ports": [
        { "containerPort": 8080, "protocol": "TCP" }
      ],
      "resources": {
        "requests": { "cpu": "50m", "memory": "64Mi" },
        "limits": { "cpu": "200m", "memory": "128Mi" }
      },
      "securityContext": {
        "allowPrivilegeEscalation": false,
        "capabilities": { "drop": ["ALL"] },
        "runAsNonRoot": true
      },
      "volumeMounts": [
        { "name": "openclaw-data", "mountPath": "/srv", "readOnly": true },
        { "name": "filebrowser-tmp", "mountPath": "/database" }
      ]
    }
  }
]'
```

Key points:
- The PVC `openclaw-data` is mounted **read-only** at `/srv` — the sidecar cannot modify workspace data
- The emptyDir provides writable space for the filebrowser database and config (ephemeral, reinit on restart)
- The binary is at `/bin/filebrowser` (not `/filebrowser`)
- The startup command reinitializes on every pod start (`rm -f` + `config init`) — the database is ephemeral in the emptyDir
- Uses `json` auth — credentials: **admin / openclaw-demo** (filebrowser v2.63.0 does not support `noauth`)
- All write permissions disabled (`create`, `delete`, `modify`, `rename`, `execute` = false)

### Step 5: Create Service

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: openclaw-filebrowser-service
  labels:
    app: openclaw
spec:
  type: ClusterIP
  selector:
    app: openclaw
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
      name: http
EOF
```

### Step 6: Create Route

```bash
oc apply -f - <<'EOF'
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: openclaw-filebrowser-route
  labels:
    app: openclaw
spec:
  to:
    kind: Service
    name: openclaw-filebrowser-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
```

### Step 7: Wait for rollout

```bash
oc rollout status deployment/openclaw --timeout=120s
```

Check pod status:

```bash
oc get pods -l app=openclaw
```

If any container is not ready, show the filebrowser logs:

```bash
oc logs deployment/openclaw -c filebrowser --tail=30
```

### Step 8: Smoke test and open

```bash
ROUTE_HOST=$(oc get route openclaw-filebrowser-route -o jsonpath='{.spec.host}')
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://${ROUTE_HOST}/")
echo "File Browser: https://${ROUTE_HOST}"
echo "HTTP Status: ${HTTP_STATUS}"
```

Open in the default browser:

```bash
open "https://${ROUTE_HOST}"
```

Report the URL and credentials to the user:
- **Username:** `admin`
- **Password:** `openclaw-demo`

---

## Remove Flow

### Step 1: Verify OpenShift connectivity

```bash
oc whoami
oc project -q
```

### Step 2: Delete Route, Service, and ConfigMap

```bash
oc delete route openclaw-filebrowser-route --ignore-not-found
oc delete service openclaw-filebrowser-service --ignore-not-found
oc delete configmap filebrowser-config --ignore-not-found
```

### Step 3: Remove sidecar container from deployment

Dynamically discover the filebrowser container index and remove it:

```bash
INDEX=$(oc get deployment openclaw -o json | python3 -c "
import sys, json
containers = json.load(sys.stdin)['spec']['template']['spec']['containers']
for i, c in enumerate(containers):
    if c['name'] == 'filebrowser':
        print(i)
        break
else:
    print(-1)
")
if [ "$INDEX" -ge 0 ]; then
  oc patch deployment openclaw --type='json' -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/${INDEX}\"}]"
else
  echo "filebrowser container not found — nothing to remove"
fi
```

### Step 4: Remove the emptyDir volume

Dynamically discover the filebrowser-tmp volume index and remove it:

```bash
INDEX=$(oc get deployment openclaw -o json | python3 -c "
import sys, json
volumes = json.load(sys.stdin)['spec']['template']['spec']['volumes']
for i, v in enumerate(volumes):
    if v['name'] == 'filebrowser-tmp':
        print(i)
        break
else:
    print(-1)
")
if [ "$INDEX" -ge 0 ]; then
  oc patch deployment openclaw --type='json' -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/volumes/${INDEX}\"}]"
else
  echo "filebrowser-tmp volume not found — nothing to remove"
fi
```

### Step 5: Remove filebrowser-config volume (if present from older versions)

```bash
INDEX=$(oc get deployment openclaw -o json | python3 -c "
import sys, json
volumes = json.load(sys.stdin)['spec']['template']['spec']['volumes']
for i, v in enumerate(volumes):
    if v['name'] == 'filebrowser-config':
        print(i)
        break
else:
    print(-1)
")
if [ "$INDEX" -ge 0 ]; then
  oc patch deployment openclaw --type='json' -p="[{\"op\":\"remove\",\"path\":\"/spec/template/spec/volumes/${INDEX}\"}]"
else
  echo "filebrowser-config volume not found — nothing to remove"
fi
```

### Step 6: Wait for rollout

```bash
oc rollout status deployment/openclaw --timeout=120s
oc get pods -l app=openclaw
```

Report that the filebrowser sidecar has been removed.
