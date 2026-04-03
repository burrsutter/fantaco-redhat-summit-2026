# Customer Master Data API

REST API for managing customer master data. External systems can create, read, update, and delete customer records with support for searching by ID, company name, contact name, email, and phone number.

## Database Schema

```mermaid
erDiagram
    Customer ||--o{ CustomerNote : "has many"
    Customer ||--o{ CustomerContact : "has many"
    Customer ||--o{ SalesPerson : "has many"

    Customer {
        string customerId PK "max 10 chars"
        string companyName "indexed"
        string contactName "indexed"
        string contactTitle
        string address
        string city
        string region
        string postalCode
        string country
        string phone "indexed"
        string fax
        string contactEmail "indexed"
        string website
        timestamp createdAt
        timestamp updatedAt
    }

    CustomerNote {
        long id PK "auto-generated"
        string customerId FK
        text noteText
        timestamp createdAt
        timestamp updatedAt
    }

    CustomerContact {
        long id PK "auto-generated"
        string customerId FK
        string firstName
        string lastName
        string email
        string title
        string phone
        string notes
    }

    SalesPerson {
        long id PK "auto-generated"
        string customerId FK
        string firstName
        string lastName
        string email
        string phone
        string territory
    }
```

## Features

- **CRUD Operations**: Create, Read, Update, Delete customer records
- **Advanced Search**: Partial match, case-insensitive search by multiple fields
- **Validation**: Bean Validation with detailed error messages
- **OpenAPI Documentation**: Auto-generated Swagger UI
- **Health Checks**: Kubernetes-ready liveness and readiness probes
- **Containerized**: Multi-stage Docker build with Red Hat UBI9 images

## Prerequisites

- **Java 21** (OpenJDK or Oracle JDK)
- **Maven 3.8+**
- **PostgreSQL 15+** (or Docker for local development)
- **Docker** (optional, for containerization)
- **Kubernetes** (optional, for deployment)

## Postgres 
```bash
createdb fantaco_customer
```

## Build

```bash
mvn clean package
```

## localhost

### With Local PostgreSQL

Ensure PostgreSQL is running and update `src/main/resources/application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/fantaco_customer
spring.datasource.username=postgres
spring.datasource.password=postgres
```

Run the application and test it locally (see curl commands below for other tests)

```bash
mvn spring-boot:run
```

or 

```bash
mvn clean compile package
```

```bash
java -jar target/fantaco-customer-main-1.0.0.jar
```

```bash
export CUST_URL=http://localhost:8081
```

```bash
open $CUST_URL/api/customers
```

```bash
curl -sS $CUST_URL/api/customers | jq
```

```bash
open $CUST_URL/swagger-ui/index.html
```


## Podman

### Build Image

```bash
brew install podman 
podman machine start

podman login docker.io
```

```bash
podman build --arch amd64 --os linux -t docker.io/burrsutter/fantaco-customer-main:1.0.0 -f deployment/Dockerfile .
podman push docker.io/burrsutter/fantaco-customer-main:1.0.0
```

Go into docker.io and make the image public


### Run container on localhost

```bash
podman run -p 8081:8081 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/fantaco_customer \
  -e SPRING_DATASOURCE_USERNAME=postgres \
  -e SPRING_DATASOURCE_PASSWORD=admin \
  docker.io/burrsutter/fantaco-customer-main:1.0.0
```

### OpenShift

```bash
oc new-project fantaco
```

