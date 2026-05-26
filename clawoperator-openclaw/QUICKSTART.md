# Quick Start

## A — Fresh Cluster Setup (20 Users, End-to-End)

**Prerequisites:**
- `oc login` as cluster-admin
- `../.env` populated (copy from `../.env.example`)
- claw-operator repo at `../../claw-operator`

```bash
cd clawoperator-openclaw

# ── Phase 1: Cluster-level setup (one-time) ──────────────────────────
./0-admin-setup.sh 1 22              # Step 1: Install operator, enable User Workload Monitoring, RBAC
./deploy-logs-loki.sh                # Step 2: Centralized logging (Loki + S3)
./deploy-dashboards-grafana.sh       # Step 3: Grafana dashboards (Prometheus + Loki data sources)
./deploy-traces-mlflow.sh            # Step 4: LLM trace collection (MLflow + OTEL)
./deploy-traces-langfuse.sh          # Step 5: LLM observability (Langfuse — optional, takes priority over MLflow)

# ── Phase 2: Deploy everything + audience reset ──────────────────────
./audience-reset.sh 1 22             # Step 6: Claw instances, backends, MCP, traces, skills, URLs, broker
./enable-prometheus.sh 1 22          # Step 7: Prometheus metrics (one-time: creates ServiceMonitor + NetworkPolicy)

# ── Phase 3: Verify ──────────────────────────────────────────────────
./demo-preflight.sh 1 22             # Step 8: 15-point pre-demo check
```

### FantaCo Web UIs (per namespace)

Each namespace has its own Customer, Product, and Sales Order web apps:

```bash
NS=agentic-user1
echo "Customers:    https://$(oc get route fantaco-customer-service -n $NS -o jsonpath='{.spec.host}')/customers/index.html"
echo "Products:     https://$(oc get route fantaco-product-service -n $NS -o jsonpath='{.spec.host}')/catalog/index.html"
echo "Sales Orders: https://$(oc get route fantaco-sales-order-service -n $NS -o jsonpath='{.spec.host}')/orders/index.html"
```

### Observability UIs

```bash
echo "Grafana:      https://$(oc get route grafana-route -n grafana -o jsonpath='{.spec.host}')"
echo "Langfuse:     https://$(oc get route langfuse -n langfuse -o jsonpath='{.spec.host}')"
echo "MLflow:       https://$(oc get route mlflow -n mlflow -o jsonpath='{.spec.host}')"
```

---

## B — New Audience Reset (Subsequent Demos)

Before each subsequent demo, just re-run these two commands to wipe all user state (chats, memory, skills, cron), generate new unique audience URLs, re-inject backends/MCP/skills/tracing, and update the Route-LB broker:

```bash
./audience-reset.sh 1 22             # Wipe state, new URLs, re-inject everything
./demo-preflight.sh 1 22             # Verify
```

`enable-prometheus.sh` does **not** need to re-run — `audience-reset.sh` automatically re-installs the plugin and re-patches config if a ServiceMonitor already exists.
