# Cluster Template — Reference Configuration

Use this document to verify that a new or additional OpenShift cluster is configured approximately the same as the reference cluster used for the Red Hat Summit 2026 demo.

## Reference Cluster

- **Domain:** `sandbox2526` — `apps.ocp.fr9sv.sandbox2526.opentlc.com`
- **API:** `https://api.ocp.fr9sv.sandbox2526.opentlc.com:6443`
- **Platform:** AWS (ROSA / OCP on AWS)
- **OpenShift version:** 4.x

## Node Summary

| Role | Count | Instance Type | CPUs per Node | Memory per Node |
|------|-------|---------------|---------------|-----------------|
| Dedicated worker | 8 | `m5a.4xlarge` | 16 cores | ~62 Gi |
| Control-plane + worker (dual-role) | 3 | `m6a.4xlarge` | 16 cores | ~62 Gi |
| **Total** | **11** | | **176 cores** | **~678 Gi** |

## Expected Totals (Workers)

These are the totals across all nodes with the `worker` role (including dual-role control-plane nodes):

| Resource | Capacity | Allocatable |
|----------|----------|-------------|
| CPUs | 176 cores | 170 cores |
| Memory | 678 Gi | 666 Gi |
| Max pods | 2,750 | — |

## Minimum Requirements

A cluster intended to run the same workload should meet or exceed these minimums:

| Resource | Minimum | Notes |
|----------|---------|-------|
| Worker nodes | 6 | Enough to spread 22 agentic-user namespaces |
| Total worker CPUs (allocatable) | 120 cores | Each namespace quota: 3 cores request / 8 cores limit |
| Total worker memory (allocatable) | 400 Gi | Each namespace quota: 4 Gi request / 10 Gi limit |
| Max pods (total) | 1,500 | Each namespace quota: 16 pods |
| Storage class | `gp3-csi` (or equivalent RWO) | Each namespace gets a 10 Gi PVC |

## Per-Namespace Resource Quotas

Applied by `set-namespace-quotas.sh`:

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 3 cores | 8 cores |
| Memory | 4 Gi | 10 Gi |
| Pods | 16 | — |

With 22 namespaces, worst-case totals:
- CPU requests: 66 cores, limits: 176 cores
- Memory requests: 88 Gi, limits: 220 Gi
- Pods: 352

## Checklist for Validating a New Cluster

When analyzing a new cluster, verify the following:

1. **Node count and roles**
   - [ ] At least 6 worker nodes (or dual-role nodes with worker label)
   - [ ] All worker nodes in `Ready` status

2. **Instance sizing**
   - [ ] Each worker node has >= 16 CPUs
   - [ ] Each worker node has >= 60 Gi memory
   - [ ] Instance types are compute-balanced (e.g., `m5a.4xlarge`, `m6a.4xlarge`, or equivalent)

3. **Aggregate capacity**
   - [ ] Total allocatable CPUs >= 120 cores
   - [ ] Total allocatable memory >= 400 Gi
   - [ ] Total pod capacity >= 1,500

4. **Storage**
   - [ ] A default StorageClass exists with RWO access mode
   - [ ] StorageClass supports dynamic provisioning (e.g., `gp3-csi`, `gp2-csi`)

5. **Networking**
   - [ ] Cluster has a wildcard DNS entry for `*.apps.<cluster-domain>`
   - [ ] Routes are accessible externally (TLS termination at router)

6. **Namespaces**
   - [ ] 22 `agentic-user*` namespaces exist (or can be created)
   - [ ] ResourceQuotas applied per the table above

## Commands to Gather This Information

```bash
# Node summary
oc get nodes -o wide

# Allocatable resources per node
oc get nodes -o custom-columns=\
'NAME:.metadata.name,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory,PODS:.status.allocatable.pods'

# Total allocatable CPUs and memory across workers
oc get nodes -l node-role.kubernetes.io/worker -o json | python3 -c "
import json, sys
nodes = json.load(sys.stdin)['items']
cpus = sum(int(n['status']['allocatable']['cpu']) for n in nodes)
mem = sum(int(n['status']['allocatable']['memory'].replace('Ki','')) for n in nodes) / 1024 / 1024
print(f'Workers: {len(nodes)}, CPUs: {cpus}, Memory: {mem:.0f} Gi')
"

# Storage classes
oc get storageclasses

# Existing namespaces
oc get namespaces | grep agentic-user

# Resource quotas
oc get resourcequota -A | grep agentic-user
```
