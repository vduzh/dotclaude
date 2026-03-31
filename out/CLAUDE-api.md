# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nano CRM API** - RESTful API for Customer Relationship Management system built with Spring Boot.

**Tech Stack:**
- Java 25
- Spring Boot 3.5.7
- Spring Data JPA with PostgreSQL
- Liquibase for schema migrations
- JWT authentication (JJWT)
- MapStruct for entity-DTO mapping
- Gradle 9.1.0
- Springdoc OpenAPI for API documentation

## Build & Run Commands

```bash
# Build project
.\gradlew clean build

# Build without tests
.\gradlew clean build -x test

# Run with dev profile (default)
.\gradlew bootRun

# Run with specific profile
.\gradlew bootRun --args='--spring.profiles.active=test'
```

**Profiles:**
- `dev` (default): Local development, PostgreSQL at `localhost:5532/nano-crm-db`, all actuator endpoints enabled
- `test`: QA environment, PostgreSQL at `postgresql.pe-art-landings-qa.svc.cluster.local:5432/nano-crm-db`

**API Documentation:**
- Swagger UI: http://localhost:8080/swagger-ui.html
- OpenAPI JSON: http://localhost:8080/api-docs

## Architecture

```
src/main/java/com/artezio/nano/api/
├── config/           # Spring configurations (OpenAPI, Security, CORS)
├── controller/       # REST controllers (@RestController)
├── service/          # Business logic interfaces and implementations
├── repository/       # Spring Data JPA repositories
│   └── spec/         # Specifications and Filters
├── model/            # JPA entities
│   └── enums/        # All enums (AccountStatus, InvoiceStatus, etc.)
├── dto/              # Data Transfer Objects with validation
├── mapper/           # MapStruct mappers (entity ↔ DTO)
├── exception/        # Custom exceptions and global exception handler
├── security/         # JWT authentication & authorization
├── validation/       # Custom validators (e.g., @ValidSort)
└── util/             # Utility classes

src/main/resources/
├── application.yml           # Base configuration
├── application-{profile}.yml # Profile-specific overrides
└── db/changelog/
    ├── db.changelog-master.xml
    └── changes/*.sql         # Liquibase migrations (formatted SQL)
```

### Current Enums

- `AccountStatus` - User account status (ACTIVE, DISABLED)
- `TransactionType` - Transaction types (topup, subscription, refund, adjustment)
- `TransactionStatus` - Transaction status (pending, completed, failed)
- `CoachSubscriptionStatus` - Coach subscription status (ACTIVE, CANCELLED, SUSPENDED)
- `InvoiceStatus` - Invoice status (pending, paid_by_client, confirmed, overdue)
- `InvoiceType` - Invoice type (subscription, one_time)
- `SubscriptionStatus` - Athlete subscription status (active, paused)

## Security

**JWT Authentication:**
- Stateless session management (`SessionCreationPolicy.STATELESS`)
- BCrypt for password hashing
- JWT secret and expiration configured in `application.yml` (`app.jwt.*`)

**Rate Limiting (DDoS protection):**
- Bucket4j + Caffeine (Token Bucket algorithm)
- Protected endpoints: `/api/v1/auth/*` (login, register, forgot-password, etc.)
- Key: `IP:endpoint` — separate limits per IP per endpoint
- Config: `app.rate-limiting.*` in `application.yml`

**Login Attempt Protection (Brute-force protection):**
- Caffeine Cache with simple counter
- Key: `IP:email` — blocks specific IP+account combination after failed attempts
- Protects against brute-force while preventing Account Lockout attacks
- Config: `app.login-attempt.*` in `application.yml`

```yaml
app:
  rate-limiting:
    enabled: true
    default-requests-per-minute: 5
    endpoints:
      login:
        requests-per-minute: 30
    cache:
      expire-after-access-minutes: 5
      maximum-size: 10000

  login-attempt:
    enabled: true
    max-attempts: 5
    block-duration-minutes: 15
    cache:
      expire-after-write-minutes: 15
      maximum-size: 10000
```

**Why IP:email key (not just email)?** Prevents Account Lockout Attack — attacker can only block their own IP's access to victim's account, not the victim's access from their IP.

**For K8s (distributed):** Add `bucket4j-redis` dependency and run with `--spring.profiles.active=distributed`. See `RateLimitConfig.java` for Redis template.

**Actuator и Management Port (K8s):**

- **Порт 8080** — публичный API (через Ingress)
- **Порт 8081** — management/actuator (только внутри K8s кластера)
- **Dev:** один порт для удобства локальной разработки

```yaml
# application.yml (prod)
management:
  server:
    port: 8081

# application-dev.yml
management:
  server:
    port: 8080
```

**SecurityFilterChain для actuator:**
```java
@Bean
@Order(1)
public SecurityFilterChain actuatorSecurityFilterChain(HttpSecurity http) throws Exception {
    http
            .securityMatcher(EndpointRequest.toAnyEndpoint())
            .csrf(AbstractHttpConfigurer::disable)
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
    return http.build();
}
```

**Profile-specific Security:**
- **Dev**: Actuator на порту 8080, все endpoints открыты (`/actuator/**`)
- **Test/Prod**: Actuator на порту 8081, только `health,prometheus`

