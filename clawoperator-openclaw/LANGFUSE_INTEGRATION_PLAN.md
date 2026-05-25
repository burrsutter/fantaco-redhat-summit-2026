# Langfuse Integration Plan for audience-reset.sh

**Status:** Planning - DO NOT IMPLEMENT YET (audience-reset running in another session)

**Goal:** Enable OpenClaw instances to send OTEL traces to Langfuse as an alternative to (or alongside) MLflow.

---

## Decision Points

Before implementing, decide:

### 1. Deployment Model

**Option A: Replace MLflow with Langfuse**
- Remove MLflow integration entirely
- All traces go to Langfuse only
- Simpler configuration, single trace backend

**Option B: Run both MLflow and Langfuse in parallel**
- Keep MLflow integration as-is
- Add Langfuse as a second OTEL exporter
- Compare both platforms during demos
- More complex (need multi-exporter OTEL config)

**Option C: Make it configurable**
- Add a variable (e.g., `TRACE_BACKEND=mlflow|langfuse|both|none`)
- Script checks which backends are deployed and configures accordingly
- Most flexible but most complex

**Recommendation:** Start with **Option B** (run both) to compare capabilities, then decide which to keep long-term.

---

## 2. Implementation Approach

### Add to Phase 4: Re-patch diagnostics

Current Phase 4 structure:
```
Phase 4: Re-patch diagnostics (Prometheus + MLflow/OTEL)
  ├── Reset Prometheus data
  ├── Reset Grafana dashboard
  ├── Prometheus plugin install + config
  └── MLflow/OTEL plugin install + config
```

**Proposed:**
```
Phase 4: Re-patch diagnostics (Prometheus + MLflow/OTEL + Langfuse)
  ├── Reset Prometheus data
  ├── Reset Grafana dashboard
  ├── Reset MLflow traces (if deployed)
  ├── Reset Langfuse traces (if deployed)     ← NEW
  ├── Prometheus plugin install + config
  ├── MLflow/OTEL plugin install + config (if deployed)
  └── Langfuse/OTEL plugin install + config (if deployed)  ← NEW
```

---

## 3. Code Changes Required

### A. Add Langfuse Detection (similar to MLflow)

**Location:** After line 756 (end of MLflow detection block)

```bash
# ── Langfuse / OTEL ────────────────────────────────────────────────
LANGFUSE_PATCHED=false
LANGFUSE_URL=""
LANGFUSE_INTERNAL_URL=""
LANGFUSE_PUBLIC_KEY=""
LANGFUSE_SECRET_KEY=""

LANGFUSE_ROUTE=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$LANGFUSE_ROUTE" ]]; then
  LANGFUSE_URL="https://${LANGFUSE_ROUTE}"
  LANGFUSE_INTERNAL_URL="http://langfuse-web.langfuse.svc.cluster.local:3000"

  # Load API keys from .env (populated by deploy-traces-langfuse.sh)
  if [[ -n "${LANGFUSE_PUBLIC_KEY:-}" && -n "${LANGFUSE_SECRET_KEY:-}" ]]; then
    echo -e "${BOLD}--- Langfuse detected (will configure OTEL export) ---${RESET}"
    echo "  External URL:  ${LANGFUSE_URL} (for browser access)"
    echo "  Internal URL:  ${LANGFUSE_INTERNAL_URL} (for gateway OTEL export)"
    echo "  Public Key:    ${LANGFUSE_PUBLIC_KEY}"
  else
    echo "Warning: Langfuse deployed but LANGFUSE_PUBLIC_KEY/SECRET_KEY not in .env — skipping"
    LANGFUSE_ROUTE=""
  fi
fi
```

### B. Add Langfuse Trace Reset (before OTEL patching)

**Location:** After line 1172 (end of MLflow trace deletion)

