# REST Action Microservice — Generative Spec

> **Purpose:** Given a domain name and a set of operations, generate a Spring Boot service with action-based POST endpoints (not resource CRUD). Use this when the domain operations are complex business actions, multi-entity workflows, or side-effecting procedures — not simple create/read/update/delete.

---

## When to Use This Spec (vs. REST_CRUD_SPEC)

| Use REST_CRUD_SPEC when... | Use REST_ACTION_SPEC when... |
|----------------------------|------------------------------|
| The entity IS the resource | The endpoint represents an action |
| Standard GET/POST/PUT/DELETE on a resource | All endpoints are POST (action invocations) |
| Response is the entity directly | Response is wrapped: `{ success, message, data }` |
| Single entity type | Multiple related entity types |
| Simple CRUD operations | Business logic, validation rules, side effects |

**Examples of action-based services:**
- Finance: fetch order history, start a dispute, find a lost receipt
- Account management: reset password, verify email, lock/unlock account
- Workflow: approve request, escalate ticket, trigger notification

---

## Input Contract

To generate a service, provide:

| Input | Example | Required |
|-------|---------|----------|
| **Service name** | `fantaco-account-main` | Yes |
| **Port** | `8084` | Yes |
| **Base package** | `com.fantaco.account` | Yes |
| **Domain name** | `account` (used in URL path `/api/account/...`) | Yes |
| **Database name** | `fantaco_account` | Yes |
| **Container registry** | `quay.io/burrsutter` | Yes |
| **Entities** | See entity definition below | Yes |
| **Operations** | See operation definition below | Yes |

### Entity Definition Format

Each entity needs:

| Property | Example |
|----------|---------|
| name | `Account` |
| tableName | `accounts` |
| ID strategy | auto-generated Long |
| fields | List of field definitions (name, type, constraints) |
| enums | List of enum types used by this entity |

### Operation Definition Format

Each operation needs:

| Property | Example |
|----------|---------|
| name | `reset-password` |
| endpoint | `POST /api/account/password/reset` |
| requestDTO | `ResetPasswordRequest` (fields + validations) |
| responseStatus | 200 or 201 |
| description | "Resets a user's password and sends confirmation" |
| businessRules | List of validation/logic rules |
| tags | OpenAPI tag grouping (e.g., "Password Management") |

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
    ├── java/com/fantaco/<domain>/
    │   ├── <Domain>Application.java
    │   ├── entity/
    │   │   ├── <Entity1>.java           (with inner enums)
    │   │   ├── <Entity2>.java
    │   │   └── ...
    │   ├── dto/
    │   │   ├── <Operation1>Request.java  (class, not Record)
    │   │   ├── <Operation2>Request.java
    │   │   └── ...
    │   ├── repository/
    │   │   ├── <Entity1>Repository.java
    │   │   ├── <Entity2>Repository.java
    │   │   └── ...
    │   ├── service/
    │   │   └── <Domain>Service.java      (single service for all operations)
    │   └── controller/
    │       └── <Domain>Controller.java   (single controller for all operations)
    └── resources/
        ├── application.properties
        ├── schema.sql
        └── data.sql
