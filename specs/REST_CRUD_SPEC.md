# REST CRUD Microservice — Generative Spec

> **Purpose:** Given an entity name and field list, generate a complete Spring Boot CRUD microservice with PostgreSQL, Docker, and Kubernetes/OpenShift deployment.

---

## Input Contract

To generate a service, provide:

| Input | Example | Required |
|-------|---------|----------|
| **Service name** | `fantaco-product-main` | Yes |
| **Port** | `8083` | Yes |
| **Base package** | `com.product` | Yes |
| **Entity name** | `Product` | Yes |
| **ID field** | `productId` (String, 5 chars) or auto-generated Long | Yes |
| **Fields** | See field definition table below | Yes |
| **Database name** | `fantaco_product` | Yes |
| **Container registry** | `docker.io/burrsutter` | Yes |

### Field Definition Format

Each field needs:

| Property | Example |
|----------|---------|
| name | `productName` |
| type | `String`, `BigDecimal`, `Integer`, `Boolean`, `LocalDateTime`, enum name |
| maxLength | `40` (for String) |
| required | `true` / `false` |
| constraints | `@Email`, `@DecimalMin("0.0")`, `@Size(min=5, max=5)` |
| indexed | `true` / `false` |
| searchable | `true` / `false` (adds `findByFieldContainingIgnoreCase` to repository) |

---

## Output Contract

The generator produces these exact files:

```
fantaco-<service>-main/
├── pom.xml
├── deployment/
│   ├── Dockerfile
│   └── kubernetes/
│       ├── application/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── route.yaml
│       │   ├── configmap.yaml
│       │   └── secret.yaml
│       └── postgres/
│           ├── deployment.yaml
│           └── service.yaml
└── src/main/
    ├── java/<base-package-as-path>/
    │   ├── <Entity>Application.java
    │   ├── model/
    │   │   └── <Entity>.java
    │   ├── dto/
    │   │   ├── <Entity>Request.java          (Record; omit ID when auto-generated)
    │   │   ├── <Entity>Response.java         (Record)
    │   │   ├── <Entity>UpdateRequest.java    (Record; omit ID when auto-generated)
    │   │   └── ErrorResponse.java            (Record)
    │   ├── repository/
    │   │   └── <Entity>Repository.java
    │   ├── service/
    │   │   └── <Entity>Service.java
    │   ├── controller/
    │   │   └── <Entity>Controller.java
    │   └── exception/
    │       ├── <Entity>NotFoundException.java
    │       ├── Duplicate<Entity>IdException.java
    │       └── GlobalExceptionHandler.java
    └── resources/
        ├── application.properties
        └── data.sql
```

---

## API Endpoints Produced

| Method | Path | Body | Response | Description |
|--------|------|------|----------|-------------|
| POST | `/api/<entities>` | `<Entity>Request` (omit ID when auto-generated) | 201 + `<Entity>Response` | Create (+ Location header) |
| GET | `/api/<entities>/{id}` | — | 200 + `<Entity>Response` | Get by ID |
| GET | `/api/<entities>` | query params | 200 + `List<Entity>Response` | Search/list all |
| PUT | `/api/<entities>/{id}` | `<Entity>UpdateRequest` (omit ID when auto-generated) | 200 + `<Entity>Response` | Full update (path ID only) |
| DELETE | `/api/<entities>/{id}` | — | 204 No Content | Hard delete |

---

## Complete Worked Example: Product Catalog Service

**Input:**
- Service name: `fantaco-product-main`
- Port: `8083`
- Base package: `com.product`
- Entity: `Product`
- ID: `productId` (String, 5 chars, business key)
- Database: `fantaco_product`
- Registry: `docker.io/burrsutter`

**Fields:**

| name | type | maxLength | required | constraints | indexed | searchable |
|------|------|-----------|----------|-------------|---------|------------|
| productName | String | 100 | true | — | true | true |
| category | String | 50 | true | — | true | true |
| price | BigDecimal | — | true | `@DecimalMin("0.01")` | false | false |
| inStock | Boolean | — | true | — | false | false |
| description | String | 500 | false | — | false | false |

---

### Generated File: `pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
        <relativePath/>
    </parent>

    <groupId>com.product</groupId>
    <artifactId>fantaco-product-main</artifactId>
    <version>1.0.0</version>
    <name>Product Catalog API</name>
    <description>REST API for managing product catalog data</description>

    <properties>
        <java.version>21</java.version>
        <springdoc.version>2.2.0</springdoc.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.springdoc</groupId>
            <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
            <version>${springdoc.version}</version>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

