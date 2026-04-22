# Pagination, Filtering, Sorting

`PagedResult`/`PagedResponse` classes, `SortUtil`, `@ValidSort`, Specifications, Filter objects, `SearchParams`.

## Core classes

### PagedResult (service layer)

`Page<T>` (Spring Data) stays inside `service/impl/` and never leaks to interfaces or controllers:

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
            page.getNumber() + 1,   // convert 0-indexed to 1-indexed
            page.getSize(),
            page.getTotalElements(),
            page.getTotalPages()
        );
    }
}
```

### PagedResponse (controller layer)

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
        if (sortParam == null || sortParam.isBlank()) return Sort.unsorted();
        List<Sort.Order> orders = new ArrayList<>();
        for (String field : sortParam.split(",")) {
            field = field.trim();
            orders.add(field.startsWith("-")
                ? Sort.Order.desc(field.substring(1))
                : Sort.Order.asc(field));
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
    private UUID countryId;
}
```

## Controller / Service chain

```java
// Controller
@GetMapping(produces = {"application/json", "application/vnd.api.customer.list+json"})
public ResponseEntity<PagedResponse<CustomerListItemDto>> list(
        @Valid @ModelAttribute CustomerSearchParams params) {
    return ResponseEntity.ok(PagedResponse.of(customerService.search(params)));
}

// Service
@Transactional(readOnly = true)
public PagedResult<CustomerListItemDto> search(CustomerSearchParams params) {
    Sort sort = SortUtil.parseSortParameter(params.getSort())
        .and(Sort.by("id"));    // always append id for stable sorting
    Pageable pageable = PageRequest.of(params.getPage() - 1, params.getLimit(), sort);

    Specification<Customer> spec = CustomerSpecification.withFilters(
        params.getSearch(), params.getCountryId());
    return PagedResult.of(repository.findAll(spec, pageable).map(mapper::toListItemDto));
}
```

- Convert 1-indexed page to 0-indexed: `PageRequest.of(page - 1, ...)`
- Always append `id` as final sort field for stable sorting
- Return empty array `[]` for no results — never 404

## Specification pattern

```java
public class CustomerSpecification {

    // 1-3 params: individual arguments
    public static Specification<Customer> withFilters(String search, UUID countryId) {
        return Specification.where(searchLike(search)).and(hasCountry(countryId));
    }

    // 4+ params: use Filter object
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
}
```

## Filter class (4+ parameters)

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