```

### Key Structural Differences from CRUD Spec

| Aspect | CRUD Spec | Action Spec |
|--------|-----------|-------------|
| DTOs | Java Records | Regular classes with constructors |
| Controller count | One per entity | One for the whole domain |
| Service count | One per entity | One for the whole domain |
| Exception handling | `GlobalExceptionHandler` | Inline try-catch in controller |
| Response format | Entity/DTO directly | Wrapped `{ success, message, data }` |
| Timestamps | `@CreationTimestamp` / `@UpdateTimestamp` | Constructor-set `createdAt` + `@PreUpdate` |
| DDL strategy | `create-drop` with Hibernate | `update` + explicit `schema.sql` |
| Health check | Actuator only | Actuator + custom `/api/<domain>/health` endpoint |

---

## API Endpoints Produced

All operations use POST. Each returns a wrapped response:

```json
{
    "success": true,
    "message": "Operation completed successfully",
    "data": { ... },
    "count": 5
}
```

Error responses:

```json
{
    "success": false,
    "message": "Error description here",
    "data": null
}
```

Plus a health check:

| Method | Path | Response |
|--------|------|----------|
| GET | `/api/<domain>/health` | `{ status, service, count, timestamp }` |

---

## Complete Worked Example: Website Account Service

**Input:**
- Service name: `fantaco-account-main`
- Port: `8084`
- Base package: `com.fantaco.account`
- Domain: `account`
- Database: `fantaco_account`
- Registry: `quay.io/burrsutter`

**Entities:**

1. `Account` — id (Long, auto), accountNumber (String, unique), email (String), status (AccountStatus enum), passwordHash (String), failedLoginAttempts (Integer), lastLoginAt (LocalDateTime), lockedAt (LocalDateTime), emailVerifiedAt (LocalDateTime), createdAt, updatedAt
2. `AccountEvent` — id (Long, auto), accountId (Long, FK), eventType (EventType enum), description (String), createdAt

**Operations:**

1. `POST /api/account/password/reset` — Reset a user's password
2. `POST /api/account/email/verify` — Verify an email address
3. `POST /api/account/lock` — Lock an account
4. `POST /api/account/unlock` — Unlock an account

---

### Generated File: `pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
        <relativePath/>
    </parent>

    <groupId>com.fantaco</groupId>
    <artifactId>fantaco-account-main</artifactId>
    <version>1.0.0</version>
    <name>Fantaco Account API</name>
    <description>REST API for account management operations</description>

    <properties>
        <java.version>21</java.version>
        <maven.compiler.source>21</maven.compiler.source>
        <maven.compiler.target>21</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
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
            <version>2.2.0</version>
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

### Generated File: `src/main/java/com/fantaco/account/AccountApplication.java`

```java
package com.fantaco.account;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AccountApplication {

    public static void main(String[] args) {
        SpringApplication.run(AccountApplication.class, args);
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/entity/Account.java`

Entities use inner enums, `@PreUpdate`, and constructor-set `createdAt`:

```java
package com.fantaco.account.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.persistence.*;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDateTime;

@Entity
@Table(name = "accounts")
@Schema(description = "Account entity representing a user account")
public class Account {

    @Schema(description = "Unique identifier", example = "1")
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Schema(description = "Unique account number", example = "ACC-00001")
    @NotBlank
    @Column(name = "account_number", unique = true, nullable = false)
    private String accountNumber;

    @Schema(description = "Account email address", example = "user@example.com")
    @NotBlank
    @Email
    @Column(name = "email", nullable = false)
    private String email;

    @Schema(description = "Current account status", example = "ACTIVE")
    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 50)
    private AccountStatus status;

    @Schema(description = "Hashed password")
    @Column(name = "password_hash")
    private String passwordHash;

    @Schema(description = "Number of failed login attempts", example = "0")
    @Column(name = "failed_login_attempts", nullable = false)
    private Integer failedLoginAttempts = 0;

    @Schema(description = "Last login timestamp")
    @Column(name = "last_login_at")
    private LocalDateTime lastLoginAt;

    @Schema(description = "When the account was locked")
    @Column(name = "locked_at")
    private LocalDateTime lockedAt;

    @Schema(description = "When the email was verified")
    @Column(name = "email_verified_at")
    private LocalDateTime emailVerifiedAt;

    @Schema(description = "Record creation timestamp")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Schema(description = "Record last update timestamp")
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    // Constructors
    public Account() {
        this.createdAt = LocalDateTime.now();
    }

    public Account(String accountNumber, String email, AccountStatus status) {
        this();
        this.accountNumber = accountNumber;
        this.email = email;
        this.status = status;
    }

    @PreUpdate
    public void preUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public AccountStatus getStatus() { return status; }
    public void setStatus(AccountStatus status) { this.status = status; }

    public String getPasswordHash() { return passwordHash; }
    public void setPasswordHash(String passwordHash) { this.passwordHash = passwordHash; }

    public Integer getFailedLoginAttempts() { return failedLoginAttempts; }
    public void setFailedLoginAttempts(Integer failedLoginAttempts) { this.failedLoginAttempts = failedLoginAttempts; }

    public LocalDateTime getLastLoginAt() { return lastLoginAt; }
    public void setLastLoginAt(LocalDateTime lastLoginAt) { this.lastLoginAt = lastLoginAt; }

    public LocalDateTime getLockedAt() { return lockedAt; }
    public void setLockedAt(LocalDateTime lockedAt) { this.lockedAt = lockedAt; }

    public LocalDateTime getEmailVerifiedAt() { return emailVerifiedAt; }
    public void setEmailVerifiedAt(LocalDateTime emailVerifiedAt) { this.emailVerifiedAt = emailVerifiedAt; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }

    @Schema(description = "Account status enumeration")
    public enum AccountStatus {
        @Schema(description = "Account is pending activation") PENDING,
        @Schema(description = "Account is active") ACTIVE,
        @Schema(description = "Account is locked") LOCKED,
        @Schema(description = "Account is suspended") SUSPENDED,
        @Schema(description = "Account is closed") CLOSED
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/entity/AccountEvent.java`

