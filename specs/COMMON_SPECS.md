# Common Conventions — Cross-Cutting Reference

> **Purpose:** Shared conventions for all Fantaco services (REST and MCP). The generative specs (`REST_CRUD_SPEC`, `REST_ACTION_SPEC`, `MCP_SERVER_SPEC`) should follow these conventions.

---

## 1. Container Build Convention

All images are built with `podman` (not Docker). Dev machines are ARM Mac; OpenShift is x86_64.

```bash
# Java services
mvn clean compile package
podman build --arch amd64 --os linux -t docker.io/burrsutter/<image-name>:1.0.0 -f deployment/Dockerfile .
podman push docker.io/burrsutter/<image-name>:1.0.0

# Python MCP servers
podman build --arch amd64 --os linux -t docker.io/burrsutter/<image-name>:1.0.0 .
podman push docker.io/burrsutter/<image-name>:1.0.0
```

**Critical:** The `--arch amd64 --os linux` flags are **required**. Without them, containers built on ARM Mac will fail with `Exec format error` on OpenShift.

| Convention | Value |
|------------|-------|
| Build tool | `podman` |
| Platform flags | `--arch amd64 --os linux` |
| Registry | `docker.io/burrsutter` |
| Tag | `1.0.0` |

---

## 2. Image Naming

| Type | Pattern | Example |
|------|---------|---------|
| REST service | `fantaco-<domain>-main` | `fantaco-customer-main` |
| MCP server | `mcp-server-<domain>` | `mcp-server-finance` |

---

## 3. Port Assignments

### REST Services (8081-8089)

| Port | Service |
|------|---------|
| 8081 | fantaco-customer-main |
| 8082 | fantaco-finance-main |
| 8083 | fantaco-product-main |
| 8084 | fantaco-sales-order-main |
| 8085 | fantaco-hr-recruiting |
| 8086+ | (next REST service) |

### MCP Servers (9001-9009)

| Port | Service |
|------|---------|
| 9001 | mcp-server-customer |
| 9002 | mcp-server-finance |
| 9003 | mcp-server-product |
| 9004 | mcp-server-sales-order |
| 9005+ | (next MCP server) |

---

## 4. Base Images

| Type | Build Stage | Runtime Stage |
|------|-------------|---------------|
| Java (Spring Boot) | `registry.access.redhat.com/ubi9/openjdk-21:latest` | `registry.access.redhat.com/ubi9/openjdk-21-runtime:latest` |
| Python MCP | `python:3.11-slim` | (single stage) |
| PostgreSQL | `registry.redhat.io/rhel9/postgresql-15` | — |

---

## 5. Kubernetes / OpenShift Conventions

### Labels

Use `app: <deployment-name>` consistently on metadata, selector, and pod template:

```yaml
metadata:
  name: fantaco-product-main
  labels:
    app: fantaco-product-main
spec:
  selector:
    matchLabels:
      app: fantaco-product-main
  template:
    metadata:
      labels:
        app: fantaco-product-main
```

### Service Naming

| Type | Pattern | Example |
|------|---------|---------|
| REST service | `fantaco-<domain>-service` | `fantaco-customer-service` |
| MCP service | `mcp-<domain>-service` | `mcp-customer-service` |

All services use `type: ClusterIP`.

### Routes (OpenShift)

```yaml
spec:
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  to:
    kind: Service
    name: <service-name>
    weight: 100
```

---

## 6. Resource Limits

### REST CRUD / Action Services

```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### MCP Servers

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

---

## 7. Health Probes

### REST Services (Spring Boot Actuator)

```yaml
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: <port>
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: <port>
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

### MCP Servers

No health probes. They are stateless and start fast.