**Always Public:**
- Health check (`/`)
- Swagger UI (`/swagger-ui.html`)
- API documentation (`/api-docs`)
- Login endpoint (`/api/v1/auth/login`)

## Configuration

**HikariCP Connection Pool:**
- Dev: 10 connections, Test: 20 connections
- Connection timeout: 30s, Idle timeout: 10min, Max lifetime: 30min

**Logging:**
- SLF4J + Logback
- Console + file (`logs/nano-crm-api.log`)
- Daily rotation, 30-day retention

**CORS:**
- Configured via `app.cors.allowed-origins` in YAML
- Default: `http://localhost:3000`
- Exposed headers: `Authorization`, `X-Total-Count`

**Environment Profiles:**

| Profile | Secrets | Actuator | Use case |
|---------|---------|----------|----------|
| `dev` | In YAML (defaults) | All endpoints, port 8080 | Local development |
| `test` | In YAML | health,prometheus, port 8081 | QA/staging |
| `prod` | ENV variables only | health,prometheus, port 8081 | Production |

**Production Environment Variables (Spring Boot Relaxed Binding):**

| ENV Variable | Property | Example |
|--------------|----------|---------|
| `SPRING_DATASOURCE_URL` | `spring.datasource.url` | `jdbc:postgresql://host:5432/db` |
| `SPRING_DATASOURCE_USERNAME` | `spring.datasource.username` | `user` |
| `SPRING_DATASOURCE_PASSWORD` | `spring.datasource.password` | `secret` |
| `SPRING_MAIL_USERNAME` | `spring.mail.username` | `email@example.com` |
| `SPRING_MAIL_PASSWORD` | `spring.mail.password` | `app-password` |
| `APP_JWT_SECRET` | `app.jwt.secret` | `min-256-bit-key` |
| `APP_CORS_ALLOWED_ORIGINS` | `app.cors.allowed-origins` | `https://domain.com` |
| `APP_TELEGRAM_BOT_TOKEN` | `app.telegram.bot.token` | `123456:ABC...` |
| `APP_TELEGRAM_BOT_USERNAME` | `app.telegram.bot.username` | `your_bot` |
| `APP_INTEGRATIONS_YOOKASSA_SHOP_ID` | `app.integrations.yookassa.shop-id` | `shop-id` |
| `APP_INTEGRATIONS_YOOKASSA_SECRET_KEY` | `app.integrations.yookassa.secret-key` | `secret` |

> **No custom ENV names** — use Spring Boot naming convention: `SPRING_*` for Spring properties, `APP_*` for custom `app.*` properties.

## YooKassa Payment Integration

### Overview

Balance top-up via YooKassa with robust handling for webhook failures.

**Problem:** If YooKassa webhook doesn't arrive (network issues, server downtime), payment stays `PENDING` forever even if money was charged.

**Solution:** `PaymentStatusScheduler` periodically checks pending payments via YooKassa API.

### Payment Statuses

```java
public enum PaymentStatus {
    PENDING,    // Awaiting payment in YooKassa
    SUCCEEDED,  // Successfully paid
    CANCELED,   // Canceled by user or payment system
    EXPIRED     // Timed out (not paid within 24 hours)
}
```

### PaymentStatusScheduler

**Location:** `scheduler/PaymentStatusScheduler.java`

**Schedule:**
- Dev: every 2 minutes (`@Profile("dev")`)
- Test/Prod: every 5 minutes (`@Profile("test")`, `@Profile("prod")`)

**Logic:**
1. Find `PENDING` payments older than `pendingCheckThresholdMinutes`
2. Call `YooKassaService.getPayment(yookassaPaymentId)` to check actual status
3. If `succeeded` → process payment, update balance
4. If `canceled` → mark as canceled
5. If still `pending` and older than `expirationHours` → mark as `EXPIRED`

**Key point:** Always checks YooKassa API before marking as expired, so payments are processed even after extended server downtime.

### Configuration

```yaml
# application.yml
app:
  payments:
    pending-check-threshold-minutes: 5
    expiration-hours: 24

# application-dev.yml (shorter for testing)
app:
  payments:
    pending-check-threshold-minutes: 2
    expiration-hours: 1
```

### Disabling "Allow recurring payments" checkbox

`save_payment_method: false` is set in `YooKassaPaymentRequestDto` to hide the auto-debit checkbox on YooKassa payment page.

### Related Files

- `config/PaymentProperties.java` — configuration properties
- `config/WebClientConfig.java` — WebClient bean (5s connect, 10s read/write timeout)
- `scheduler/PaymentStatusScheduler.java` — scheduled task
- `service/YooKassaService.java` — YooKassa API client
- `service/impl/BalanceServiceImpl.java` — payment processing methods
- `repository/PaymentRepository.java` — `findPendingOlderThan()` query

## Important Notes

- **No unit tests or integration tests** — project policy
- **Controllers never expose entities** — always use DTOs
- **All list endpoints MUST implement** pagination, filtering, and sorting
- **Content Negotiation** via separate controller methods (not manual Accept parsing)
- **1-indexed pagination** in API, convert to 0-indexed for Spring Data
- **Formatted SQL migrations** (not XML) for better readability