```bash
# ── Reset Langfuse traces ─────────────────────────────────────────
LANGFUSE_ROUTE_CHECK=$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}' 2>/dev/null || true)
if [[ -n "$LANGFUSE_ROUTE_CHECK" && -n "${LANGFUSE_PUBLIC_KEY:-}" && -n "${LANGFUSE_SECRET_KEY:-}" ]]; then
  echo -e "\n${BOLD}--- Resetting Langfuse traces (new audience) ---${RESET}"
  LANGFUSE_RESET_URL="https://${LANGFUSE_ROUTE_CHECK}"

  # Brief pause to let in-flight OTEL exports land
  sleep 3

  # Get all traces and delete them
  TRACE_IDS=$(curl -sk -u "${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}" \
    "${LANGFUSE_RESET_URL}/api/public/traces?limit=1000" \
    | jq -r '.data[].id' 2>/dev/null || echo "")

  if [[ -n "$TRACE_IDS" ]]; then
    TRACE_COUNT=$(echo "$TRACE_IDS" | wc -l | tr -d ' ')
    echo "  Found ${TRACE_COUNT} traces to delete..."

    # Langfuse doesn't have a bulk delete API, so we'd need to delete one-by-one
    # OR truncate the ClickHouse tables directly (requires db access)
    # OR accept that traces accumulate (Langfuse has TTL/retention settings)

    # For now, just warn:
    echo "  Warning: Langfuse bulk trace deletion not implemented"
    echo "  Traces will accumulate across audiences (filter by session timestamp)"
  else
    echo "  No existing traces found"
  fi
fi
```

**Note:** Langfuse doesn't have a bulk trace deletion API like MLflow. Options:
1. Skip deletion (traces accumulate, filter by timestamp in UI)
2. Delete via ClickHouse directly (requires pod exec)
3. Implement trace-by-trace deletion (slow for large datasets)

### C. Add Langfuse OTEL Configuration

**Location:** After line 854 (end of MLflow OTEL patching)

**Challenge:** OTEL SDK doesn't natively support multiple exporters. Options:

**Option 1: Use OTEL Collector (Recommended for production)**
- Deploy an OTEL Collector sidecar or separate pod
- Gateway sends to Collector
- Collector forwards to both MLflow and Langfuse
- Adds complexity but is the "right" way

**Option 2: Use environment variable concatenation (Hack)**
- Some OTEL SDKs support comma-separated endpoints
- May not work with OpenClaw's OTEL setup
- Fragile

**Option 3: Choose one exporter based on priority**
```bash
if [[ -n "$LANGFUSE_ROUTE" ]]; then
  # Langfuse takes priority if both are deployed
  TRACE_ENDPOINT="${LANGFUSE_INTERNAL_URL}/api/public/otel/v1/traces"
  TRACE_HEADERS="Authorization=Basic $(echo -n "${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}" | base64)"
elif [[ -n "$MLFLOW_ROUTE" ]]; then
  # Fall back to MLflow
  TRACE_ENDPOINT="${MLFLOW_INTERNAL_URL}/v1/traces"
  TRACE_HEADERS="x-mlflow-experiment-id=${EXPERIMENT_ID}"
fi

# Apply OTEL config using $TRACE_ENDPOINT and $TRACE_HEADERS
```

**Option 4: User chooses via .env variable**
```bash
# In .env:
TRACE_BACKEND=langfuse  # or "mlflow" or "both" (if collector deployed)
```

**Recommendation:** Start with **Option 3** (Langfuse priority if both deployed) for simplicity.

### D. NetworkPolicy for Langfuse

**Location:** After line 799 (before plugin install loop)

```bash
# If using Langfuse, create NetworkPolicy
if [[ -n "$LANGFUSE_ROUTE" ]]; then
  oc apply -n "$NS" -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-instance-to-langfuse
spec:
  podSelector:
    matchLabels:
      app: claw
      claw.sandbox.redhat.com/instance: instance
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: langfuse
    ports:
    - port: 3000
      protocol: TCP
EOF
fi
```

### E. OTEL Config Differences: MLflow vs Langfuse

| Setting | MLflow | Langfuse |
|---------|--------|----------|
| Endpoint | `/v1/traces` | `/api/public/otel/v1/traces` |
| Auth | Header: `x-mlflow-experiment-id=1` | Header: `Authorization: Basic <base64(pk:sk)>` |
| Internal URL | `http://mlflow-mlflow.mlflow.svc:5000` | `http://langfuse-web.langfuse.svc:3000` |
| Port | 5000 | 3000 |

