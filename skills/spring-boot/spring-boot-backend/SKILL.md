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

## Prerequisites

The Gradle build must include: Lombok, MapStruct (with `lombok-mapstruct-binding`), Spring Data JPA, Liquibase, and a JDBC driver. If any are missing, configure them via the `spring-boot-gradle-setup` skill before proceeding.

## Non-negotiable rules

1. Services accept DTOs from the `dto` package only; never transport-specific objects (HTTP requests, Kafka messages, aggregates).
2. Services take `userId` as a parameter; never extract it from `SecurityContext`.
3. Entities use `@Getter @Setter`, never `@Data`.
4. `Page<T>` never leaves service impl — services return `PagedResult<T>`.
5. Throw dedicated exceptions (`ResourceNotFoundException`, `ConflictException`, `BadRequestException`), not `IllegalStateException`/`IllegalArgumentException`.
6. Schema managed by Liquibase; set `spring.jpa.hibernate.ddl-auto: validate`.

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
public ProfileDto create(@Valid @RequestBody ProfileCreateDto dto) {
    UUID userId = getCurrentUserId(authentication);
    return profileService.create(userId, dto);
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
public ProfileDto create(UUID userId, ProfileCreateDto dto) { ... }
```

Authentication is resolved at the entry point (controller via `Authentication`, consumer via message payload).

## Entity design

```java
@Entity
@Table(name = "profiles")
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ProfileEntity {
    @Id
    private UUID id;

    @Column(nullable = false)
    private String firstName;

    @CreatedDate
    @Column(updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;
}
```

- Use `@Getter @Setter`, never `@Data` — avoids `equals`/`hashCode` issues with lazy loading
- Use `UUID` for IDs
- Add `@CreatedDate`/`@LastModifiedDate` only to **own entities**; do NOT add to replicated entities (their lifecycle is managed by the source system)
- Requires `@EnableJpaAuditing` on a `@Configuration` class

## ID ownership

- **Own entities**: ID generated inside the service via `UUID.randomUUID()` and passed to the mapper.
- **Replicated entities** (data arriving via events from external systems): ID comes from the source system in the DTO — preserve it.

```java
// Own entity — service owns the ID
public ProfileDto create(UUID userId, ProfileCreateDto dto) {
    UUID id = UUID.randomUUID();
    ProfileEntity entity = mapper.toEntity(dto);
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
public class ProfileServiceImpl implements ProfileService {

    @Override
    @Transactional(readOnly = true)     // override for reads
    public ProfileDto findById(UUID id) { ... }

    @Override
    public ProfileDto create(UUID userId, ProfileCreateDto dto) { ... }
}
```

## Idempotent delete

DELETE must be idempotent — return 204 whether the resource exists or not:

```java
public void deleteProfile(UUID id) {
    repository.findById(id).ifPresent(entity -> {
        repository.delete(entity);
        log.info("Deleted profile: id={}", id);
    });
}
```

With business rules — checks only performed if resource is found:

```java
public void deletePaymentMethod(UUID coachId, UUID paymentMethodId) {
    paymentMethodRepository.findByIdAndCoachId(paymentMethodId, coachId)
        .ifPresent(pm -> {
            if (subscriptionRepository.existsByPaymentMethodId(paymentMethodId)) {
                throw new ConflictException("Cannot delete: assigned to subscriptions");
            }
            paymentMethodRepository.delete(pm);
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
- `references/lookup.md` — Large vs small lookup, `X-Total-Count` header.
  Load when adding lookup endpoints for dropdowns or selects.
- `references/security-oauth2.md` — Dual `SecurityFilterChain`, OAuth2 Resource Server (Keycloak/external IdP), CORS.
  Load when the service validates JWTs issued by an external IdP.
- `references/security-jjwt.md` — Dual `SecurityFilterChain`, self-issued JWTs (JJWT), Bucket4j rate limiting, login-attempt protection, CORS.
  Load when the service issues and validates its own JWTs.
- `references/logging.md` — `key=value` format, verb tenses, PII via `@ToString`.
  Load when adding or reviewing log statements.
- `references/swagger.md` — `@Operation` summary/description rules, `@ApiResponse` sparing use.
  Load when documenting controllers with Springdoc OpenAPI.
- `references/migrations.md` — Liquibase formatted SQL, SQL Style Guide, rollback, contexts.
  Load when writing or modifying Liquibase migrations.
