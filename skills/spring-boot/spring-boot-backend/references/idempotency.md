# Idempotency

Spring Boot implementation of `rest-api-design/references/idempotency.md` — once-only POST execution backed by a database record.

**Opt-in feature.** Nothing is wired globally. Each endpoint that needs idempotency opts in by wrapping its create flow explicitly. Enable on high-stakes POSTs (orders, payments, outbound notifications); leave regular POSTs untouched. If the feature is not used, omit the table, entity, service, and cleanup job entirely.

## How the guarantee is enforced

The database is the single arbiter. A composite primary key `(idempotency_key, endpoint_path)` on the `idempotency_keys` table guarantees uniqueness across concurrent requests and across server instances — no distributed lock needed.

Flow for a single POST with an `Idempotency-Key` header:

1. Controller generates a UUID (`reservedId`) and a SHA-256 hash of the request body.
2. Service (in one `@Transactional`) inserts `{key, path, reservedId, bodyHash}` then creates the resource with `id = reservedId`.
3. If the insert succeeds, the resource is created; the transaction commits together.
4. If the insert fails with `DataIntegrityViolationException` (PK clash — the key was already used), the whole transaction rolls back. The controller looks up the existing record in a fresh read and returns the current resource (replay) or throws `ConflictException` (body mismatch).

The pre-allocated `reservedId` is what makes this atomic in a single transaction — the resource knows its own ID before the idempotency record is written.

## Database schema (Liquibase)

Local to this feature. Register in the project's changelog only when enabling idempotency:

```sql
--liquibase formatted sql

--changeset author:idempotency-0001-create-idempotency-keys
CREATE TABLE idempotency_keys (
    idempotency_key UUID         NOT NULL,
    endpoint_path   VARCHAR(512) NOT NULL,
    resource_id     UUID         NOT NULL,
    body_hash       CHAR(64)     NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at      TIMESTAMP WITH TIME ZONE NOT NULL,
    PRIMARY KEY (idempotency_key, endpoint_path)
);

CREATE INDEX idx_idempotency_expires_at ON idempotency_keys (expires_at);

--rollback DROP TABLE idempotency_keys;
```

- Composite PK matches the contract's `{key, path}` scoping — DB enforces uniqueness.
- `body_hash` is `CHAR(64)` for a SHA-256 hex digest; the original body is never stored.
- `expires_at` indexed for the cleanup job.

## Entity

```java
@Entity
@Table(name = "idempotency_keys")
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@IdClass(IdempotencyKeyEntity.Id.class)
public class IdempotencyKeyEntity {

    @jakarta.persistence.Id
    @Column(name = "idempotency_key")
    private UUID key;

    @jakarta.persistence.Id
    @Column(name = "endpoint_path")
    private String path;

    @Column(name = "resource_id", nullable = false)
    private UUID resourceId;

    @Column(name = "body_hash", nullable = false)
    private String bodyHash;

    @CreatedDate
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class Id implements Serializable {
        private UUID key;
        private String path;
    }
}
```

Composite PK via `@IdClass` — both fields carry `@jakarta.persistence.Id`; the static nested `Id` class mirrors them and must implement `Serializable` with `equals`/`hashCode` (provided by Lombok `@Data`).

## Repository

```java
public interface IdempotencyKeyRepository
        extends JpaRepository<IdempotencyKeyEntity, IdempotencyKeyEntity.Id> {

    long deleteByExpiresAtBefore(Instant threshold);
}
```

## IdempotencyService

```java
@Service
@RequiredArgsConstructor
public class IdempotencyService {

    private static final Duration RETENTION = Duration.ofHours(24);

    private final IdempotencyKeyRepository repository;
    private final ObjectMapper objectMapper;

    public String computeBodyHash(Object body) {
        try {
            byte[] json = objectMapper.writeValueAsBytes(body);
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(json);
            return HexFormat.of().formatHex(digest);
        } catch (JsonProcessingException | NoSuchAlgorithmException e) {
            throw new IllegalStateException("Failed to hash request body", e);
        }
    }

    /**
     * Reserves the {key, path} slot. Called inside the caller's @Transactional
     * so reservation and resource creation commit together.
     *
     * Throws DataIntegrityViolationException on PK clash — caller handles
     * replay vs conflict separately in a fresh transaction.
     */
    public void reserve(UUID key, String path, UUID resourceId, String bodyHash) {
        IdempotencyKeyEntity entity = IdempotencyKeyEntity.builder()
            .key(key).path(path)
            .resourceId(resourceId).bodyHash(bodyHash)
            .expiresAt(Instant.now().plus(RETENTION))
            .build();
        repository.saveAndFlush(entity);   // flush to surface the PK violation now
    }

    @Transactional(readOnly = true)
    public IdempotencyKeyEntity findExisting(UUID key, String path) {
        return repository.findById(new IdempotencyKeyEntity.Id(key, path))
            .orElseThrow(() -> new IllegalStateException(
                "Idempotency record vanished between flush and lookup"));
    }
}
```

`saveAndFlush` surfaces the PK violation immediately — a plain `save` defers the INSERT until commit, making the conflict invisible until it's too late to react.

## Service — atomic reservation + create

Two paths: with and without idempotency. The idempotent path reserves the key and creates the resource in the **same transaction**:

