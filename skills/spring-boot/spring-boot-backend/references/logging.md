# Logging Conventions

`key=value` format, verb tenses, PII protection via `@ToString`, log levels.

## Format: key=value

All service logs use structured `key=value` parameters:

```java
log.debug("Creating profile: userId={}, data={}", userId, dto);
log.debug("Created profile: id={}, userId={}", profile.getId(), userId);
```

## Verb tense

| When | Tense | Example |
|------|-------|---------|
| Entry (before action) | Present continuous (`-ing`) | `"Creating profile: userId={}"` |
| Result (after action) | Past tense | `"Created profile: id={}"` |

```java
public ProfileDto create(UUID userId, ProfileCreateDto dto) {
    log.debug("Creating profile: userId={}, data={}", userId, dto);
    // ... business logic ...
    log.debug("Created profile: id={}, userId={}", entity.getId(), userId);
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
public class ProfileCreateDto {
    @ToString.Include
    private String firstName;    // appears in logs

    private String email;        // excluded from logs
    private String phone;        // excluded from logs
}
```

## SLF4J setup

Use Lombok's `@Slf4j` — no manual logger creation:

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class ProfileServiceImpl implements ProfileService {
    // log.debug(), log.info(), log.warn(), log.error() available
}
```
