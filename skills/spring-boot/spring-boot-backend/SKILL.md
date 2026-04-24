---
name: spring-boot-backend
description: >
  Implement and maintain the runtime code of a Spring Boot 3.5+ backend —
  layered architecture, services, JPA entities, REST controllers, DTOs,
  validation, exceptions, pagination, security, logging, and Liquibase
  migrations. Use this skill when the user is building, modifying, or
  reviewing a Spring Boot application's Java code or database migrations.
---

# Spring Boot Backend

Scope: Spring Boot 3.5+ application runtime code and database migrations.

This skill implements the REST API contract defined in the `rest-api-design` skill. Refer to it for URI conventions, HTTP status codes, content negotiation, error response shape, pagination semantics, and authentication/rate-limiting requirements. This skill defines only the Spring Boot runtime mapping of that contract.

**Out of scope:** `ETag`/`If-Match` optimistic concurrency — introduce when multi-editor conflicts become a concrete business requirement (see the `rest-api-design` scope).

## Non-negotiable rules

1. Services accept DTOs from the `dto` package only; never transport-specific objects (HTTP requests, Kafka messages, aggregates).
2. Services take `userId` as a parameter; never extract it from `SecurityContext`.
3. Entities use `@Getter @Setter`, never `@Data`.
4. `Page<T>` never leaves service impl — services return `PagedResult<T>`.
5. Throw dedicated exceptions (`ResourceNotFoundException`, `ConflictException`, `BadRequestException`), not `IllegalStateException`/`IllegalArgumentException`.
6. Schema managed by Liquibase; set `spring.jpa.hibernate.ddl-auto: validate`.
7. All endpoints are mounted under `/api/v1/...` — URI versioning per the contract.
8. Controllers expose the **default representation** on `application/json` — no vendor media type for the default. Declare `produces = "application/vnd.api.{entity}.{view}+json"` only for alternative variants (`lookup`, `summary`, `full`).
9. Tokens are delivered in `HttpOnly` cookies, never in the response body or `Authorization` header.

## HTTP contract mapping

Controllers must map paths, verbs, and media types per `rest-api-design`:

| Concern | Rule | Where implemented |
|---------|------|-------------------|
| Base path | `/api/v1/` | `@RequestMapping` on every `@RestController` |
| Collection name | plural noun, `kebab-case` | `@RequestMapping("/payment-methods")` — never `/paymentMethods`, never `/paymentMethod` |
| No verbs in URI | HTTP method carries the action | `POST /customers`, not `/customers/create` |
| Lookup by alt id | `/{resource}/by-{field}/{value}` | `@GetMapping("/customers/by-email/{email}")` |
| Alt identifier with reserved chars | query parameter | `@GetMapping("/customers") + @RequestParam email` |

These URI rules are enforced in controllers only; services operate on IDs and DTOs.

## Layer responsibilities

**Controller → Service → Repository → Entity**

| Layer | Responsibilities | Rules |
|-------|-----------------|-------|
| **Controller** | HTTP request/response, validation | Works with DTOs only, never exposes entities |
| **Service** | Business logic, transactions | Works with DTOs for input/output, never leaks `Page<T>` |
| **Repository** | Data access | Spring Data JPA (`JpaRepository` + `JpaSpecificationExecutor`) |
| **Entity** | JPA model | Hibernate annotations, never leaves service layer |

## Package structure

| Package | Contents |
|---------|----------|
| `controller/` | `@RestController` classes |
| `service/` | Service interfaces |
| `service/impl/` | `XxxServiceImpl` implementations |
| `repository/` | Spring Data JPA repositories |
| `repository/spec/` | `XxxSpecification` and `XxxFilter` classes |
| `model/` (or `repository/jpa/entity/`) | JPA entities |
| `model/enums/` | All enums as standalone files |
| `dto/` | Shared DTOs (`PagedResult`, `PagedResponse`, `Patchable`, `ErrorDto`) |
| `dto/{domain}/` | Domain-specific DTOs (`XxxCreateDto`, `XxxUpdateDto`, `XxxPatchDto`, `XxxDto`, `XxxSearchParams`) |
| `mapper/` | MapStruct mappers |
| `exception/` | Exception classes and `GlobalExceptionHandler` |
| `config/` | Spring `@Configuration` classes |
| `security/` | Security filters and helpers |
| `validation/` | Custom `ConstraintValidator` classes |
| `util/` | Utility classes |
| `consumer/` / `producer/` | Kafka consumers/producers (when messaging is used) |
| `scheduler/` | `@Scheduled` tasks (when applicable) |

