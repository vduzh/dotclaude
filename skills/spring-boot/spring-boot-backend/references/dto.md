# DTO Implementation

Spring Boot DTO conventions — class structure, Lombok, Bean Validation, `@Schema`, MapStruct mapper.

## Lombok annotations per DTO type

| DTO | Lombok |
|-----|--------|
| `XxxCreateDto` | `@Data @Builder` |
| `XxxUpdateDto` | `@Data @Builder` |
| `XxxPatchDto` | `@Data @Builder @ToString(onlyExplicitlyIncluded = true)` |
| `XxxDto` (response) | `@Data @Builder` |
| `XxxSummaryDto` | `@Data @Builder` |
| `XxxFullDto` | `@Data @Builder` |
| `XxxListItemDto` | `@Data @Builder` |
| `XxxLookupDto` | `@Data @Builder` |
| `XxxSearchParams` | `@Data` |

`XxxSummaryDto` and `XxxFullDto` are optional — add only when the endpoint exposes `application/vnd.api.{entity}.summary+json` or `.full+json` variants per the `rest-api-design` content-negotiation contract. Wire them through the controller's `produces` and a separate mapper method; the controller chooses which DTO to return based on the `Accept` header (resolved by Spring MVC).

`@ToString(onlyExplicitlyIncluded = true)` on Patch DTOs controls PII in logs — see `references/logging.md`.

## Create / Update DTO

```java
@Data
@Builder
@Schema(name = "CustomerCreate")
public class CustomerCreateDto {

    @NotBlank @Size(max = 50)
    @Schema(description = "First name", example = "John")
    private String firstName;

    @NotBlank @Size(max = 50)
    @Schema(description = "Last name", example = "Doe")
    private String lastName;

    @Email @Size(max = 255)
    @Schema(description = "Email address", example = "john@example.com", nullable = true)
    private String email;

    @NotNull
    @Schema(description = "Account status", example = "ACTIVE")
    private AccountStatus status;

    @NotNull
    @Schema(description = "Country ID")
    private UUID countryId;

    @NotNull
    @Schema(description = "Payment method IDs (may be empty)")
    private List<UUID> paymentMethods;
}
```

- `email` has no `@NotBlank` — it is nullable per the `rest-api-design` payload contract. `@Email` and `@Size` do not fire on null values, so the annotation chain covers both "null" and "valid non-null".
- `paymentMethods` is `@NotNull` but may be an empty list — clients must send `[]` explicitly rather than omit the field (the contract rejects missing required fields).
- `XxxUpdateDto` has the same fields and validators; the semantic difference is "full replacement" — clients must send every field.

For Patch DTOs, see `references/patch.md`.

## Response DTOs — FK representation

The default `CustomerDto` carries associations as identifiers; `CustomerFullDto` expands them per the `.full+json` contract.

```java
@Data @Builder @Schema(name = "Customer")
public class CustomerDto {
    private UUID id;
    private String firstName;
    private String lastName;
    private String email;                // nullable
    private AccountStatus status;
    private UUID countryId;
    private List<UUID> paymentMethods;
    private Instant createdAt;
    private Instant updatedAt;
}

@Data @Builder @Schema(name = "CustomerFull")
public class CustomerFullDto {
    private UUID id;
    private String firstName;
    private String lastName;
    private String email;
    private AccountStatus status;
    private CountryLookupDto country;               // scalar FK expanded — name drops "Id" suffix
    private List<PaymentMethodLookupDto> paymentMethods;  // collection FK expanded — same field name
    private Instant createdAt;
    private Instant updatedAt;
}
```

The scalar-vs-collection naming asymmetry is by design — see `rest-api-design/references/dto-conventions.md`.

## Audit fields are read-only on the wire

Per the `rest-api-design` payload contract, `createdAt`/`updatedAt` are set by the server and never accepted on input. Enforce this by **omitting** them from `XxxCreateDto`, `XxxUpdateDto`, `XxxPatchDto` — declare them only on response DTOs. Mapper methods for write operations keep `@Mapping(target = "createdAt"/"updatedAt", ignore = true)` as a defence-in-depth even with `@EnableJpaAuditing` in place.

## Money fields

Amounts are `BigDecimal` in Java and **serialized as string** on the wire (per `rest-api-design` payload contract — avoids float precision loss). Always paired with a sibling `currencyCode` field.

