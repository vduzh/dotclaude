# Spring Data JPA Conventions

Repository naming, eager loading strategy, FK handling, and datasource configuration.

## Prefer ID over Entity in parameters

```java
// ✅ Good — works with UUID directly
Optional<Athlete> findByEmailAndCoachId(String email, UUID coachId);

// ❌ Avoid — requires loading entity first
Optional<Athlete> findByEmailAndCoach(String email, User coach);
```

## Eager loading — With-suffix convention

| Method style | Loading | When to use |
|---|---|---|
| Without `With` | All relationships LAZY | Default — use for most queries |
| With `With` suffix + `@Query` | Explicit `JOIN FETCH` | When caller needs related data |

```java
// LAZY — all relationships lazy
Optional<Balance> findByCoachId(UUID coachId);

// EAGER — explicit JOIN FETCH, all joined entities listed in name
@Query("SELECT b FROM Balance b JOIN FETCH b.currency WHERE b.coach.id = :coachId")
Optional<Balance> findByCoachIdWithCurrency(@Param("coachId") UUID coachId);

@Query("SELECT b FROM Balance b JOIN FETCH b.coach JOIN FETCH b.currency WHERE b.coach.id = :coachId")
Optional<Balance> findByCoachIdWithCoachAndCurrency(@Param("coachId") UUID coachId);
```

**Exception:** `findAll(Specification, Pageable)` override — method signature is fixed, so `@EntityGraph` is acceptable:

```java
@EntityGraph(attributePaths = {"athlete", "currency"})
Page<Invoice> findAll(Specification<Invoice> spec, Pageable pageable);
```

When `findAll` is used by multiple callers with different needs, load all potentially required relations (2-3 JOINs are acceptable).

## getReferenceById for FK relationships

```java
// No SELECT — creates proxy with just the ID
User coach = userRepository.getReferenceById(coachId);
athlete.setCoach(coach);
athleteRepository.save(athlete);
```

| Method | SELECT | Validates existence | Use case |
|--------|--------|---------------------|----------|
| `findById()` | Yes | Yes | Need entity data |
| `getReferenceById()` | No | No | Only for FK (`setCoach`) |
| `existsById()` | Yes (light) | Yes | Only check existence |

Do NOT use `getReferenceById()` when you need to access entity fields — throws `EntityNotFoundException`.

## Hibernate ddl-auto

Always set `spring.jpa.hibernate.ddl-auto: validate` — Liquibase owns the schema, Hibernate only validates it matches the entities.

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate
```

## Datasource & HikariCP

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/app-db
    username: app-db
    password: app-db
    hikari:
      maximum-pool-size: 10
      connection-timeout: 30000     # 30s
      idle-timeout: 600000          # 10min
      max-lifetime: 1800000         # 30min
```

| Profile | Database host | Pool size |
|---------|--------------|-----------|
| dev (local) | `localhost:{port}` | 10 |
| test/qa (k8s) | `postgresql.{namespace}.svc.cluster.local:5432` | 20 |
| prod (k8s) | `${SPRING_DATASOURCE_URL}` | 20+ |

Production secrets via Spring Boot ENV convention: `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`. No custom ENV names.