```java
package com.fantaco.account.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDateTime;

@Entity
@Table(name = "account_events")
@Schema(description = "Account event entity for audit trail")
public class AccountEvent {

    @Schema(description = "Unique identifier", example = "1")
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Schema(description = "Associated account ID", example = "1")
    @NotNull
    @Column(name = "account_id", nullable = false)
    private Long accountId;

    @Schema(description = "Type of event", example = "PASSWORD_RESET")
    @Enumerated(EnumType.STRING)
    @Column(name = "event_type", nullable = false, length = 50)
    private EventType eventType;

    @Schema(description = "Event description")
    @Column(name = "description", columnDefinition = "TEXT")
    private String description;

    @Schema(description = "Record creation timestamp")
    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public AccountEvent() {
        this.createdAt = LocalDateTime.now();
    }

    public AccountEvent(Long accountId, EventType eventType, String description) {
        this();
        this.accountId = accountId;
        this.eventType = eventType;
        this.description = description;
    }

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getAccountId() { return accountId; }
    public void setAccountId(Long accountId) { this.accountId = accountId; }

    public EventType getEventType() { return eventType; }
    public void setEventType(EventType eventType) { this.eventType = eventType; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    @Schema(description = "Account event type enumeration")
    public enum EventType {
        PASSWORD_RESET, EMAIL_VERIFIED, ACCOUNT_LOCKED,
        ACCOUNT_UNLOCKED, LOGIN_SUCCESS, LOGIN_FAILED
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/dto/ResetPasswordRequest.java`

DTOs in action services are **regular classes** (not Records) with constructors, getters, setters, and `toString`:

```java
package com.fantaco.account.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for resetting an account password")
public class ResetPasswordRequest {

    @Schema(description = "Account number", example = "ACC-00001", required = true)
    @NotBlank(message = "Account number is required")
    private String accountNumber;

    @Schema(description = "New password", example = "newSecurePass123!", required = true)
    @NotBlank(message = "New password is required")
    private String newPassword;

    public ResetPasswordRequest() {}

    public ResetPasswordRequest(String accountNumber, String newPassword) {
        this.accountNumber = accountNumber;
        this.newPassword = newPassword;
    }

    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }

    public String getNewPassword() { return newPassword; }
    public void setNewPassword(String newPassword) { this.newPassword = newPassword; }

    @Override
    public String toString() {
        return "ResetPasswordRequest{accountNumber='" + accountNumber + "'}";
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/dto/VerifyEmailRequest.java`

```java
package com.fantaco.account.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for verifying an account email")
public class VerifyEmailRequest {

    @Schema(description = "Account number", example = "ACC-00001", required = true)
    @NotBlank(message = "Account number is required")
    private String accountNumber;

    @Schema(description = "Verification token", example = "abc123def456", required = true)
    @NotBlank(message = "Verification token is required")
    private String verificationToken;

    public VerifyEmailRequest() {}

    public VerifyEmailRequest(String accountNumber, String verificationToken) {
        this.accountNumber = accountNumber;
        this.verificationToken = verificationToken;
    }

    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }

    public String getVerificationToken() { return verificationToken; }
    public void setVerificationToken(String verificationToken) { this.verificationToken = verificationToken; }

    @Override
    public String toString() {
        return "VerifyEmailRequest{accountNumber='" + accountNumber + "'}";
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/dto/LockAccountRequest.java`

