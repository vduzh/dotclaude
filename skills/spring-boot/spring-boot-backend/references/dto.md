# DTO Implementation

Spring Boot DTO conventions — class structure, Lombok, Bean Validation, `@Schema`, MapStruct mapper.

## Lombok annotations per DTO type

| DTO | Lombok |
|-----|--------|
| `XxxCreateDto` | `@Data @Builder` |
| `XxxUpdateDto` | `@Data @Builder` |
| `XxxPatchDto` | `@Data @Builder @ToString(onlyExplicitlyIncluded = true)` |
| `XxxDto` (response) | `@Data @Builder` |
| `XxxListItemDto` | `@Data @Builder` |
| `XxxLookupDto` | `@Data @Builder` |
| `XxxSearchParams` | `@Data` |

`@ToString(onlyExplicitlyIncluded = true)` on Patch DTOs controls PII in logs — see `references/logging.md`.

## Create / Update DTO

```java
@Data
@Builder
@Schema(name = "CustomerCreate")
public class CustomerCreateDto {

    @NotBlank @Size(max = 255)
    @Schema(description = "Customer name", example = "John Doe")
    private String name;

    @NotBlank @Email @Size(max = 255)
    @Schema(description = "Email address", example = "john@example.com")
    private String email;

    @NotNull
    @Schema(description = "Status")
    private AccountStatus status;
}
```

For Patch DTOs, see `references/patch.md`.

## @Schema conventions

- `@Schema(name = "Customer")` on the class — strips `Dto` suffix in Swagger UI
- `@Schema(description = ..., example = ...)` on fields — improves API docs
- Apply to all DTO types

## MapStruct mapper

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
- Do NOT set `nullValuePropertyMappingStrategy` at `@Mapper` level — use `@BeanMapping` only on patch methods (see `references/patch.md`)
- Add `patchEntityFromDto` with `@BeanMapping(nullValuePropertyMappingStrategy = IGNORE)` when PATCH is needed

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
