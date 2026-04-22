# Lookup Endpoint Implementation

Large vs small lookup, `X-Total-Count` header.

Expose `X-Total-Count` in CORS `exposedHeaders` — see `references/security-jjwt.md` or `references/security-oauth2.md`.

## Large lookup (server-side search)

Use when the dataset can be large (athletes, users, clients). Paginate internally, return `List<T>` + `X-Total-Count` header.

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
        .body(result.content());
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

`PagedResult` carries `total` for the `X-Total-Count` header even though the response body is `List<T>`.

## Small lookup (load all)

Use when the dataset is small and static (currencies, payment method types, subscription plans — typically <100 items).

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