```java
package com.fantaco.account.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for locking an account")
public class LockAccountRequest {

    @Schema(description = "Account number", example = "ACC-00001", required = true)
    @NotBlank(message = "Account number is required")
    private String accountNumber;

    @Schema(description = "Reason for locking", example = "Too many failed login attempts")
    private String reason;

    public LockAccountRequest() {}

    public LockAccountRequest(String accountNumber, String reason) {
        this.accountNumber = accountNumber;
        this.reason = reason;
    }

    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }

    public String getReason() { return reason; }
    public void setReason(String reason) { this.reason = reason; }

    @Override
    public String toString() {
        return "LockAccountRequest{accountNumber='" + accountNumber + "', reason='" + reason + "'}";
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/dto/UnlockAccountRequest.java`

```java
package com.fantaco.account.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;

@Schema(description = "Request object for unlocking an account")
public class UnlockAccountRequest {

    @Schema(description = "Account number", example = "ACC-00001", required = true)
    @NotBlank(message = "Account number is required")
    private String accountNumber;

    @Schema(description = "Reason for unlocking", example = "Identity verified by support")
    private String reason;

    public UnlockAccountRequest() {}

    public UnlockAccountRequest(String accountNumber, String reason) {
        this.accountNumber = accountNumber;
        this.reason = reason;
    }

    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }

    public String getReason() { return reason; }
    public void setReason(String reason) { this.reason = reason; }

    @Override
    public String toString() {
        return "UnlockAccountRequest{accountNumber='" + accountNumber + "', reason='" + reason + "'}";
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/repository/AccountRepository.java`

```java
package com.fantaco.account.repository;

import com.fantaco.account.entity.Account;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface AccountRepository extends JpaRepository<Account, Long> {

    Optional<Account> findByAccountNumber(String accountNumber);

    Optional<Account> findByEmail(String email);
}
```

---

### Generated File: `src/main/java/com/fantaco/account/repository/AccountEventRepository.java`

```java
package com.fantaco.account.repository;

import com.fantaco.account.entity.AccountEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface AccountEventRepository extends JpaRepository<AccountEvent, Long> {

    List<AccountEvent> findByAccountIdOrderByCreatedAtDesc(Long accountId);
}
```

---

### Generated File: `src/main/java/com/fantaco/account/service/AccountService.java`

One service class handles all operations. Business logic and validation live here:

```java
package com.fantaco.account.service;

import com.fantaco.account.dto.*;
import com.fantaco.account.entity.*;
import com.fantaco.account.repository.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

@Service
@Transactional
public class AccountService {

    @Autowired
    private AccountRepository accountRepository;

    @Autowired
    private AccountEventRepository accountEventRepository;

    /**
     * Reset password for an account
     */
    public Account resetPassword(ResetPasswordRequest request) {
        Account account = accountRepository.findByAccountNumber(request.getAccountNumber())
                .orElseThrow(() -> new RuntimeException(
                    "Account not found: " + request.getAccountNumber()));

        if (account.getStatus() == Account.AccountStatus.LOCKED) {
            throw new RuntimeException(
                "Cannot reset password for locked account: " + request.getAccountNumber());
        }

        // In a real service, hash the password
        account.setPasswordHash("hashed_" + request.getNewPassword());
        account.setFailedLoginAttempts(0);

        accountEventRepository.save(new AccountEvent(
                account.getId(),
                AccountEvent.EventType.PASSWORD_RESET,
                "Password was reset"));

        return accountRepository.save(account);
    }

    /**
     * Verify email for an account
     */
    public Account verifyEmail(VerifyEmailRequest request) {
        Account account = accountRepository.findByAccountNumber(request.getAccountNumber())
                .orElseThrow(() -> new RuntimeException(
                    "Account not found: " + request.getAccountNumber()));

        if (account.getEmailVerifiedAt() != null) {
            throw new RuntimeException(
                "Email already verified for account: " + request.getAccountNumber());
        }

        account.setEmailVerifiedAt(LocalDateTime.now());
        if (account.getStatus() == Account.AccountStatus.PENDING) {
            account.setStatus(Account.AccountStatus.ACTIVE);
        }

        accountEventRepository.save(new AccountEvent(
                account.getId(),
                AccountEvent.EventType.EMAIL_VERIFIED,
                "Email verified: " + account.getEmail()));

        return accountRepository.save(account);
    }

    /**
     * Lock an account
     */
    public Account lockAccount(LockAccountRequest request) {
        Account account = accountRepository.findByAccountNumber(request.getAccountNumber())
                .orElseThrow(() -> new RuntimeException(
                    "Account not found: " + request.getAccountNumber()));

        if (account.getStatus() == Account.AccountStatus.LOCKED) {
            throw new RuntimeException(
                "Account is already locked: " + request.getAccountNumber());
        }

        account.setStatus(Account.AccountStatus.LOCKED);
        account.setLockedAt(LocalDateTime.now());

        accountEventRepository.save(new AccountEvent(
                account.getId(),
                AccountEvent.EventType.ACCOUNT_LOCKED,
                "Account locked. Reason: " + request.getReason()));

        return accountRepository.save(account);
    }

    /**
     * Unlock an account
     */
    public Account unlockAccount(UnlockAccountRequest request) {
        Account account = accountRepository.findByAccountNumber(request.getAccountNumber())
                .orElseThrow(() -> new RuntimeException(
                    "Account not found: " + request.getAccountNumber()));

        if (account.getStatus() != Account.AccountStatus.LOCKED) {
            throw new RuntimeException(
                "Account is not locked: " + request.getAccountNumber());
        }

        account.setStatus(Account.AccountStatus.ACTIVE);
        account.setLockedAt(null);
        account.setFailedLoginAttempts(0);

        accountEventRepository.save(new AccountEvent(
                account.getId(),
                AccountEvent.EventType.ACCOUNT_UNLOCKED,
                "Account unlocked. Reason: " + request.getReason()));

        return accountRepository.save(account);
    }
}
```