```java
public class InvoiceDto {
    @JsonFormat(shape = JsonFormat.Shape.STRING)
    @Schema(description = "Amount", example = "1999.99")
    private BigDecimal amount;

    @Schema(description = "ISO 4217 currency code", example = "USD")
    private String currencyCode;
}
```

Use `@JsonFormat(shape = STRING)` per field (not a global `ObjectMapper` setting) — keeps the wire contract explicit at the DTO definition and does not force unrelated numeric fields to serialize as strings.

## @Schema conventions

- `@Schema(name = "Customer")` on the class — strips `Dto` suffix in Swagger UI.
- `@Schema(description = ..., example = ...)` on fields — improves API docs.
- Apply to all DTO types.

## MapStruct mapper

```java
@Mapper(componentModel = "spring", uses = { CountryMapper.class, PaymentMethodMapper.class })
public interface CustomerMapper {

    // Default response — FK as identifiers
    @Mapping(target = "countryId", source = "country.id")
    @Mapping(target = "paymentMethods", source = "paymentMethods", qualifiedByName = "paymentMethodIds")
    CustomerDto toDto(CustomerEntity entity);

    // Full response — FK expanded via sub-mappers (resolved through `uses`)
    @Mapping(target = "country", source = "country")
    @Mapping(target = "paymentMethods", source = "paymentMethods")
    CustomerFullDto toFullDto(CustomerEntity entity);

    CustomerSummaryDto toSummaryDto(CustomerEntity entity);

    CustomerListItemDto toListItemDto(CustomerEntity entity);

    // Lookup — derived display name
    @Mapping(target = "name",
             expression = "java(entity.getFirstName() + \" \" + entity.getLastName())")
    CustomerLookupDto toLookupDto(CustomerEntity entity);

    // Write — associations resolved by the service, not the mapper
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "country", ignore = true)
    @Mapping(target = "paymentMethods", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    CustomerEntity toEntity(CustomerCreateDto dto);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "country", ignore = true)
    @Mapping(target = "paymentMethods", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void updateEntityFromDto(CustomerUpdateDto dto, @MappingTarget CustomerEntity entity);

    @Named("paymentMethodIds")
    default List<UUID> toPaymentMethodIds(Set<PaymentMethodEntity> entities) {
        return entities.stream().map(PaymentMethodEntity::getId).toList();
    }
}
```

- `componentModel = "spring"` — inject via constructor.
- Do NOT set `nullValuePropertyMappingStrategy` at `@Mapper` level — use `@BeanMapping` only on patch methods (see `references/patch.md`).
- Write methods (`toEntity`, `updateEntityFromDto`, `patchEntityFromDto`) ignore associations — the service resolves FK UUIDs to entity references via `getReferenceById` (see `references/jpa.md`).
- `uses = { CountryMapper.class, PaymentMethodMapper.class }` wires sub-mappers for the full variant; no inline expressions needed.

## Service — FK resolution before save

```java
@Transactional
public CustomerDto create(UUID userId, CustomerCreateDto dto) {
    CustomerEntity entity = customerMapper.toEntity(dto);
    entity.setId(UUID.randomUUID());
    entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
    entity.setPaymentMethods(dto.getPaymentMethods().stream()
        .map(paymentMethodRepository::getReferenceById)
        .collect(Collectors.toSet()));
    customerRepository.save(entity);
    return customerMapper.toDto(entity);
}
```

`getReferenceById` produces a proxy — no SELECT. Invalid FK triggers `DataIntegrityViolationException` at flush → `409 CONFLICT` via `GlobalExceptionHandler`. If a cleaner `400 BAD_REQUEST` is required, validate with `existsById` before save and throw `BadRequestException`.

## Controller: @Valid

Always use `@Valid` on request bodies and query params:

```java
@PostMapping
public ResponseEntity<CustomerDto> create(@Valid @RequestBody CustomerCreateDto dto) {
    UUID userId = getCurrentUserId(authentication);
    CustomerDto created = customerService.create(userId, dto);
    return ResponseEntity.status(HttpStatus.CREATED)
        .header("Location", "/api/v1/customers/" + created.getId())
        .body(created);
}

@GetMapping
public ResponseEntity<PagedResponse<CustomerListItemDto>> list(
        @Valid @ModelAttribute CustomerSearchParams params) { ... }
```
