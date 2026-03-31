---
name: spring-layered-arch
description: Spring Boot layered architecture — Controller/Service/Repository pattern, DI conventions, adapter pattern, auth as parameter, entity design
---

# Spring Boot Layered Architecture

Apply these patterns when structuring Spring Boot applications.

## Layer Responsibilities

**Controller → Service → Repository → Entity**

| Layer | Responsibilities | Rules |
|-------|-----------------|-------|
| **Controller** | HTTP request/response, validation | Works with DTOs only, never exposes entities |
| **Service** | Business logic, transactions | Works with DTOs for input/output, never leaks `Page<T>` |
| **Repository** | Data access | Spring Data JPA (`JpaRepository` + `JpaSpecificationExecutor`) |
| **Entity** | JPA model | Hibernate annotations, never leaves service layer |

## Dependency Injection

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

## Adapter Pattern

Services only accept DTOs from the `dto` package, **never** transport-specific objects (HTTP requests, Kafka messages, aggregates). Each entry point is an adapter that converts its transport objects into service DTOs:

```java
// Controller — adapts HTTP to service DTOs
@PostMapping
public ProfileDto create(@Valid @RequestBody ProfileCreateDto dto) {
    return profileService.create(userId, dto);
}

// Kafka consumer — adapts message to service DTOs
@KafkaListener(topics = "user.events")
public void handle(UserAggregate aggregate) {
    UserDto dto = aggregateMapper.toDto(aggregate);  // convert first
    userService.create(dto);                          // then call service
}
```

This keeps services infrastructure-agnostic and reusable across entry points.

## Auth as Parameter

Services receive `userId` as a method parameter, **never** extract it from `SecurityContext` directly:

```java
// ✅ Good — service is infrastructure-agnostic
public ProfileDto create(UUID userId, ProfileCreateDto dto) { ... }

// ❌ Bad — service coupled to Spring Security
public ProfileDto create(ProfileCreateDto dto) {
    UUID userId = SecurityContextHolder.getContext()...  // don't do this
}
```

Authentication is resolved at the entry point (controller via `Authentication`, consumer via message payload).

## Entity Design

```java
@Entity
@Table(name = "profiles")
@Getter @Setter           // NOT @Data — avoids equals/hashCode issues with lazy loading
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

- Use `@Getter @Setter` on entities, NOT `@Data`
- Use `UUID` for IDs
- Audit fields (`@CreatedDate`, `@LastModifiedDate`) — add only to own entities. Do NOT add to replicated entities (their lifecycle is managed by the source system)

## ID Ownership

- **Own entities**: `id` is generated inside the service via `UUID.randomUUID()` and passed to the mapper. The caller doesn't control the ID.
  ```java
  public ProfileDto create(UUID userId, ProfileCreateDto dto) {
      UUID id = UUID.randomUUID();
      ProfileEntity entity = mapper.toEntity(dto);
      entity.setId(id);
      // ...
  }
  ```
- **Replicated entities** (data from external systems via events): `id` comes from the source system inside the DTO. The service must preserve the original ID.

## Audit Fields

Two approaches — choose one per project:

| Approach | Annotations | Requires |
|----------|------------|----------|
| Spring Data Auditing | `@CreatedDate`, `@LastModifiedDate` | `@EnableJpaAuditing` on config |
| Hibernate timestamps | `@CreationTimestamp`, `@UpdateTimestamp` | Nothing extra |

Add audit fields only to **own entities**. Do NOT add to replicated entities — their lifecycle is managed by the source system.

## Enums Organization

All enums in separate files in `model/enums/` package:
- **Always** create enums as standalone files, not as nested classes inside entities
- Naming: Use descriptive names with entity prefix when needed (`InvoiceStatus`, `TransactionType`)

## Transaction Management

```java
@Service
@Transactional                        // default for all methods
@RequiredArgsConstructor
public class ProfileServiceImpl implements ProfileService {

    @Override
    @Transactional(readOnly = true)    // override for reads
    public ProfileDto findById(UUID id) { ... }

    @Override
    public ProfileDto create(UUID userId, ProfileCreateDto dto) { ... }
}
```

## Delete — Idempotent Pattern

See `rest-api-design` skill for the design rationale. Implementation:

```java
public void deleteXxx(UUID id) {
    repository.findById(id).ifPresent(entity -> {
        repository.delete(entity);
        log.info("Deleted xxx with ID: {}", id);
    });
}
```

With business rules — checks only performed if the resource is found:

```java
public void deletePaymentMethod(UUID coachId, UUID paymentMethodId) {
    paymentMethodRepository.findByIdAndCoachId(paymentMethodId, coachId)
        .ifPresent(paymentMethod -> {
            if (subscriptionRepository.existsByPaymentMethodId(paymentMethodId)) {
                throw new ConflictException("Cannot delete: assigned to subscriptions");
            }
            paymentMethodRepository.delete(paymentMethod);
        });
}
```

## Method Ordering

- **Controllers**: by HTTP verb (GET, POST, PUT, PATCH, DELETE)
- **Services**: by CRUD (find/read, create, update, patch, delete)