---

### Generated File: `src/main/java/com/product/ProductApplication.java`

```java
package com.product;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ProductApplication {

    public static void main(String[] args) {
        SpringApplication.run(ProductApplication.class, args);
    }
}
```

---

### Generated File: `src/main/java/com/product/model/Product.java`

```java
package com.product.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Objects;

@Entity
@Table(name = "product", indexes = {
    @Index(name = "idx_product_name", columnList = "productName"),
    @Index(name = "idx_category", columnList = "category")
})
public class Product {

    @Id
    @Column(name = "product_id", length = 5, nullable = false)
    @NotBlank(message = "Product ID is required")
    @Size(min = 5, max = 5, message = "Product ID must be exactly 5 characters")
    private String productId;

    @Column(name = "product_name", nullable = false, length = 100)
    @NotBlank(message = "Product name is required")
    @Size(max = 100, message = "Product name must not exceed 100 characters")
    private String productName;

    @Column(name = "category", nullable = false, length = 50)
    @NotBlank(message = "Category is required")
    @Size(max = 50, message = "Category must not exceed 50 characters")
    private String category;

    @Column(name = "price", nullable = false, precision = 10, scale = 2)
    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than 0")
    private BigDecimal price;

    @Column(name = "in_stock", nullable = false)
    @NotNull(message = "In stock status is required")
    private Boolean inStock;

    @Column(name = "description", length = 500)
    @Size(max = 500, message = "Description must not exceed 500 characters")
    private String description;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    public Product() {}

    public Product(String productId, String productName) {
        this.productId = productId;
        this.productName = productName;
    }

    // Getters and Setters
    public String getProductId() { return productId; }
    public void setProductId(String productId) { this.productId = productId; }

    public String getProductName() { return productName; }
    public void setProductName(String productName) { this.productName = productName; }

    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Boolean getInStock() { return inStock; }
    public void setInStock(Boolean inStock) { this.inStock = inStock; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public LocalDateTime getUpdatedAt() { return updatedAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Product product = (Product) o;
        return Objects.equals(productId, product.productId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(productId);
    }

    @Override
    public String toString() {
        return "Product{productId='" + productId + "', productName='" + productName + "', category='" + category + "'}";
    }
}
```

---

### Generated File: `src/main/java/com/product/dto/ProductRequest.java`

```java
package com.product.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record ProductRequest(
    @NotBlank(message = "Product ID is required")
    @Size(min = 5, max = 5, message = "Product ID must be exactly 5 characters")
    String productId,

    @NotBlank(message = "Product name is required")
    @Size(max = 100, message = "Product name must not exceed 100 characters")
    String productName,

    @NotBlank(message = "Category is required")
    @Size(max = 50, message = "Category must not exceed 50 characters")
    String category,

    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than 0")
    BigDecimal price,

    @NotNull(message = "In stock status is required")
    Boolean inStock,

    @Size(max = 500, message = "Description must not exceed 500 characters")
    String description
) {}
```

---

### Generated File: `src/main/java/com/product/dto/ProductUpdateRequest.java`

Same as `ProductRequest` but **without the ID field**:

```java
package com.product.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public record ProductUpdateRequest(
    @NotBlank(message = "Product name is required")
    @Size(max = 100, message = "Product name must not exceed 100 characters")
    String productName,

    @NotBlank(message = "Category is required")
    @Size(max = 50, message = "Category must not exceed 50 characters")
    String category,

    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than 0")
    BigDecimal price,

    @NotNull(message = "In stock status is required")
    Boolean inStock,

    @Size(max = 500, message = "Description must not exceed 500 characters")
    String description
) {}
```

---

### Generated File: `src/main/java/com/product/dto/ProductResponse.java`

Includes all fields plus audit timestamps:

```java
package com.product.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record ProductResponse(
    String productId,
    String productName,
    String category,
    BigDecimal price,
    Boolean inStock,
    String description,
    LocalDateTime createdAt,
    LocalDateTime updatedAt
) {}
```

---

### Generated File: `src/main/java/com/product/dto/ErrorResponse.java`

This is always the same across all CRUD services:

```java
package com.product.dto;

import java.time.LocalDateTime;
import java.util.List;

public record ErrorResponse(
    LocalDateTime timestamp,
    int status,
    String error,
    String message,
    List<ValidationError> errors
) {
    public record ValidationError(
        String field,
        String rejectedValue,
        String message
    ) {}
}
```

---

### Generated File: `src/main/java/com/product/repository/ProductRepository.java`

One `findBy...ContainingIgnoreCase` method per searchable field:

```java
package com.product.repository;

import com.product.model.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProductRepository extends JpaRepository<Product, String> {

    List<Product> findByProductNameContainingIgnoreCase(String productName);

    List<Product> findByCategoryContainingIgnoreCase(String category);
}
```

---

### Generated File: `src/main/java/com/product/service/ProductService.java`

```java
package com.product.service;

import com.product.dto.ProductRequest;
import com.product.dto.ProductResponse;
import com.product.dto.ProductUpdateRequest;
import com.product.exception.ProductNotFoundException;
import com.product.exception.DuplicateProductIdException;
import com.product.model.Product;
import com.product.repository.ProductRepository;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

@Service
@Transactional
public class ProductService {

    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public ProductResponse createProduct(ProductRequest request) {
        if (productRepository.existsById(request.productId())) {
            throw new DuplicateProductIdException(
                "Product with ID " + request.productId() + " already exists");
        }

        Product product = new Product();
        product.setProductId(request.productId());
        product.setProductName(request.productName());
        product.setCategory(request.category());
        product.setPrice(request.price());
        product.setInStock(request.inStock());
        product.setDescription(request.description());

        try {
            Product saved = productRepository.save(product);
            return toResponse(saved);
        } catch (DataIntegrityViolationException e) {
            throw new DuplicateProductIdException(
                "Product with ID " + request.productId() + " already exists");
        }
    }

    @Transactional(readOnly = true)
    public ProductResponse getProductById(String productId) {
        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(
                    "Product with ID " + productId + " not found"));
        return toResponse(product);
    }

    @Transactional(readOnly = true)
    public List<ProductResponse> searchProducts(String productName, String category) {
        boolean hasAnyCriteria = (productName != null && !productName.isBlank())
                || (category != null && !category.isBlank());

        if (!hasAnyCriteria) {
            return productRepository.findAll().stream()
                    .map(this::toResponse)
                    .toList();
        }

        List<Product> results = null;

        if (productName != null && !productName.isBlank()) {
            results = new ArrayList<>(
                productRepository.findByProductNameContainingIgnoreCase(productName));
        }
        if (category != null && !category.isBlank()) {
            List<Product> matched =
                productRepository.findByCategoryContainingIgnoreCase(category);
            results = (results == null)
                ? new ArrayList<>(matched)
                : intersect(results, matched);
        }

        return results.stream().map(this::toResponse).toList();
    }

    public ProductResponse updateProduct(String productId, ProductUpdateRequest request) {
        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(
                    "Product with ID " + productId + " not found"));

        product.setProductName(request.productName());
        product.setCategory(request.category());
        product.setPrice(request.price());
        product.setInStock(request.inStock());
        product.setDescription(request.description());

        Product updated = productRepository.save(product);
        return toResponse(updated);
    }

    public void deleteProduct(String productId) {
        if (!productRepository.existsById(productId)) {
            throw new ProductNotFoundException(
                "Product with ID " + productId + " not found");
        }
        productRepository.deleteById(productId);
    }

    private List<Product> intersect(List<Product> a, List<Product> b) {
        List<Product> result = new ArrayList<>(a);
        result.retainAll(b);
        return result;
    }

    private ProductResponse toResponse(Product product) {
        return new ProductResponse(
                product.getProductId(),
                product.getProductName(),
                product.getCategory(),
                product.getPrice(),
                product.getInStock(),
                product.getDescription(),
                product.getCreatedAt(),
                product.getUpdatedAt()
        );
    }
}
```

---

### Generated File: `src/main/java/com/product/controller/ProductController.java`

