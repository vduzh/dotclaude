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

## Prerequisites

The Gradle build must include: Lombok, MapStruct (with `lombok-mapstruct-binding`), Spring Data JPA, Liquibase, and a JDBC driver. If any are missing, configure them via the `spring-boot-gradle-setup` skill before proceeding.

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
| `service/` | Service interfaces and `XxxServiceImpl` implementations |
| `repository/` | Spring Data JPA repositories |
| `repository/spec/` | `XxxSpecification` and `XxxFilter` classes |
| `model/` (or `repository/jpa/entity/`) | JPA entities |
| `model/enums/` | All enums as standalone files |
| `dto/` | Request/response DTOs |
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

Services only accept DTOs from the `dto` package. Each entry point (controller, Kafka consumer, scheduler) converts its transport objects into service DTOs before calling the service:

```java
// Controller — adapts HTTP to service DTOs
@PostMapping
public CustomerDto create(@Valid @RequestBody CustomerCreateDto dto) {
    UUID userId = getCurrentUserId(authentication);
    return customerService.create(userId, dto);
}

// Kafka consumer — adapts message to service DTOs
@KafkaListener(topics = "user.events")
public void handle(UserAggregate aggregate) {
    UserDto dto = aggregateMapper.toDto(aggregate);
    userService.create(dto);
}
```

## Auth as parameter

Services receive `userId` as a method parameter, never extract it from `SecurityContext`:

```java
// ✅ Good — service is infrastructure-agnostic
public CustomerDto create(UUID userId, CustomerCreateDto dto) { ... }
```

Authentication is resolved at the entry point (controller via `Authentication`, consumer via message payload).

## Entity design

```java
@Entity
@Table(name = "customers")
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CustomerEntity {
    @Id
    private UUID id;

    @Column(nullable = false)
    private String firstName;

    @Column(nullable = false)
    private String lastName;

    private String email;                    // nullable

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private AccountStatus status;

    @CreatedDate
    @Column(updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;
}
```

Associations (`country`, `paymentMethods`) are omitted here for clarity — see `references/jpa.md` for `@ManyToOne`/`@ManyToMany` mappings on this entity.

- Use `@Getter @Setter`, never `@Data` — avoids `equals`/`hashCode` issues with lazy loading
- Use `UUID` for IDs
- Add `@CreatedDate`/`@LastModifiedDate` only to **own entities**; do NOT add to replicated entities (their lifecycle is managed by the source system)
- Requires `@EnableJpaAuditing` on a `@Configuration` class

## ID ownership

- **Own entities**: ID generated inside the service via `UUID.randomUUID()` and passed to the mapper.
- **Replicated entities** (data arriving via events from external systems): ID comes from the source system in the DTO — preserve it.

```java
// Own entity — service owns the ID
public CustomerDto create(UUID userId, CustomerCreateDto dto) {
    UUID id = UUID.randomUUID();
    CustomerEntity entity = mapper.toEntity(dto);
    entity.setId(id);
    repository.save(entity);
    return mapper.toDto(entity);
}
```

## Enums organization

All enums in separate files in `model/enums/`. Never nested inside entities.

## Transaction management

```java
@Service
@Transactional                          // default for all methods
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {

    @Override
    @Transactional(readOnly = true)     // override for reads
    public CustomerDto findById(UUID id) { ... }

    @Override
    public CustomerDto create(UUID userId, CustomerCreateDto dto) { ... }
}
```

## Idempotent delete

DELETE must be idempotent — return 204 whether the resource exists or not:

```java
public void deleteCustomer(UUID id) {
    customerRepository.findById(id).ifPresent(entity -> {
        customerRepository.delete(entity);
        log.info("Deleted customer: id={}", id);
    });
}
```

With business rules — checks only performed if resource is found:

```java
public void deleteCustomer(UUID id) {
    customerRepository.findById(id).ifPresent(customer -> {
        if (customer.getStatus() != AccountStatus.INACTIVE) {
            throw new ConflictException("Cannot delete: customer must be INACTIVE first");
        }
        customerRepository.delete(customer);
    });
}
```

## Method ordering

- **Controllers**: by HTTP verb (GET, POST, PUT, PATCH, DELETE)
- **Services**: by CRUD (find/read, create, update, patch, delete)

## Optional references

Load the reference file for each area the current task touches:

- `references/dto.md` — DTO class structure, Lombok per DTO type, Bean Validation, `@Schema`, MapStruct mapper.
  Load when creating or modifying DTOs or mappers.
- `references/jpa.md` — Repository conventions, With-suffix for JOIN FETCH, `getReferenceById`, `@EntityGraph`, datasource/HikariCP config.
  Load when writing repositories, queries, or tuning datasource config.
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
- `references/security-jjwt.md` — Dual `SecurityFilterChain`, self-issued JWTs (JJWT), account state gating, anti-enumeration, per-IP + per-user rate limiting with `X-RateLimit-*` headers, login-attempt protection (IP-email + email-global), email-trigger cooldown, persisted secret hashing, CORS.
  Load when the service issues and validates its own JWTs.
- `references/refresh-tokens.md` — Refresh-token flow (opt-in): rotation, family revocation on reuse, scope-limited cookie, server-side revocation on logout, hashed storage.
  Load when implementing short-lived access tokens + refresh.
- `references/logging.md` — `key=value` format, verb tenses, PII via `@ToString`.
  Load when adding or reviewing log statements.
- `references/swagger.md` — `@Operation` summary/description rules, `@ApiResponse` sparing use.
  Load when documenting controllers with Springdoc OpenAPI.
- `references/migrations.md` — Liquibase formatted SQL, SQL Style Guide, rollback, contexts.
  Load when writing or modifying Liquibase migrations.
