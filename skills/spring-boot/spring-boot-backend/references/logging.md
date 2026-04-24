# Logging Conventions

`key=value` format, verb tenses, PII protection via `@ToString`, log levels.

## Format: key=value

All service logs use structured `key=value` parameters:

```java
log.debug("Creating customer: userId={}, data={}", userId, dto);
log.debug("Created customer: id={}, userId={}", customer.getId(), userId);
```

## Verb tense

| When | Tense | Example |
|------|-------|---------|
| Entry (before action) | Present continuous (`-ing`) | `"Creating customer: userId={}"` |
| Result (after action) | Past tense | `"Created customer: id={}"` |

```java
public CustomerDto create(UUID userId, CustomerCreateDto dto) {
    log.debug("Creating customer: userId={}, data={}", userId, dto);
    // ... business logic ...
    log.debug("Created customer: id={}, userId={}", entity.getId(), userId);
    return mapper.toDto(entity);
}
```

## Log levels

| Level | When |
|-------|------|
| `debug` | Normal operations, entry/exit |
| `info` | Business events, state changes |
| `warn` | Recoverable issues |
| `error` | Failures requiring attention |

Never log PII at INFO level.

## PII protection

Control what appears in logs via `@ToString(onlyExplicitlyIncluded = true)` on input DTOs:

```java
@Data
@ToString(onlyExplicitlyIncluded = true)
public class CustomerCreateDto {
    @ToString.Include
    private String firstName;    // appears in logs

    @ToString.Include
    private String lastName;     // appears in logs

    private String email;        // excluded from logs (PII)

    @ToString.Include
    private AccountStatus status;

    @ToString.Include
    private UUID countryId;
}
```

Identifiers (`status`, `countryId`, `paymentMethods`) are safe to log. Direct personal data (`email`, phone numbers if present, full addresses) stays out.

## SLF4J setup

Use Lombok's `@Slf4j` — no manual logger creation:

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {
    // log.debug(), log.info(), log.warn(), log.error() available
}
```