---

### Generated File: `src/main/java/com/fantaco/account/controller/AccountController.java`

The controller uses **inline try-catch** (not GlobalExceptionHandler) and wraps all responses in `Map<String, Object>`:

```java
package com.fantaco.account.controller;

import com.fantaco.account.dto.*;
import com.fantaco.account.entity.*;
import com.fantaco.account.service.AccountService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/account")
@CrossOrigin(origins = "*")
@Tag(name = "Account API", description = "REST API for account management operations")
public class AccountController {

    private static final Logger logger = LoggerFactory.getLogger(AccountController.class);

    @Autowired
    private AccountService accountService;

    @Operation(
        summary = "Reset account password",
        description = "Resets the password for a user account",
        tags = {"Password Management"}
    )
    @ApiResponses(value = {
        @ApiResponse(
            responseCode = "200",
            description = "Password reset successfully",
            content = @Content(
                mediaType = MediaType.APPLICATION_JSON_VALUE,
                schema = @Schema(implementation = Map.class),
                examples = @ExampleObject(
                    name = "Success Response",
                    value = """
                    {
                        "success": true,
                        "message": "Password reset successfully",
                        "data": {
                            "id": 1,
                            "accountNumber": "ACC-00001",
                            "email": "user@example.com",
                            "status": "ACTIVE"
                        }
                    }
                    """
                )
            )
        ),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/password/reset",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> resetPassword(
            @Parameter(description = "Password reset request", required = true)
            @Valid @RequestBody ResetPasswordRequest request) {
        logger.info("resetPassword called with request: {}", request);
        try {
            Account account = accountService.resetPassword(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Password reset successfully");
            response.put("data", account);

            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error resetting password: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Verify account email",
        description = "Verifies the email address for a user account",
        tags = {"Email Management"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Email verified successfully"),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/email/verify",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> verifyEmail(
            @Parameter(description = "Email verification request", required = true)
            @Valid @RequestBody VerifyEmailRequest request) {
        logger.info("verifyEmail called with request: {}", request);
        try {
            Account account = accountService.verifyEmail(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Email verified successfully");
            response.put("data", account);

            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error verifying email: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Lock an account",
        description = "Locks a user account to prevent access",
        tags = {"Account Status"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Account locked successfully"),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/lock",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> lockAccount(
            @Parameter(description = "Lock account request", required = true)
            @Valid @RequestBody LockAccountRequest request) {
        logger.info("lockAccount called with request: {}", request);
        try {
            Account account = accountService.lockAccount(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Account locked successfully");
            response.put("data", account);

            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error locking account: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @Operation(
        summary = "Unlock an account",
        description = "Unlocks a previously locked user account",
        tags = {"Account Status"}
    )
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Account unlocked successfully"),
        @ApiResponse(responseCode = "400", description = "Bad request"),
        @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping(
        value = "/unlock",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> unlockAccount(
            @Parameter(description = "Unlock account request", required = true)
            @Valid @RequestBody UnlockAccountRequest request) {
        logger.info("unlockAccount called with request: {}", request);
        try {
            Account account = accountService.unlockAccount(request);

            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "Account unlocked successfully");
            response.put("data", account);

            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("success", false);
            errorResponse.put("message", "Error unlocking account: " + e.getMessage());
            errorResponse.put("data", null);

            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    int count = 0;

    @Operation(
        summary = "Health check endpoint",
        description = "Returns the current health status of the Account API service",
        tags = {"Health"}
    )
    @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Map<String, Object>> healthCheck() {
        count++;
        Map<String, Object> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "Fantaco Account API");
        response.put("count", count);
        response.put("timestamp", java.time.LocalDateTime.now());
        return ResponseEntity.ok(response);
    }
}
```

