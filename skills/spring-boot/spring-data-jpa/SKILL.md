---
name: spring-data-jpa
description: Spring Data JPA conventions — With-suffix for eager loading, getReferenceById for FK, ID over Entity in params, @EntityGraph pragmatic approach
---

# Spring Data JPA Conventions

Apply these conventions when writing repository interfaces and queries.

## Prefer ID Over Entity in Parameters

Always use `...AndCoachId(UUID coachId)` instead of `...AndCoach(User coach)`:

```java
// ✅ Good — works with UUID directly, no need to load entity
Optional<Athlete> findByEmailAndCoachId(String email, UUID coachId);

// ❌ Avoid — requires entity, may cause unnecessary SELECT
Optional<Athlete> findByEmailAndCoach(String email, User coach);
```

Both generate the same SQL (`WHERE email = ? AND coach_id = ?`), but `...AndCoachId` doesn't require loading the entity first.

## Eager Loading — With Suffix Convention

Clear separation of methods by loading strategy:

### Without `With` = All Relationships LAZY

```java
// Basic query methods — all relationships stay LAZY
Optional<Balance> findByCoachId(UUID coachId);
Optional<User> findByEmail(String email);
```

### With `With` Suffix = Explicit JOIN FETCH

```java
// Single relationship
@Query("SELECT b FROM Balance b JOIN FETCH b.currency WHERE b.coach.id = :coachId")
Optional<Balance> findByCoachIdWithCurrency(@Param("coachId") UUID coachId);

// Multiple relationships — all listed in name
@Query("SELECT b FROM Balance b JOIN FETCH b.coach JOIN FETCH b.currency WHERE b.coach.id = :coachId")
Optional<Balance> findByCoachIdWithCoachAndCurrency(@Param("coachId") UUID coachId);
```

Benefits:
- Method name explicitly shows what is loaded
- Basic methods never do unnecessary JOINs
- No hidden `@EntityGraph` magic
- Consistent pattern across the project

### Exception: `findAll(Specification, Pageable)` Override

When overriding `JpaSpecificationExecutor.findAll()`, the method signature is fixed — cannot rename. In this case, `@EntityGraph` is acceptable:

```java
@EntityGraph(attributePaths = {"currency"})
Page<User> findAll(Specification<User> spec, Pageable pageable);
```

### Pragmatic Approach for findAll

When `findAll(Specification, Pageable)` is used by multiple callers with different data requirements, load all relations that might be needed:

```java
// Load everything that any caller might need
@EntityGraph(attributePaths = {"athlete", "currency"})
Page<Invoice> findAll(Specification<Invoice> spec, Pageable pageable);
```

Why this is OK:
- 2-3 JOINs have minimal overhead
- Simpler code, no custom implementations
- Optimize only if profiling shows a problem

## getReferenceById for FK Relationships

When you only need an entity to set a FK relationship:

```java
// No SELECT — creates proxy with just the ID
User coach = userRepository.getReferenceById(coachId);
athlete.setCoach(coach);
athleteRepository.save(athlete);  // INSERT with coach_id
```

`getReferenceById()` returns a proxy with only the ID populated. No database query is executed.

**Use when:**
- You only need the entity to set a FK relationship
- You've already validated the entity exists

**Do NOT use when** you need to access entity fields — that will trigger a SELECT or throw `EntityNotFoundException`.

| Method | SELECT | Validates Existence | Use Case |
|--------|--------|---------------------|----------|
| `findById()` | Yes | Yes | Need entity data |
| `getReferenceById()` | No | No | Only for FK (`setCoach`) |
| `existsById()` | Yes (light) | Yes | Only check existence |
