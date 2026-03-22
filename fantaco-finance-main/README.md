# Fantaco Finance API

A comprehensive Finance REST API built with Java 21, Spring Boot 3.2, Maven, PostgreSQL, and containerized with Docker and Kubernetes.

## Features

- **Order Management**: Track and retrieve order history
- **Invoice Management**: Manage invoice history and status
- **Dispute Management**: Handle duplicate charge disputes
- **Receipt Management**: Find and manage lost receipts
- **RESTful API**: Clean, well-documented REST endpoints
- **Database Integration**: PostgreSQL with JPA/Hibernate
- **Containerization**: Docker with UBI9/OpenJDK base image
- **Kubernetes Ready**: Complete K8s deployment configurations

## Technology Stack

- **Java**: 21
- **Spring Boot**: 3.2.0
- **Build Tool**: Maven
- **Database**: PostgreSQL
- **Container**: Docker with UBI9/OpenJDK
- **Orchestration**: Kubernetes



### Postgres
```bash
createdb fantaco_finance
```

### Run Application
```bash
# Build the project
mvn clean package
```

## localhost

### With Local PostgreSQL

Ensure PostgreSQL is running and update `src/main/resources/application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/fantaco_finance
spring.datasource.username=postgres
spring.datasource.password=postgres
```

Run the application and test it locally (see curl commands below for other tests)

```bash
# Run the application
mvn spring-boot:run
```

The API will be available at `http://localhost:8082`

# Podman and Kubernetes Deployment

### Build & Run 
```bash
# Build the application
mvn clean package
```

```bash
java -jar target/fantaco-finance-main-1.0.0.jar
```

```bash
export FIN_URL=http://localhost:8082
```

```bash
curl -sS -X POST $FIN_URL/api/finance/orders/history \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "LONEP",
    "startDate": "2024-01-20T00:00:00",
    "endDate": "2024-01-31T23:59:59",
    "limit": 10
  }' | jq
```

### Container image
```bash
brew install podman 
podman machine start

podman login docker.io
```


```bash
podman build --arch amd64 --os linux -t docker.io/burrsutter/fantaco-finance-main:1.0.0 -f deployment/Dockerfile .
```

```bash
podman run \
  --name fantaco-finance-main \
  -p 8082:8082 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/fantaco_finance \
  -e SPRING_DATASOURCE_USERNAME=postgres \
  -e SPRING_DATASOURCE_PASSWORD=postgres \
  docker.io/burrsutter/fantaco-finance-main:1.0.0
```

```bash
curl $FIN_URL/api/finance/health
```

```bash
podman push docker.io/burrsutter/fantaco-finance-main:1.0.0
```

```bash
oc new-project fantaco
```

IF using the docker.io postgres image

```bash
oc adm policy add-scc-to-user anyuid -z default
```

Deploy Postgres

```bash
oc apply -f deployment/kubernetes/postgres/deployment.yaml
oc apply -f deployment/kubernetes/postgres/service.yaml
```

Deploy the application

```bash
oc apply -f deployment/kubernetes/application/configmap.yaml
oc apply -f deployment/kubernetes/application/secret.yaml
oc apply -f deployment/kubernetes/application/deployment.yaml
oc apply -f deployment/kubernetes/application/service.yaml
```

```bash
oc get pods
```

```bash
oc get services
```

```bash
oc expose service fantaco-finance-service
```

```bash
export FIN_URL=http://$(oc get routes -n fantaco -l app=fantaco-finance-main -o jsonpath="{range .items[*]}{.status.ingress[0].host}{end}")
echo $FIN_URL
```

### 1. Health Check
```bash
curl $FIN_URL/api/finance/health
```


### 2. Get Order History

```bash
curl -sS -X POST $FIN_URL/api/finance/orders/history \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "LONEP",
    "limit": 10
  }' | jq
```


```bash
curl -sS -X POST $FIN_URL/api/finance/orders/history \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "LONEP",
    "startDate": "2024-01-20T00:00:00",
    "endDate": "2024-06-30T23:59:59",
    "limit": 10
  }' | jq
```



### 3. Get Invoice History
```bash
curl -sS -X POST $FIN_URL/api/finance/invoices/history \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "LONEP",
    "startDate": "2024-01-01T00:00:00",
    "endDate": "2024-01-31T23:59:59",
    "limit": 10
  }' | jq
```

### 4. Start Duplicate Charge Dispute
```bash
curl -sS -X POST $FIN_URL/api/finance/disputes/duplicate-charge \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "AROUT",
    "orderId": 8,
    "description": "Charged twice for the same order",
    "reason": "Payment processor error caused duplicate charge"
  }' | jq
```

### 5. Find Lost Receipt
```bash
curl -sS -X POST $FIN_URL/api/finance/receipts/find-lost \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "LONEP",
    "orderId": 1
  }' | jq
```

##  Swagger URLs:
  - Swagger UI: http://localhost:8082/swagger-ui.html
  - API Docs (JSON): http://localhost:8082/api-docs


## Database Schema

The application uses the following main entities:

- **Orders**: Customer orders with status tracking
- **Invoices**: Invoice management with payment status
- **Disputes**: Dispute tracking for various types
- **Receipts**: Receipt management with file storage

Sample data is automatically loaded on startup via `data.sql`.

## Configuration

### Environment Variables
- `SPRING_DATASOURCE_URL`: Database connection URL
- `SPRING_DATASOURCE_USERNAME`: Database username
- `SPRING_DATASOURCE_PASSWORD`: Database password
- `SPRING_PROFILES_ACTIVE`: Active Spring profile

### Application Properties
Configuration is managed through `application.properties` with profiles for different environments.

## Monitoring and Health Checks

The application includes:
- Health check endpoint at `/api/finance/health`
- Kubernetes liveness and readiness probes
- Actuator endpoints for monitoring
- Structured logging with configurable levels

## Cleaning

Database cleaning

```bash
psql -U postgres -d fantaco_finance -c "DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE'; END LOOP; END \$\$;"
```