```java
package com.product.controller;

import com.product.dto.ProductRequest;
import com.product.dto.ProductResponse;
import com.product.dto.ProductUpdateRequest;
import com.product.service.ProductService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/products")
@CrossOrigin(origins = "*")
@Tag(name = "Product", description = "Product catalog management operations")
public class ProductController {

    private static final Logger logger = LoggerFactory.getLogger(ProductController.class);

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @PostMapping
    @Operation(summary = "Create a new product",
               description = "Creates a new product record with the provided information")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "201", description = "Product created successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "409", description = "Product ID already exists")
    })
    public ResponseEntity<ProductResponse> createProduct(
            @Valid @RequestBody ProductRequest request) {
        logger.info("createProduct called with request: {}", request);
        ProductResponse response = productService.createProduct(request);

        URI location = ServletUriComponentsBuilder
                .fromCurrentRequest()
                .path("/{id}")
                .buildAndExpand(response.productId())
                .toUri();

        return ResponseEntity.created(location).body(response);
    }

    @GetMapping("/{productId}")
    @Operation(summary = "Get product by ID",
               description = "Retrieves a single product record by its unique identifier")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Product found"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<ProductResponse> getProductById(
            @PathVariable String productId) {
        logger.info("getProductById called with productId: {}", productId);
        ProductResponse response = productService.getProductById(productId);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    @Operation(summary = "Search products",
               description = "Search for products by various fields with partial matching")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200",
                     description = "List of products matching the search criteria")
    })
    public ResponseEntity<List<ProductResponse>> searchProducts(
            @RequestParam(required = false) String productName,
            @RequestParam(required = false) String category) {
        logger.info("searchProducts called with productName: {}, category: {}",
                productName, category);
        List<ProductResponse> products =
            productService.searchProducts(productName, category);
        return ResponseEntity.ok(products);
    }

    @PutMapping("/{productId}")
    @Operation(summary = "Update product",
               description = "Updates an existing product record")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Product updated successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid input data"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<ProductResponse> updateProduct(
            @PathVariable String productId,
            @Valid @RequestBody ProductUpdateRequest request) {
        logger.info("updateProduct called with productId: {}, request: {}",
                productId, request);
        ProductResponse response = productService.updateProduct(productId, request);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{productId}")
    @Operation(summary = "Delete product",
               description = "Permanently deletes a product record (hard delete)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "204", description = "Product deleted successfully"),
        @ApiResponse(responseCode = "404", description = "Product not found")
    })
    public ResponseEntity<Void> deleteProduct(@PathVariable String productId) {
        logger.info("deleteProduct called with productId: {}", productId);
        productService.deleteProduct(productId);
        return ResponseEntity.noContent().build();
    }
}
```

---

### Generated File: `src/main/java/com/product/exception/ProductNotFoundException.java`

```java
package com.product.exception;

public class ProductNotFoundException extends RuntimeException {
    public ProductNotFoundException(String message) {
        super(message);
    }
}
```

---

### Generated File: `src/main/java/com/product/exception/DuplicateProductIdException.java`

```java
package com.product.exception;

public class DuplicateProductIdException extends RuntimeException {
    public DuplicateProductIdException(String message) {
        super(message);
    }
}
```

---

### Generated File: `src/main/java/com/product/exception/GlobalExceptionHandler.java`

Replace `<Entity>` class references with the actual entity exceptions:

```java
package com.product.exception;

import com.product.dto.ErrorResponse;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ProductNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ProductNotFoundException ex) {
        ErrorResponse errorResponse = new ErrorResponse(
                LocalDateTime.now(),
                HttpStatus.NOT_FOUND.value(),
                "Not Found",
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(errorResponse);
    }

    @ExceptionHandler(DuplicateProductIdException.class)
    public ResponseEntity<ErrorResponse> handleDuplicate(DuplicateProductIdException ex) {
        ErrorResponse errorResponse = new ErrorResponse(
                LocalDateTime.now(),
                HttpStatus.CONFLICT.value(),
                "Conflict",
                ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.CONFLICT).body(errorResponse);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
            MethodArgumentNotValidException ex) {
        List<ErrorResponse.ValidationError> validationErrors = new ArrayList<>();
        for (FieldError error : ex.getBindingResult().getFieldErrors()) {
            String rejectedValue = error.getRejectedValue() != null
                ? error.getRejectedValue().toString() : "null";
            validationErrors.add(new ErrorResponse.ValidationError(
                    error.getField(), rejectedValue, error.getDefaultMessage()));
        }
        ErrorResponse errorResponse = new ErrorResponse(
                LocalDateTime.now(),
                HttpStatus.BAD_REQUEST.value(),
                "Bad Request",
                "Validation failed",
                validationErrors
        );
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorResponse> handleDataIntegrity(
            DataIntegrityViolationException ex) {
        ErrorResponse errorResponse = new ErrorResponse(
                LocalDateTime.now(),
                HttpStatus.CONFLICT.value(),
                "Conflict",
                "Data integrity violation - possibly duplicate product ID",
                null
        );
        return ResponseEntity.status(HttpStatus.CONFLICT).body(errorResponse);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        ErrorResponse errorResponse = new ErrorResponse(
                LocalDateTime.now(),
                HttpStatus.INTERNAL_SERVER_ERROR.value(),
                "Internal Server Error",
                "An unexpected error occurred: " + ex.getMessage(),
                null
        );
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
    }
}
```