**openclaw.json patch for Langfuse:**
```javascript
c.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = 'http://langfuse-web.langfuse.svc.cluster.local:3000/api/public/otel/v1/traces';
c.env.OTEL_EXPORTER_OTLP_TRACES_HEADERS = 'Authorization=Basic <base64>';
```

**Container env vars for Langfuse:**
```bash
oc set env deployment/instance -n $NS -c gateway \
  OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="http://langfuse-web.langfuse.svc.cluster.local:3000/api/public/otel/v1/traces" \
  OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=Basic $(echo -n "${LANGFUSE_PUBLIC_KEY}:${LANGFUSE_SECRET_KEY}" | base64)" \
  OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf" \
  OTEL_EXPORTER_OTLP_TRACES_PROTOCOL="http/protobuf" \
  OTEL_SERVICE_NAME="openclaw-${NS}" \
  OTEL_RESOURCE_ATTRIBUTES="openclaw.namespace=${NS}" \
  OTEL_SEMCONV_STABILITY_OPT_IN="gen_ai_latest_experimental"
```

### F. Post-Restart Re-Patching

**Location:** After line 988 (end of MLflow post-restart re-patch)

Must duplicate the Langfuse OTEL patching logic in the "post-restart re-patch" section (lines 947-989) because `oc rollout restart` re-seeds `openclaw.json` from the operator ConfigMap.

---

## 4. Testing Plan

1. **Fresh deployment test:**
   ```bash
   # Deploy both MLflow and Langfuse
   ./deploy-traces-mlflow.sh
   ./deploy-traces-langfuse.sh

   # Verify .env has all keys
   grep LANGFUSE .env

   # Run audience-reset with Langfuse priority
   ./audience-reset.sh 1 2

   # Verify traces go to Langfuse only
   # Open Langfuse UI, send test prompts, check traces appear
   ```

2. **MLflow-only test (backward compatibility):**
   ```bash
   # Delete Langfuse namespace
   oc delete namespace langfuse

   # Run audience-reset
   ./audience-reset.sh 1 2

   # Verify traces still go to MLflow
   ```

3. **Neither deployed test:**
   ```bash
   # Delete both MLflow and Langfuse namespaces
   oc delete namespace mlflow langfuse

   # Run audience-reset
   ./audience-reset.sh 1 2

   # Verify script skips OTEL config gracefully
   ```

---

## 5. Documentation Updates

### README.md additions:
- Update Quick Start to mention Langfuse as Step 5 (already done ✓)
- Add note about choosing trace backend
- Document the priority logic (Langfuse > MLflow if both deployed)

### .env.example additions:
- Already added ✓

### MEMORY.md additions:
- Document Langfuse integration approach once implemented
- Add any new gotchas discovered during implementation

---

## 6. Open Questions

1. **Trace deletion:** Accept accumulation or implement deletion?
2. **Multi-exporter:** Worth deploying OTEL Collector for "both" mode?
3. **Default backend:** Which should be default if we add a `TRACE_BACKEND` env var?
4. **Deprecation:** Keep MLflow or deprecate it in favor of Langfuse?

---

## 7. Rollout Strategy

**Proposed:**
1. Implement Option 3 (Langfuse priority) in a new branch
2. Test on a fresh cluster with 2-3 users
3. Verify traces in Langfuse UI
4. Test backward compatibility (MLflow-only)
5. Merge and deploy to production cluster
6. Observe for 1-2 demos
7. Decide: keep Langfuse, keep both, or revert to MLflow

---

## 8. Estimated Effort

- Code changes: ~100 lines (detection, config, NetworkPolicy, post-restart)
- Testing: 1-2 hours (fresh, backward compat, edge cases)
- Documentation: 30 minutes
- Total: ~3-4 hours

---

## Next Steps

1. Review this plan
2. Wait for current audience-reset to complete
3. Choose deployment model (A/B/C from Decision Points)
4. Implement and test on a branch
5. Deploy to production

---

**Questions? Decisions needed?**
- Which deployment model: A (Langfuse only), B (both), or C (configurable)?
- Trace deletion: implement, skip, or truncate via ClickHouse?
- OTEL Collector: worth the complexity for "both" mode?
