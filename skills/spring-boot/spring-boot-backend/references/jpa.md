# Spring Data JPA Conventions

Repository naming, eager loading strategy, FK handling, and datasource configuration.

## Prefer ID over Entity in parameters

```java
// ✅ Good — works with UUID directly
Optional<Customer> findByEmailAndCountryId(String email, UUID countryId);

// ❌ Avoid — requires loading entity first
Optional<Customer> findByEmailAndCountry(String email, CountryEntity country);
```

## Eager loading — With-suffix convention

| Method style | Loading | When to use |
|---|---|---|
| Without `With` | All relationships LAZY | Default — use for most queries |
| With `With` suffix + `@Query` | Explicit `JOIN FETCH` | When the caller needs related data |

```java
// LAZY — default; all relationships lazy
Optional<Customer> findById(UUID id);

// EAGER — single JOIN FETCH
@Query("SELECT c FROM Customer c JOIN FETCH c.country WHERE c.id = :id")
Optional<Customer> findByIdWithCountry(@Param("id") UUID id);

// EAGER — multiple JOIN FETCHes; every joined association listed in the method name
@Query("""
       SELECT c FROM Customer c
       JOIN FETCH c.country
       LEFT JOIN FETCH c.paymentMethods
       WHERE c.id = :id
       """)
Optional<Customer> findByIdWithCountryAndPaymentMethods(@Param("id") UUID id);
```

- `JOIN FETCH` for required associations (`country` — NOT NULL FK).
- `LEFT JOIN FETCH` for collection associations that may be empty (`paymentMethods` — M2M, empty set is valid). A plain `JOIN FETCH` would exclude customers without any payment methods from the result.
- Only **one** collection association may be fetched per query without a cartesian explosion (`MultipleBagFetchException` if more than one `Set`/`List` is join-fetched). For multiple collections, issue separate queries or use `@EntityGraph` with `EntityGraph.EntityGraphType.LOAD` plus a pagination-aware strategy.

**Exception:** `findAll(Specification, Pageable)` override — method signature is fixed, so `@EntityGraph` is acceptable:

```java
@EntityGraph(attributePaths = {"country", "paymentMethods"})
Page<Customer> findAll(Specification<Customer> spec, Pageable pageable);
```

When `findAll` is used by multiple callers with different needs, load all potentially required relations (2-3 JOINs are acceptable).

## getReferenceById for FK relationships

Setting a foreign key does not require a SELECT — just the UUID wrapped in a proxy:

```java
// No SELECT — creates a proxy with just the ID
CountryEntity country = countryRepository.getReferenceById(countryId);
customer.setCountry(country);
customerRepository.save(customer);
```

| Method | SELECT | Validates existence | Use case |
|--------|--------|---------------------|----------|
| `findById()` | Yes | Yes | Need entity fields |
| `getReferenceById()` | No | No — at flush only | Only for FK assignment |
| `existsById()` | Yes (light) | Yes | Only check existence |

Do NOT use `getReferenceById()` when you need to access entity fields — throws `EntityNotFoundException` on first access.

### M2M association setup

For `paymentMethods` (M2M), resolve every UUID in the input via `getReferenceById` and set the resulting collection on the entity:

```java
entity.setPaymentMethods(dto.getPaymentMethods().stream()
    .map(paymentMethodRepository::getReferenceById)
    .collect(Collectors.toSet()));
```

Hibernate reconciles the current join-table rows against the new set on flush — rows added, rows removed, rows left untouched — without loading any `PaymentMethodEntity` fields.

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
