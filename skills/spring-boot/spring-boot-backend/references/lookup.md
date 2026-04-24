# Lookup Endpoint Implementation

Large vs small lookup, `X-Total-Count` header.

Expose `X-Total-Count` in CORS `exposedHeaders` — see `references/security-jwt.md` or `references/security-oauth2.md`.

## Large lookup (server-side search)

Use when the dataset can be large (customers, countries). Paginate internally, return `List<T>` + `X-Total-Count` header.

### Controller

```java
@GetMapping(produces = "application/vnd.api.customer.lookup+json")
@Operation(summary = "Get customers as lookup")
public ResponseEntity<List<CustomerLookupDto>> getCustomersAsLookup(
        @Valid @ModelAttribute CustomerLookupSearchParams params) {
    PagedResult<CustomerLookupDto> result = customerService.searchCustomersAsLookup(params);
    return ResponseEntity.ok()
        .header("X-Total-Count", String.valueOf(result.total()))
        .body(result.content());
}
```

### SearchParams

```java
@Data
public class CustomerLookupSearchParams {
    private String search;

    @Min(1) @Max(100)
    private Integer limit = 50;
}
```

### Service

```java
@Transactional(readOnly = true)
public PagedResult<CustomerLookupDto> searchCustomersAsLookup(CustomerLookupSearchParams params) {
    Pageable pageable = PageRequest.of(0, params.getLimit(), Sort.by("lastName", "firstName"));
    Specification<Customer> spec = CustomerSpecification.withFilters(params.getSearch(), null, null);
    Page<Customer> page = repository.findAll(spec, pageable);
    return PagedResult.of(page.map(mapper::toLookupDto));
}
```

`PagedResult` carries `total` for the `X-Total-Count` header even though the response body is `List<T>`.

The same pattern applies to `Country` (~200 entries) — swap the entity, DTO, and the `.country.lookup+json` media type; sort by `name`.

## Small lookup (load all)

Use when the dataset is small and static (payment methods, subscription plans — typically under 50 items).

### Controller

```java
@GetMapping(produces = "application/vnd.api.payment-method.lookup+json")
@Operation(summary = "Get payment methods as lookup")
public List<PaymentMethodLookupDto> getPaymentMethodsAsLookup() {
    return paymentMethodService.getAllAsLookup();
}
```

### Service

```java
@Transactional(readOnly = true)
public List<PaymentMethodLookupDto> getAllAsLookup() {
    return repository.findAll(Sort.by("name")).stream()
        .map(mapper::toLookupDto)
        .toList();
}
```

No `X-Total-Count`, no pagination — the client holds the full list and filters in memory.