---

### Generated File: `src/main/resources/application.properties`

```properties
# Server Configuration
server.port=8084
server.servlet.context-path=/

# Spring Application Configuration
spring.application.name=fantaco-account-api

# Database Configuration
spring.datasource.url=jdbc:postgresql://localhost:5432/fantaco_account
spring.datasource.username=postgres
spring.datasource.password=postgres
spring.datasource.driver-class-name=org.postgresql.Driver

# JPA/Hibernate Configuration
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.properties.hibernate.format_sql=true
spring.jpa.database-platform=org.hibernate.dialect.PostgreSQLDialect

# SQL Initialization
spring.sql.init.mode=always
spring.sql.init.schema-locations=classpath:schema.sql
spring.sql.init.data-locations=classpath:data.sql
spring.sql.init.continue-on-error=true

# Logging Configuration
logging.level.com.fantaco.account=INFO
logging.level.org.springframework.web=INFO
logging.level.org.hibernate.SQL=INFO
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} - %msg%n

# Actuator Configuration
management.endpoints.web.exposure.include=health,info,metrics
management.endpoint.health.show-details=always

# Swagger/OpenAPI Configuration
springdoc.api-docs.path=/v3/api-docs
springdoc.swagger-ui.path=/swagger-ui.html
```

---

### Generated File: `src/main/resources/schema.sql`

Action-based services use explicit DDL (not Hibernate auto-generate):

```sql
-- Create accounts table
CREATE TABLE IF NOT EXISTS accounts (
    id BIGSERIAL PRIMARY KEY,
    account_number VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255),
    failed_login_attempts INTEGER NOT NULL DEFAULT 0,
    last_login_at TIMESTAMP,
    locked_at TIMESTAMP,
    email_verified_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Create account_events table
CREATE TABLE IF NOT EXISTS account_events (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (account_id) REFERENCES accounts(id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_accounts_account_number ON accounts(account_number);
CREATE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email);
CREATE INDEX IF NOT EXISTS idx_accounts_status ON accounts(status);
CREATE INDEX IF NOT EXISTS idx_account_events_account_id ON account_events(account_id);
CREATE INDEX IF NOT EXISTS idx_account_events_event_type ON account_events(event_type);
```

---

### Generated File: `src/main/resources/data.sql`

```sql
-- Insert sample account data
INSERT INTO accounts (account_number, email, status, password_hash, failed_login_attempts, email_verified_at, created_at) VALUES
('ACC-00001', 'alice@example.com', 'ACTIVE', 'hashed_password1', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('ACC-00002', 'bob@example.com', 'ACTIVE', 'hashed_password2', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('ACC-00003', 'carol@example.com', 'PENDING', 'hashed_password3', 0, NULL, CURRENT_TIMESTAMP),
('ACC-00004', 'dave@example.com', 'LOCKED', 'hashed_password4', 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
('ACC-00005', 'eve@example.com', 'ACTIVE', 'hashed_password5', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT DO NOTHING;
```

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
EXPOSE 8084
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

### Generated K8s Manifests

Same pattern as CRUD spec — substitute service name, port, and database name.

**`deployment/kubernetes/application/deployment.yaml`** — Health probes use `/api/account/health`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fantaco-account-main
  labels:
    app: fantaco-account-main
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fantaco-account-main
  template:
    metadata:
      labels:
        app: fantaco-account-main
    spec:
      containers:
      - name: fantaco-account-main
        image: quay.io/burrsutter/fantaco-account-main:1.0.0
        imagePullPolicy: Always
        ports:
        - containerPort: 8084
          name: http
          protocol: TCP
        env:
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            configMapKeyRef:
              name: fantaco-account-config
              key: database.url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            configMapKeyRef:
              name: fantaco-account-config
              key: database.username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fantaco-account-secret
              key: database.password
        livenessProbe:
          httpGet:
            path: /api/account/health
            port: 8084
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/account/health
            port: 8084
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

