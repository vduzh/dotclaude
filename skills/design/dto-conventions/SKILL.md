---
name: dto-conventions
description: DTO naming and structure conventions — noun-first naming, separate DTOs per operation, validation, OpenAPI schemas, PII control
---

# DTO Conventions

Apply these conventions when creating or modifying DTOs.

## Noun-First Naming

Name DTOs as `{Entity}{Operation}` — noun first, NOT verb first:

```
✅ Customer, CustomerCreate, CustomerUpdate, CustomerListItem, CustomerLookup
❌ CreateCustomer, UpdateCustomer
```

## Separate DTOs Per Operation

Each entity gets its own set of DTOs:

| DTO | Purpose | Validation |
|-----|---------|------------|
| `XxxCreateDto` | POST body | All required fields validated |
| `XxxUpdateDto` | PUT body | All fields required (full replacement) |
| `XxxPatchDto` | PATCH body | All fields nullable, at least one required |
| `XxxDto` | Response (single resource) | No validation needed |
| `XxxListItemDto` | Response (list/table view) | No validation needed |
| `XxxLookupDto` | Response (dropdown/select) | No validation needed |
| `XxxSearchParams` | Query parameters for list endpoints | Pagination/sort validation |

## Validation

All input DTOs must include Bean Validation annotations:

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
}
```

## OpenAPI Documentation

- Use `@Schema(name = "Customer")` on DTO classes for clean API documentation names (strips the `Dto` suffix)
- Use `@Schema(description = ..., example = ...)` on fields

## PII Control in Logs

Input/mutable DTOs (`Create`, `Update`, `Patch`) use `@ToString` whitelist to control PII in logs:

```java
@Data
@Builder
@ToString(onlyExplicitlyIncluded = true)  // whitelist approach
public class CustomerCreateDto {
    @ToString.Include
    @NotBlank
    private String name;       // ✅ safe — included in logs

    @NotBlank @Email
    private String email;      // 🔒 PII — excluded from logs
}
```

Output/display DTOs (`Dto`, `ListItem`, `Lookup`) contain only public data and use default `toString`.

## Lombok Annotations

```java
@Data @Builder              // for DTOs
@Getter @Setter             // for entities (NOT @Data — avoids equals/hashCode issues with lazy loading)
@NoArgsConstructor
@AllArgsConstructor
```