IF you are using the [docker.io Postgres](https://hub.docker.com/_/postgres) image

```bash
oc adm policy add-scc-to-user anyuid -z default
```

The sample deployment.yaml uses a Red Hat rootless image (no root access required)

Deploy Postgres

```bash
oc apply -f deployment/kubernetes/postgres/deployment.yaml
oc apply -f deployment/kubernetes/postgres/service.yaml
```

```
oc get pods
NAME                         READY   STATUS    RESTARTS   AGE
postgresql-665b46c48-ttrnd   1/1     Running   0          3s
```


Using OCP Console terminal

```
psql -U postgres
```

```
postgres=# \l
                                                    List of databases
       Name       |  Owner   | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider |   Access privileges   
------------------+----------+----------+------------+------------+------------+-----------------+-----------------------
 fantaco_customer | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 postgres         | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 template0        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                  |          |          |            |            |            |                 | postgres=CTc/postgres
 template1        | postgres | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/postgres          +
                  |          |          |            |            |            |                 | postgres=CTc/postgres
(4 rows)
```

Deploy the application

```bash
oc apply -f deployment/kubernetes/application/configmap.yaml
oc apply -f deployment/kubernetes/application/secret.yaml
oc apply -f deployment/kubernetes/application/deployment.yaml
oc apply -f deployment/kubernetes/application/service.yaml
oc apply -f deployment/kubernetes/application/route.yaml
```

```bash
oc get pods
```

```
NAME                                     READY   STATUS    RESTARTS   AGE
fantaco-customer-main-7bdc4dd866-46j64   1/1     Running   0          93s
postgresql-665b46c48-ttrnd               1/1     Running   0          3m16s
```

```bash
export CUST_URL=http://$(oc get routes -n fantaco -l app=fantaco-customer-main -o jsonpath="{range .items[*]}{.status.ingress[0].host}{end}")
echo $CUST_URL
```

```bash
open $CUST_URL/api/customers
```

```bash
curl -sS -L $CUST_URL/api/customers | jq
```

```bash
open $CUST_URL/swagger-ui/index.html
```


## API Documentation

Once the application is running, access:

- **Swagger UI**: $CUST_URL/swagger-ui.html
- **OpenAPI JSON**: $CUST_URL/v3/api-docs
- **Health Check**: $CUST_URL/actuator/health

## API Endpoints

```bash
# export CUST_URL=http://$(oc get routes -n fantaco -l app=fantaco-customer-main -o jsonpath="{range .items[*]}{.status.ingress[0].host}{end}")
export CUST_URL=http://localhost:8081
```

### Search Customers

```bash
# Search by contact email
curl -sS -L "$CUST_URL/api/customers?contactEmail=thomashardy%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=franwilson%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=liuwong%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=linorodriguez%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=jaimeyorres%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=hannamoos%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=mariebertrand%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=victoriaashworth%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=yangwang%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=peterfranken%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=diegoroel%40example.com" | jq
curl -sS -L "$CUST_URL/api/customers?contactEmail=janetelimeira%40example.com" | jq

# Search by company name (partial match, case-insensitive)
curl -sS -L "$CUST_URL/api/customers?companyName=Alfreds" | jq


# Search by phone
curl -sS -L "$CUST_URL/api/customers?phone=030" | jq
```

**Response**: `200 OK` with array of customers


### Create Customer


```bash
curl -L -X POST $CUST_URL/api/customers \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "ALFKI",
    "companyName": "Alfreds Futterkiste",
    "contactName": "Maria Anders",
    "contactTitle": "Sales Representative",
    "address": "Obere Str. 57",
    "city": "Berlin",
    "postalCode": "12209",
    "country": "Germany",
    "phone": "030-0074321",
    "contactEmail": "maria.anders@alfki.com"
  }'
```

**Response**: `201 Created` with `Location` header

### Get Customer by ID

```bash
curl $CUST_URL/api/customers/ALFKI
```

### Update Customer

```bash
curl -X PUT $CUST_URL/api/customers/ALFKI \
  -H "Content-Type: application/json" \
  -d '{
    "companyName": "Alfreds Futterkiste GmbH",
    "contactName": "Maria Anders",
    "contactTitle": "Sales Manager",
    "phone": "030-0074322",
    "contactEmail": "maria.anders@alfki.de"
  }'
```

**Response**: `200 OK` with updated customer

### Delete Customer

```bash
curl -X DELETE $CUST_URL/api/customers/ALFKI
```

**Response**: `204 No Content`

## Validation Rules

- **customerId**: Required, exactly 5 characters
- **companyName**: Required, max 40 characters
- **contactName**: Optional, max 30 characters
- **contactEmail**: Optional, valid email format, max 255 characters
- **phone**: Optional, max 24 characters
- All other fields are optional with defined max lengths

## Error Handling

### Validation Error (400 Bad Request)

```json
{
  "timestamp": "2025-10-05T10:30:00",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed",
  "errors": [
    {
      "field": "customerId",
      "rejectedValue": "ABC",
      "message": "Customer ID must be exactly 5 characters"
    }
  ]
}
```

### Not Found (404)

```json
{
  "timestamp": "2025-10-05T10:30:00",
  "status": 404,
  "error": "Not Found",
  "message": "Customer with ID XXXXX not found"
}
```

### Duplicate ID (409 Conflict)

```json
{
  "timestamp": "2025-10-05T10:30:00",
  "status": 409,
  "error": "Conflict",
  "message": "Customer with ID ALFKI already exists"
}
```


## Testing

### Run All Tests

```bash
mvn test
```

## Technology Stack

- **Java 21**
- **Spring Boot 3.2.0**
- **Spring Data JPA** (with Hibernate)
- **PostgreSQL 15+**
- **Maven 3.8+**
- **Springdoc OpenAPI 2.2.0**
- **Testcontainers** (for integration testing)
- **Docker** (Red Hat UBI9 base images)
- **Kubernetes** 

## Architecture

```
┌─────────────────┐
│   Controller    │  REST API Layer (validation, error handling)
└────────┬────────┘
         │
┌────────▼────────┐
│    Service      │  Business Logic Layer
└────────┬────────┘
         │
┌────────▼────────┐
│   Repository    │  Data Access Layer (Spring Data JPA)
└────────┬────────┘
         │
┌────────▼────────┐
│   PostgreSQL    │  Database
└─────────────────┘
```


## Cleaning

```bash
psql -U postgres -d fantaco_customer -c "DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE'; END LOOP; END \$\$;"
```