**`deployment/kubernetes/application/service.yaml`**, **`route.yaml`**, **`configmap.yaml`**, **`secret.yaml`**, **`postgres/deployment.yaml`**, **`postgres/service.yaml`** — Follow the same templates as REST_CRUD_SPEC.md, substituting:
- Service name: `fantaco-account-main` / `fantaco-account-service`
- Port: `8084`
- ConfigMap: `fantaco-account-config`
- Secret: `fantaco-account-secret`
- DB URL: `jdbc:postgresql://postgres-acct:5432/fantaco_account`
- DB user: `account`
- DB password: `account`
- Postgres service name: `postgres-acct`
- Postgres deployment name: `postgresql-account`
- Database name: `fantaco_account`

---

## Template Rules (How to Generalize)

### Controller Pattern for Each Operation

Every operation in the controller follows this exact structure:

```java
@Operation(
    summary = "<Short description>",
    description = "<Detailed description>",
    tags = {"<Tag Group>"}
)
@ApiResponses(value = {
    @ApiResponse(responseCode = "200", description = "Success",
        content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
            schema = @Schema(implementation = Map.class),
            examples = @ExampleObject(name = "Success Response", value = """
                { "success": true, "message": "...", "data": { ... } }
            """))),
    @ApiResponse(responseCode = "400", description = "Bad request"),
    @ApiResponse(responseCode = "500", description = "Internal server error")
})
@PostMapping(
    value = "/<action-path>",
    consumes = MediaType.APPLICATION_JSON_VALUE,
    produces = MediaType.APPLICATION_JSON_VALUE
)
public ResponseEntity<Map<String, Object>> <operationName>(
        @Parameter(description = "...", required = true)
        @Valid @RequestBody <OperationRequest> request) {
    logger.info("<operationName> called with request: {}", request);
    try {
        <Entity> result = service.<operationName>(request);

        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", "<Operation> completed successfully");
        response.put("data", result);

        return ResponseEntity.ok(response);  // or .status(HttpStatus.CREATED)
    } catch (RuntimeException e) {
        Map<String, Object> errorResponse = new HashMap<>();
        errorResponse.put("success", false);
        errorResponse.put("message", e.getMessage());
        errorResponse.put("data", null);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(errorResponse);
    } catch (Exception e) {
        Map<String, Object> errorResponse = new HashMap<>();
        errorResponse.put("success", false);
        errorResponse.put("message", "Error: " + e.getMessage());
        errorResponse.put("data", null);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
    }
}
```

### Service Pattern for Each Operation

```java
public <Entity> <operationName>(<OperationRequest> request) {
    // 1. Look up the entity (throw RuntimeException if not found)
    // 2. Validate business rules (throw RuntimeException if violated)
    // 3. Perform the action (modify entity state)
    // 4. Log an event (if audit trail entity exists)
    // 5. Save and return the modified entity
}
```

### Conventions Checklist

- [ ] DTOs are regular classes (not Records) with no-arg constructor, field constructor, getters, setters, toString
- [ ] Single controller for the entire domain (`/api/<domain>/...`)
- [ ] Single service for the entire domain
- [ ] All operations are POST endpoints
- [ ] Response wrapped in `Map<String, Object>` with `success`, `message`, `data` keys
- [ ] For list responses, add `count` key
- [ ] Inline try-catch in controller (RuntimeException → 400, Exception → 500)
- [ ] `@CrossOrigin(origins = "*")` on controller
- [ ] `@Autowired` for dependency injection in controller and service
- [ ] Entities use `@PreUpdate` and constructor-set `createdAt` (not Hibernate annotations)
- [ ] Enums defined as inner classes on entities with `@Schema` on each value
- [ ] `schema.sql` for explicit DDL with `CREATE TABLE IF NOT EXISTS`
- [ ] Custom health endpoint at `GET /api/<domain>/health`
- [ ] `spring.jpa.hibernate.ddl-auto=update` (not `create-drop`)
- [ ] OpenAPI annotations with `@ExampleObject` showing full JSON responses