## Dependency injection

Constructor injection via Lombok — no `@Autowired`:

```java
@Service
@RequiredArgsConstructor
public class CustomerService {
    private final CustomerRepository repository;
    private final CustomerMapper mapper;
}
```

All dependencies are `private final` fields.

## Adapter pattern

Services only accept DTOs from the `dto` package. Each entry point (controller, Kafka consumer, scheduler) converts its transport objects into service DTOs before calling the service. Services receive `userId` as a method parameter, never extract it from `SecurityContext`.

```java
// Kafka consumer — adapts message to service DTOs
@KafkaListener(topics = "user.events")
public void handle(UserAggregate aggregate) {
    UserDto dto = aggregateMapper.toDto(aggregate);
    userService.create(dto);
}
```

Controller adapter pattern — see `references/controller.md`.

## Method ordering

- **Controllers**: by HTTP verb (GET, POST, PUT, PATCH, DELETE)
- **Services**: by CRUD (find/read, create, update, patch, delete)

## Optional references

Load the reference file for each area the current task touches:

- `references/controller.md` — BaseController, CRUD skeleton, ResponseEntity conventions, authentication resolution, request binding.
  Load when creating or modifying controllers.
- `references/service.md` — Interface/Impl structure, CRUD skeleton, transaction management, ownership verification, idempotent delete, helper methods.
  Load when creating or modifying services.
- `references/dto.md` — DTO class structure, Lombok per DTO type, Bean Validation, `@Schema`.
  Load when creating or modifying DTOs.
- `references/mapper.md` — MapStruct mapper interface, method naming, ignore rules, sub-mappers, collection helpers.
  Load when creating or modifying mappers.
- `references/jpa.md` — Entity design (annotations, ID ownership, enums), repository conventions, With-suffix for JOIN FETCH, `getReferenceById`, `@EntityGraph`, datasource/HikariCP config.
  Load when creating or modifying entities, writing repositories or queries, or tuning datasource config.
- `references/exceptions.md` — Dedicated exception classes, `GlobalExceptionHandler`, `ErrorDto`, Exception-vs-Optional.
  Load when adding error handling or a new exception type.
- `references/pagination.md` — `PagedResult`/`PagedResponse`, `SortUtil`, `@ValidSort`, Specifications, Filter objects, `SearchParams`.
  Load when implementing list endpoints with paging, sorting, or filtering.
- `references/patch.md` — `Patchable`, `@NullOrNotBlank`, `@NotEmptyPatch`, MapStruct `@BeanMapping` for partial updates.
  Load when implementing PATCH endpoints.
- `references/idempotency.md` — `Idempotency-Key` once-only execution via a DB-backed record (opt-in feature, local migration).
  Load when implementing retry-safe POST.
- `references/lookup.md` — Large vs small lookup, `X-Total-Count` header.
  Load when adding lookup endpoints for dropdowns or selects.
- `references/security-oauth2.md` — Dual `SecurityFilterChain`, OAuth2 Resource Server (Keycloak/external IdP), CORS.
  Load when the service validates JWTs issued by an external IdP.
- `references/security-jwt.md` — SecurityConfig, JwtAuthenticationFilter, HttpOnly cookie, AuthController, account state gating, anti-enumeration, login-attempt protection, CORS, token hashing, client IP detection.
  Load when the service issues and validates its own JWTs.
- `references/rate-limiting.md` — Bucket4j per-endpoint and per-user filters, `X-RateLimit-*` headers, email-trigger cooldown, RateLimitExceededException.
  Load when adding rate limiting to the API.
- `references/refresh-tokens.md` — Refresh-token flow (opt-in): rotation, family revocation on reuse, scope-limited cookie, server-side revocation on logout, hashed storage.
  Load when implementing short-lived access tokens + refresh.
- `references/logging.md` — `key=value` format, verb tenses, PII via `@ToString`.
  Load when adding or reviewing log statements.
- `references/swagger.md` — `@Operation` summary/description rules, `@ApiResponse` sparing use.
  Load when documenting controllers with Springdoc OpenAPI.
- `references/migrations.md` — Liquibase formatted SQL, SQL Style Guide, rollback, contexts.
  Load when writing or modifying Liquibase migrations.
