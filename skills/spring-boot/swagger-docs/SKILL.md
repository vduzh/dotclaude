---
name: swagger-docs
description: Swagger/OpenAPI documentation conventions — @Operation usage, when to add description, @ApiResponse only for non-standard codes
---

# Swagger Documentation Conventions

Apply these conventions when documenting REST API endpoints with Springdoc OpenAPI.

## @Operation — Summary is Required

Every endpoint must have `@Operation(summary = "...")`:

```java
@Operation(summary = "Get profiles as list")
@GetMapping(produces = {"application/json", "application/vnd.api.profile.list+json"})
public ResponseEntity<PagedResponse<ProfileListItemDto>> getProfilesAsList(...) { ... }
```

## When to Add Description

Add `description` **only** when it provides real value:

| Add description | Don't add description |
|----------------|----------------------|
| Business rules: "Full replacement — all fields required" | Simple CRUD (GET by ID, Create, Delete) |
| Access restrictions: "for the authenticated user" | Standard list/lookup endpoints |
| Filtering specifics: "Email filter not supported" | Obvious operations where summary is enough |
| Special behavior: "Partial update — at least one field required" | |

## Examples

```java
// ✅ Good — no description needed
@Operation(summary = "Get currencies as lookup")

// ✅ Good — description adds value
@Operation(summary = "Update profile",
           description = "Full replacement (all fields required)")

// ✅ Good — business context
@Operation(summary = "Patch profile",
           description = "Partial update — at least one field required")

// ❌ Bad — description just repeats summary
@Operation(summary = "Get profile by ID",
           description = "Retrieve a single profile by its unique identifier")

// ❌ Bad — redundant synonym
@Operation(summary = "Delete profile",
           description = "Remove a profile from the system")
```

## @ApiResponse — Only for Non-Standard Codes

Let Spring/Swagger infer standard responses (200 OK) from return types. Reserve `@ApiResponse` for non-standard error codes only:

```java
// ✅ Good — only document non-obvious responses
@ApiResponse(responseCode = "409", description = "User with this email already exists")

// ❌ Bad — don't document obvious 200 OK
@ApiResponse(responseCode = "200", description = "Successfully retrieved profile")
```

## @Schema on DTOs

Use `@Schema(name = "Profile")` on DTO classes for clean API names (strips the `Dto` suffix):

```java
@Schema(name = "ProfileCreate")
public class ProfileCreateDto { ... }
```
