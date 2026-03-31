---
name: pagination-filtering
description: Pagination, filtering, and sorting — JSON:API sort format, PagedResponse wrapper, Spring Specifications, Filter pattern, SearchParams
---

# Pagination, Filtering, Sorting

MANDATORY for all list endpoints. Apply these patterns when implementing collection endpoints.

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | integer | 1 | 1-indexed page number |
| `limit` | integer | 20 | Items per page (1-100) |
| `sort` | string | `-createdAt` | JSON:API format sort |
| `search` | string | — | Search across multiple fields (ILIKE) |
| Filter params | varies | — | Entity-specific filters (`status`, `countryId`, etc.) |

## JSON:API Sort Format

- **Ascending**: `sort=name`
- **Descending**: `sort=-createdAt` (prefix with `-`)
- **Multiple fields**: `sort=name,-createdAt` (comma-separated)

Example: `GET /api/v1/customers?page=2&limit=50&search=john&sort=name,-createdAt`

## SearchParams DTO

```java
@Data
public class CustomerSearchParams {
    @Min(1)
    private Integer page = 1;

    @Min(1) @Max(100)
    private Integer limit = 20;

    @ValidSort(allowed = {"name", "email", "createdAt"})
    private String sort = "-createdAt";

    private String search;
    private UUID countryId;  // entity-specific filter
}
```

## PagedResponse Wrapper

All list endpoints (`application/vnd.api.*.list+json`) return:

```json
{
  "data": [...],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 156,
    "totalPages": 8
  }
}
```

**NOT affected** (return `T[]` directly):
- Lookup endpoints (`*.lookup+json`)
- Single resource endpoints (`GET /{id}`)
- Mutation endpoints (POST, PUT, PATCH, DELETE)
- Reference/dictionary endpoints

## Implementation Chain

### Controller

```java
@GetMapping(produces = {"application/json", "application/vnd.api.customer.list+json"})
public ResponseEntity<PagedResponse<CustomerListItemDto>> getCustomersAsList(
        @Valid @ModelAttribute CustomerSearchParams params) {
    PagedResult<CustomerListItemDto> result = customerService.search(params);
    return ResponseEntity.ok(PagedResponse.of(result));
}
```

### Service

Services return `PagedResult<T>` (project-owned record). `Page<T>` (Spring Data) stays inside `service/impl/` — never leaks to interfaces or controllers:

```java
@Transactional(readOnly = true)
public PagedResult<CustomerListItemDto> search(CustomerSearchParams params) {
    Sort sort = SortUtil.parseSortParameter(params.getSort());
    sort = sort.and(Sort.by("id"));  // stable sorting
    Pageable pageable = PageRequest.of(params.getPage() - 1, params.getLimit(), sort);

    Specification<Customer> spec = CustomerSpecification.withFilters(params.getSearch(), params.getCountryId());
    Page<Customer> page = repository.findAll(spec, pageable);

    return PagedResult.of(page.map(mapper::toListItemDto));
}
```

Key points:
- Convert 1-indexed page to 0-indexed: `PageRequest.of(page - 1, limit, sort)`
- Always add `id` as final sort field for stable sorting
- Return empty array `[]` for no results (NOT 404)

## Specification Pattern

```java
public class CustomerSpecification {

    // 1-3 parameters: individual arguments
    public static Specification<Customer> withFilters(String search, UUID countryId) {
        return Specification.where(searchLike(search))
            .and(hasCountry(countryId));
    }

    // 4+ parameters: use Filter object
    public static Specification<Customer> withFilters(CustomerFilter filter) {
        return Specification.where(searchLike(filter.getSearch()))
            .and(hasCountry(filter.getCountryId()))
            .and(hasStatus(filter.getStatus()))
            .and(hasType(filter.getType()));
    }

    private static Specification<Customer> searchLike(String search) {
        if (search == null || search.isBlank()) return null;
        String pattern = "%" + search.toLowerCase() + "%";
        return (root, query, cb) -> cb.or(
            cb.like(cb.lower(root.get("name")), pattern),
            cb.like(cb.lower(root.get("email")), pattern)
        );
    }

    private static Specification<Customer> hasCountry(UUID countryId) {
        return countryId == null ? null : (root, query, cb) -> cb.equal(root.get("country").get("id"), countryId);
    }
}
```

## Filter Class (4+ Parameters)

Place in `repository/spec/` next to Specification:

```java
@Data
@Builder
public class InvoiceFilter {
    @NonNull private UUID coachId;  // required
    private UUID athleteId;          // optional
    private InvoiceStatus status;
    private String search;
}
```
