---
name: lookup-implementation
description: Spring Boot lookup endpoint implementation — controller with X-Total-Count header, service for large/small lookups, content negotiation
---

# Lookup Endpoint Implementation (Spring Boot)

Spring Boot implementation of lookup endpoints (see `lookup-endpoints` skill for API contract and design).

## Large Lookup (Server-Side Search)

### Controller

```java
@GetMapping(produces = "application/vnd.api.athlete.lookup+json")
@Operation(summary = "Get athletes as lookup")
public ResponseEntity<List<AthleteLookupDto>> getAthletesAsLookup(
        @AuthenticationPrincipal UserDetails userDetails,
        @Valid @ModelAttribute AthleteLookupSearchParams params) {
    UUID userId = getCurrentUserId(userDetails);
    PagedResult<AthleteLookupDto> result = athleteService.searchAthletesAsLookup(userId, params);

    return ResponseEntity.ok()
        .header("X-Total-Count", String.valueOf(result.total()))
        .body(result.content());  // List<T> — contract unchanged
}
```

### SearchParams

```java
@Data
public class AthleteLookupSearchParams {
    private String search;

    @Min(1) @Max(100)
    private Integer limit = 50;
}
```

### Service

```java
@Transactional(readOnly = true)
public PagedResult<AthleteLookupDto> searchAthletesAsLookup(UUID userId, AthleteLookupSearchParams params) {
    Pageable pageable = PageRequest.of(0, params.getLimit(), Sort.by("lastName", "firstName"));

    Specification<Athlete> spec = AthleteSpecification.withFilters(params.getSearch(), userId);
    Page<Athlete> page = repository.findAll(spec, pageable);

    return PagedResult.of(page.map(mapper::toLookupDto));
}
```

Note: `PagedResult` is reused here to carry `total` for the `X-Total-Count` header, even though the response body is `List<T>`.

## Small Lookup (Load All)

### Controller

```java
@GetMapping(produces = "application/vnd.api.currency.lookup+json")
@Operation(summary = "Get currencies as lookup")
public List<CurrencyLookupDto> getCurrenciesAsLookup() {
    return currencyService.getAllAsLookup();
}
```

### Service

```java
@Transactional(readOnly = true)
public List<CurrencyLookupDto> getAllAsLookup() {
    return repository.findAll(Sort.by("name")).stream()
        .map(mapper::toLookupDto)
        .toList();
}
```

## CORS Configuration

Expose `X-Total-Count` header for frontend access:

```yaml
app:
  cors:
    allowed-origins: http://localhost:3000
    exposed-headers: Authorization, X-Total-Count
```

```java
@Override
public void addCorsMappings(CorsRegistry registry) {
    registry.addMapping("/api/**")       // scope to /api/** only, not /**
        .allowedOrigins(corsProperties.getAllowedOrigins())
        .allowedHeaders("Content-Type", "Authorization", "Accept")  // explicit, never wildcard *
        .exposedHeaders("Authorization", "X-Total-Count")
        .allowCredentials(true);
}
```

**Important:** When `allowCredentials(true)`, always list allowed headers explicitly — avoid wildcard `*` to keep CORS configuration explicit and spec-compliant.