```java
@Service
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {

    private final CustomerRepository customerRepository;
    private final CountryRepository countryRepository;
    private final PaymentMethodRepository paymentMethodRepository;
    private final CustomerMapper mapper;
    private final IdempotencyService idempotencyService;

    @Override
    @Transactional
    public CustomerDto create(UUID userId, CustomerCreateDto dto) {
        return createInternal(UUID.randomUUID(), dto);
    }

    @Override
    @Transactional
    public CustomerDto createWithIdempotency(
            UUID idempotencyKey, String path, String bodyHash,
            UUID reservedId, CustomerCreateDto dto) {
        idempotencyService.reserve(idempotencyKey, path, reservedId, bodyHash);
        return createInternal(reservedId, dto);
    }

    private CustomerDto createInternal(UUID id, CustomerCreateDto dto) {
        CustomerEntity entity = mapper.toEntity(dto);
        entity.setId(id);
        entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
        entity.setPaymentMethods(dto.getPaymentMethods().stream()
            .map(paymentMethodRepository::getReferenceById)
            .collect(Collectors.toSet()));
        customerRepository.save(entity);
        return mapper.toDto(entity);
    }
}
```

- `reserve` throws → transaction rolls back → no resource created, no idempotency record written by THIS request (the winning record stays from whichever request reserved first).
- `createInternal` throws → same rollback; the reservation and the half-created resource both disappear. The client's next retry can succeed.

## Controller — orchestration

```java
@RestController
@RequestMapping("/api/v1/customers")
@RequiredArgsConstructor
public class CustomerController {

    private final CustomerService customerService;
    private final IdempotencyService idempotencyService;

    @PostMapping
    public ResponseEntity<CustomerDto> create(
            @RequestHeader(value = "Idempotency-Key", required = false) UUID idempotencyKey,
            @Valid @RequestBody CustomerCreateDto dto,
            Authentication authentication,
            HttpServletRequest request) {

        if (idempotencyKey == null) {
            CustomerDto created = customerService.create(getCurrentUserId(authentication), dto);
            return created201(created);
        }

        String path = request.getRequestURI();
        String bodyHash = idempotencyService.computeBodyHash(dto);
        UUID reservedId = UUID.randomUUID();

        try {
            CustomerDto created = customerService.createWithIdempotency(
                idempotencyKey, path, bodyHash, reservedId, dto);
            return created201(created);
        } catch (DataIntegrityViolationException e) {
            // Key already used — either a legitimate retry or a body mismatch.
            // The original transaction has rolled back; look up in a fresh one.
            IdempotencyKeyEntity existing = idempotencyService.findExisting(idempotencyKey, path);
            if (!existing.getBodyHash().equals(bodyHash)) {
                throw new ConflictException("Idempotency-Key reused with a different request body");
            }
            try {
                CustomerDto current = customerService.findById(existing.getResourceId());
                return created201(current);
            } catch (ResourceNotFoundException ex) {
                throw new GoneException("Resource created under this Idempotency-Key no longer exists");
            }
        }
    }

    private ResponseEntity<CustomerDto> created201(CustomerDto dto) {
        return ResponseEntity.status(HttpStatus.CREATED)
            .header("Location", "/api/v1/customers/" + dto.getId())
            .body(dto);
    }
}
```

- Both the fresh path and the replay path return `201 Created` — matches the contract (status does not distinguish first vs retry).
- `ResourceNotFoundException` → `GoneException` translation is local to this wrapper — `findById` continues to throw `NOT_FOUND` for non-idempotent `GET /{id}` callers.

## GoneException + handler

```java
public class GoneException extends RuntimeException {
    public GoneException(String message) { super(message); }
}
```

Add to `GlobalExceptionHandler` (see `references/exceptions.md`):

```java
@ExceptionHandler(GoneException.class)
@ResponseStatus(HttpStatus.GONE)
public ErrorDto handleGone(GoneException ex) {
    return ErrorDto.builder().code("GONE").message(ex.getMessage()).build();
}
```

## Scheduled cleanup

Expired records are removed daily. The indexed `expires_at` makes the delete cheap.

```java
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.idempotency.cleanup.enabled", matchIfMissing = true)
@Slf4j
public class IdempotencyCleanupJob {

    private final IdempotencyKeyRepository repository;

    @Scheduled(cron = "0 0 3 * * *")   // daily at 03:00
    @Transactional
    public void cleanup() {
        long deleted = repository.deleteByExpiresAtBefore(Instant.now());
        if (deleted > 0) {
            log.info("Cleaned up expired idempotency keys: count={}", deleted);
        }
    }
}
```

Requires `@EnableScheduling` somewhere in `@Configuration`. Disable the job via `app.idempotency.cleanup.enabled=false` if cleanup is managed elsewhere (e.g. `pg_cron`).

## Making it optional

Three levels of opt-in:

1. **Source level (primary):** the feature is a copyable unit — entity, repository, service, cleanup job, migration, `GoneException`, and the controller wrapper pattern. Omit all of it and the application works as if idempotency never existed.
2. **Per-endpoint:** controllers that don't inject `IdempotencyService` don't use idempotency. Regular POSTs coexist with idempotent ones in the same service.
3. **Runtime:** cleanup job toggled via `app.idempotency.cleanup.enabled=false`.

While the feature is being evaluated in production, prefer enabling it on **one** endpoint at a time, observing behavior, then expanding. The wrapper pattern in the controller is explicit enough that turning it off is a mechanical code removal — no flag needed.

## Status code summary

| Code | Triggered by | `ErrorDto.code` |
|------|--------------|-----------------|
| 201 Created | First request OR successful retry — current resource returned | — |
| 409 Conflict | `Idempotency-Key` reused with a different request body | `CONFLICT` |
| 410 Gone | Retry when the created resource no longer exists | `GONE` |
