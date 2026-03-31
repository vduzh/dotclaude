---
name: pagination-filtering
description: Spring Boot pagination implementation — PagedResponse/PagedResult classes, SortUtil, @ValidSort, Specifications, SearchParams, controller/service chain
---

# Pagination, Filtering, Sorting (Spring Boot)

Spring Boot implementation of pagination design (see `pagination-sorting` skill for API contract and JSON format).

## Core Classes

### PagedResult (Service Layer)

Project-owned record — returned by services. `Page<T>` (Spring Data) stays inside `service/impl/` and never leaks to interfaces or controllers.

```java
public record PagedResult<T>(
    List<T> content,
    int page,
    int perPage,
    long total,
    int totalPages
) {
    public static <T> PagedResult<T> of(Page<T> page) {
        return new PagedResult<>(
            page.getContent(),
            page.getNumber() + 1,  // convert 0-indexed to 1-indexed
            page.getSize(),
            page.getTotalElements(),
            page.getTotalPages()
        );
    }
}
```

### PagedResponse (Controller Layer)

Wraps `PagedResult` for HTTP response:

```java
@Data
@Schema(name = "PagedResponse")
public class PagedResponse<T> {
    private List<T> data;
    private PaginationMeta pagination;

    @Data
    public static class PaginationMeta {
        private int page;
        private int perPage;
        private long total;
        private int totalPages;
    }

    public static <T> PagedResponse<T> of(PagedResult<T> result) {
        PagedResponse<T> response = new PagedResponse<>();
        response.data = result.content();
        PaginationMeta meta = new PaginationMeta();
        meta.page = result.page();
        meta.perPage = result.perPage();
        meta.total = result.total();
        meta.totalPages = result.totalPages();
        response.pagination = meta;
        return response;
    }
}
```

### SortUtil

Converts JSON:API sort format (`name,-createdAt`) to Spring `Sort`:

```java
public class SortUtil {
    public static Sort parseSortParameter(String sortParam) {
        if (sortParam == null || sortParam.isBlank()) {
            return Sort.unsorted();
        }
        List<Sort.Order> orders = new ArrayList<>();
        for (String field : sortParam.split(",")) {
            field = field.trim();
            if (field.startsWith("-")) {
                orders.add(Sort.Order.desc(field.substring(1)));
            } else {
                orders.add(Sort.Order.asc(field));
            }
        }
        return Sort.by(orders);
    }
}
```

### @ValidSort

Custom validator for sort parameter — ensures only allowed fields are used:

```java
@Constraint(validatedBy = SortValidator.class)
@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidSort {
    String message() default "Invalid sort field";
    String[] allowed();
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

public class SortValidator implements ConstraintValidator<ValidSort, String> {
    private Set<String> allowedFields;

    @Override
    public void initialize(ValidSort annotation) {
        allowedFields = Set.of(annotation.allowed());
    }

    @Override
    public boolean isValid(String value, ConstraintValidatorContext ctx) {
        if (value == null || value.isBlank()) return true;
        return Arrays.stream(value.split(","))
            .map(String::trim)
            .map(f -> f.startsWith("-") ? f.substring(1) : f)
            .allMatch(allowedFields::contains);
    }
}
```

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

## Implementation Chain

### Controller

```java
@GetMapping(produces = {"application/json", "application/vnd.api.customer.list+json"})
@Operation(summary = "Get customers as list")
public ResponseEntity<PagedResponse<CustomerListItemDto>> getCustomersAsList(
        @Valid @ModelAttribute CustomerSearchParams params) {
    PagedResult<CustomerListItemDto> result = customerService.search(params);
    return ResponseEntity.ok(PagedResponse.of(result));
}
```

### Service

```java
@Transactional(readOnly = true)
public PagedResult<CustomerListItemDto> search(CustomerSearchParams params) {
    Sort sort = SortUtil.parseSortParameter(params.getSort());
    sort = sort.and(Sort.by("id"));  // stable sorting
    Pageable pageable = PageRequest.of(params.getPage() - 1, params.getLimit(), sort);

    Specification<Customer> spec = CustomerSpecification.withFilters(
        params.getSearch(), params.getCountryId());
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
        return countryId == null ? null
            : (root, query, cb) -> cb.equal(root.get("country").get("id"), countryId);
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
