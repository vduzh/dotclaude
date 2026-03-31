---
name: logging-conventions
description: Logging conventions — key=value format, verb tense rules, PII protection, log levels, SLF4J with @Slf4j
---

# Logging Conventions

Apply these conventions for consistent logging across the application.

## Format: key=value Style

All service logs use structured `key=value` parameters:

```java
log.debug("Creating profile: userId={}, data={}", userId, dto);
log.debug("Created profile: id={}, userId={}", profile.getId(), userId);
```

## Verb Tense

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

## Log Levels

| Level | When | Example |
|-------|------|---------|
| `debug` | Normal operations, entry/exit | `"Finding profile: id={}"` |
| `info` | Business events, state changes | `"Deleted profile: id={}"` |
| `warn` | Recoverable issues | `"Cache miss for profile: id={}"` |
| `error` | Failures requiring attention | `"Failed to process payment: id={}"` |

**Never log PII at INFO level.** Debug-level logs with PII are acceptable for development but controlled via `@ToString`.

## PII Protection

Control what appears in logs via `@ToString(onlyExplicitlyIncluded = true)` on DTOs:

```java
@Data
@ToString(onlyExplicitlyIncluded = true)
public class ProfileCreateDto {
    @ToString.Include
    private String firstName;    // ✅ appears in logs

    private String email;        // 🔒 excluded from logs
    private String phone;        // 🔒 excluded from logs
}
```

When this DTO is logged (`log.debug("data={}", dto)`), only `firstName` appears.

## SLF4J Setup

Use Lombok's `@Slf4j` — no manual logger creation:

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class ProfileServiceImpl implements ProfileService {
    // log.debug(), log.info(), log.warn(), log.error() available automatically
}
```
