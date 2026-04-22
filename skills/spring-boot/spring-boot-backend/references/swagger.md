# Swagger / OpenAPI Documentation Conventions

`@Operation` usage, when to add description, `@ApiResponse` only for non-standard codes.

## @Operation — summary is required

Every endpoint must have `@Operation(summary = "...")`:

```java
@Operation(summary = "Get profiles as list")
@GetMapping(produces = {"application/json", "application/vnd.api.profile.list+json"})
public ResponseEntity<PagedResponse<ProfileListItemDto>> getProfilesAsList(...) { ... }
```

## When to add description

| Add description | Skip description |
|----------------|----------------------|
| Business rules: "Full replacement — all fields required" | Simple CRUD (GET by ID, Create, Delete) |
| Access restrictions: "for the authenticated user only" | Standard list / lookup endpoints |
| Filtering specifics: "Email filter not supported in this view" | Obvious operations where summary is enough |
| Special behavior: "Partial update — at least one field required" | |

```java
// ✅ Good — no description needed
@Operation(summary = "Get currencies as lookup")

// ✅ Good — description adds value
@Operation(summary = "Update profile",
           description = "Full replacement (all fields required)")

// ❌ Bad — description repeats summary
@Operation(summary = "Get profile by ID",
           description = "Retrieve a single profile by its unique identifier")
```

## @ApiResponse — only for non-standard codes

Let Spring/Swagger infer standard 200 OK from return types. Use `@ApiResponse` only for non-obvious responses:

```java
// ✅ Good — documents a non-obvious conflict case
@ApiResponse(responseCode = "409", description = "User with this email already exists")

// ❌ Bad — don't document obvious 200 OK
@ApiResponse(responseCode = "200", description = "Successfully retrieved profile")
```

## @Schema on DTOs

See `references/dto.md` for `@Schema` usage on DTO classes and fields.
