---
name: dto-implementation
description: Spring Boot DTO implementation — Lombok annotations, Bean Validation, OpenAPI @Schema, MapStruct mapper, controller @Valid
---

# DTO Implementation (Spring Boot)

Spring Boot implementation of the DTO conventions (see `dto-conventions` skill for API contracts and naming rules).

## DTO Class Structure

```java
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(name = "CustomerCreate")
public class CustomerCreateDto {

    @NotBlank @Size(max = 255)
    @Schema(description = "Customer name", example = "John Doe")
    private String name;

    @NotBlank @Email @Size(max = 255)
    @Schema(description = "Email address", example = "john@example.com")
    private String email;

    @Size(max = 20)
    @Schema(description = "Phone number", example = "+1234567890")
    private String phone;
}
```

## Lombok Annotations per DTO Type

| DTO | Lombok | Why |
|-----|--------|-----|
| `XxxCreateDto` | `@Data @Builder` | Mutable input, needs builder for tests |
| `XxxUpdateDto` | `@Data @Builder` | Same as Create |
| `XxxPatchDto` | `@Data @Builder @ToString(onlyExplicitlyIncluded = true)` | + PII control (see `logging-conventions`) |
| `XxxDto` (response) | `@Data @Builder` | Output, all fields are public |
| `XxxListItemDto` | `@Data @Builder` | Output, subset of fields |
| `XxxLookupDto` | `@Data @Builder` | Output, minimal fields |
| `XxxSearchParams` | `@Data` | Query params (see `pagination-filtering` for full example) |

## Bean Validation

### Create / Update DTOs

All required fields validated:

```java
@Data
@Builder
@Schema(name = "CustomerUpdate")
public class CustomerUpdateDto {

    @NotBlank @Size(max = 255)
    @Schema(description = "Customer name")
    private String name;

    @NotBlank @Email @Size(max = 255)
    @Schema(description = "Email address")
    private String email;

    @NotNull
    @Schema(description = "Status")
    private AccountStatus status;
}
```

### Patch DTOs

See `patch-implementation` skill for `Patchable`, `@NullOrNotBlank`, `@NotEmptyPatch`.

## OpenAPI @Schema

- `@Schema(name = "Customer")` on class — strips `Dto` suffix in Swagger UI
- `@Schema(description = ..., example = ...)` on fields — improves API docs

```java
@Schema(name = "Customer")
public class CustomerDto {
    @Schema(description = "Unique identifier", example = "550e8400-e29b-41d4-a716-446655440001")
    private UUID id;

    @Schema(description = "Customer name", example = "John Doe")
    private String name;
}
```

## MapStruct Mapper

```java
@Mapper(componentModel = "spring")
public interface CustomerMapper {

    CustomerDto toDto(CustomerEntity entity);
    CustomerListItemDto toListItemDto(CustomerEntity entity);
    CustomerLookupDto toLookupDto(CustomerEntity entity);
    CustomerEntity toEntity(CustomerCreateDto dto);
    void updateEntityFromDto(CustomerUpdateDto dto, @MappingTarget CustomerEntity entity);
}
```

- Set `componentModel = "spring"` — inject via constructor
- Do NOT set `nullValuePropertyMappingStrategy` at `@Mapper` level (see `patch-implementation` skill)

## Controller: @Valid

Always use `@Valid` on request bodies and query params:

```java
@PostMapping
@ResponseStatus(HttpStatus.CREATED)
public CustomerDto create(@Valid @RequestBody CustomerCreateDto dto) { ... }

@GetMapping
public ResponseEntity<PagedResponse<CustomerListItemDto>> list(
        @Valid @ModelAttribute CustomerSearchParams params) { ... }
```