---

### Generated File: `src/main/resources/application.properties`

```properties
# Server
server.port=8083

# PostgreSQL
spring.datasource.url=jdbc:postgresql://localhost:5432/fantaco_product
spring.datasource.username=postgres
spring.datasource.password=postgres
spring.datasource.driver-class-name=org.postgresql.Driver

# JPA / Hibernate
spring.jpa.hibernate.ddl-auto=create-drop
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect

# SQL Initialization (seed data)
spring.jpa.defer-datasource-initialization=true
spring.sql.init.mode=always
spring.sql.init.continue-on-error=true
spring.sql.init.data-locations=classpath:data.sql

# Actuator (K8s probes)
management.endpoints.web.exposure.include=health,info
management.endpoint.health.probes.enabled=true
management.health.livenessState.enabled=true
management.health.readinessState.enabled=true

# OpenAPI
springdoc.api-docs.path=/v3/api-docs
springdoc.swagger-ui.path=/swagger-ui.html

# Logging
logging.level.com.product=INFO
logging.level.org.springframework.web=INFO
logging.level.org.hibernate.SQL=WARN
```

---

### Generated File: `src/main/resources/data.sql`

Provide realistic sample data. Use the entity's table and column names:

```sql
INSERT INTO product (product_id, product_name, category, price, in_stock, description, created_at, updated_at) VALUES
('PRD01', 'Classic Beef Taco', 'Tacos', 3.99, true, 'Our signature beef taco with fresh toppings', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD02', 'Chicken Burrito Supreme', 'Burritos', 8.99, true, 'Loaded chicken burrito with all the fixings', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD03', 'Veggie Quesadilla', 'Quesadillas', 6.49, true, 'Grilled veggie quesadilla with three cheeses', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD04', 'Churro Bites', 'Desserts', 4.29, true, 'Crispy cinnamon sugar churro bites', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD05', 'Horchata', 'Beverages', 2.99, true, 'Traditional Mexican rice drink', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD06', 'Fish Taco', 'Tacos', 4.49, false, 'Battered fish taco with chipotle slaw', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD07', 'Nachos Grande', 'Sides', 7.99, true, 'Loaded nachos with cheese, beans, and jalapenos', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('PRD08', 'Carnitas Bowl', 'Bowls', 9.49, true, 'Slow-cooked pork carnitas over rice', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
```

**Rules for data.sql:**
- Minimum 5 rows, ideally 8-20 for demos
- Use realistic values matching the domain
- Always include `CURRENT_TIMESTAMP` for `created_at` and `updated_at`
- Use `spring.sql.init.continue-on-error=true` so restarts don't fail on duplicates

---

### Generated File: `deployment/Dockerfile`

```dockerfile
# Build stage
FROM registry.access.redhat.com/ubi9/openjdk-21:latest AS build
WORKDIR /app
USER root
RUN chown -R 185:185 /app
USER 185
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:latest
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

### Generated File: `deployment/kubernetes/application/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fantaco-product-main
  labels:
    app: fantaco-product-main
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fantaco-product-main
  template:
    metadata:
      labels:
        app: fantaco-product-main
    spec:
      containers:
      - name: fantaco-product-main
        image: docker.io/burrsutter/fantaco-product-main:1.0.0
        imagePullPolicy: Always
        ports:
        - containerPort: 8083
          name: http
          protocol: TCP
        env:
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            configMapKeyRef:
              name: fantaco-product-config
              key: database.url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            configMapKeyRef:
              name: fantaco-product-config
              key: database.username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fantaco-product-secret
              key: database.password
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8083
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8083
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 250m
            memory: 256Mi
```

---

### Generated File: `deployment/kubernetes/application/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fantaco-product-service
  labels:
    app: fantaco-product-main
spec:
  type: ClusterIP
  selector:
    app: fantaco-product-main
  ports:
  - name: http
    port: 8083
    targetPort: 8083
    protocol: TCP
```

---

### Generated File: `deployment/kubernetes/application/route.yaml`

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: fantaco-product-service
  labels:
    app: fantaco-product-main
spec:
  port:
    targetPort: http
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: edge
  to:
    kind: Service
    name: fantaco-product-service
    weight: 100
```

---

### Generated File: `deployment/kubernetes/application/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fantaco-product-config
  labels:
    app: fantaco-product-main
data:
  database.url: "jdbc:postgresql://postgres-prod:5432/fantaco_product"
  database.username: "product"
  application.properties: |
    spring.jpa.hibernate.ddl-auto=update
    spring.jpa.show-sql=false
    logging.level.com.product=INFO
```

---

### Generated File: `deployment/kubernetes/application/secret.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: fantaco-product-secret
type: Opaque
stringData:
  database.password: product
```

---

### Generated File: `deployment/kubernetes/postgres/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql-product
  labels:
    app: postgresql-product
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql-product
  template:
    metadata:
      labels:
        app: postgresql-product
    spec:
      containers:
        - name: postgresql
          image: registry.redhat.io/rhel9/postgresql-15
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5432
              protocol: TCP
              name: postgres-prod
          env:
            - name: POSTGRESQL_USER
              value: product
            - name: POSTGRESQL_PASSWORD
              value: product
            - name: POSTGRESQL_ADMIN_PASSWORD
              value: postgres
            - name: POSTGRESQL_DATABASE
              value: fantaco_product
          volumeMounts:
            - name: postgres-product-data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: postgres-product-data
          emptyDir: {}
```

---

### Generated File: `deployment/kubernetes/postgres/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-prod
  labels:
    app: postgres-prod
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: postgres-prod
      protocol: TCP
      name: postgres-prod
  selector:
    app: postgresql-product
```

---

## Template Rules (How to Generalize)

When generating for a new entity, apply these substitutions:

| Placeholder | Rule |
|-------------|------|
| `<Entity>` | PascalCase entity name (e.g., `Product`) |
| `<entity>` | camelCase entity name (e.g., `product`) |
| `<entities>` | lowercase plural for URL path (e.g., `products`) |
| `<entity_id>` | ID field name in camelCase (e.g., `productId`) |
| `<service>` | short service name for K8s resources (e.g., `product`) |
| `<service-name>` | full K8s deployment name (e.g., `fantaco-product-main`) |
| `<port>` | assigned port number |
| `<db_name>` | database name (e.g., `fantaco_product`) |
| `<package>` | base Java package (e.g., `com.product`) |
| `<svc>` | 3-4 char abbreviation for postgres service name (e.g., `prod`) |

### ID Strategy

- **Business key (default):** String with fixed length, set by client → use `@Id @Column(length = N)`, no `@GeneratedValue`
- **Auto-generated:** Long with `@GeneratedValue(strategy = GenerationType.IDENTITY)` → POST response includes generated ID, UpdateRequest still omits ID

### Searchable Fields

For each field marked `searchable: true`:
1. Add `findBy<Field>ContainingIgnoreCase` to Repository
2. Add `@RequestParam(required = false) String <field>` to controller's `@GetMapping`
3. Add AND-intersection logic in service's `searchProducts` method

### Conventions Checklist

- [ ] DTOs are Java Records (not classes)
- [ ] `@CrossOrigin(origins = "*")` on controller
- [ ] `@CreationTimestamp` and `@UpdateTimestamp` for audit fields (not `@PreUpdate`)
- [ ] `GlobalExceptionHandler` with `@RestControllerAdvice` (not inline try-catch)
- [ ] OpenAPI annotations (`@Operation`, `@ApiResponses`, `@Tag`) on every endpoint
- [ ] Constructor injection (not `@Autowired`)
- [ ] `@Transactional(readOnly = true)` on read methods
- [ ] Logger with `LoggerFactory.getLogger` in controller
- [ ] Actuator liveness/readiness probes enabled
- [ ] UBI9 multi-stage Docker build
- [ ] K8s: ConfigMap for DB URL/username, Secret for DB password
- [ ] PostgreSQL: Red Hat `rhel9/postgresql-15` image, `emptyDir` volume

---

## Port Assignment Convention

| Service | Port |
|---------|------|
| Customer | 8081 |
| Finance | 8082 |
| (next service) | 8083 |
| (next service) | 8084 |
