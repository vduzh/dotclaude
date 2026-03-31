---
name: patch-operations
description: PATCH endpoint design — partial update semantics, null vs absent fields, empty patch rejection, validation rules
---

# PATCH Operations

Apply these patterns when designing PATCH (partial update) endpoints.

## Semantics

- Only provided (non-null) fields are updated
- Absent/null fields are **ignored** (not set to null)
- Empty body `{}` → `400 Bad Request` (at least one field must be provided)
- Blank string `""` or `"   "` → `400 Bad Request` (field is either absent or a valid value)

## Request Contract

```
PATCH /api/v1/profiles/550e8400-...
Content-Type: application/json

{
  "lastName": "Smith"
}
```

Response: `200 OK` with full updated resource.

## Validation Rules

### At least one field required

An empty patch body must be rejected at the validation layer:

```json
// ❌ 400 Bad Request
{}

// ❌ 400 Bad Request
{ "firstName": null, "lastName": null }

// ✅ 200 OK
{ "firstName": "John" }
```

Error response:
```json
{
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "details": {
    "profilePatch": "At least one field must be provided"
  }
}
```

### Null-or-not-blank rule

For string fields in PATCH, the value is either:
- **`null` / absent** → field is not updated (valid)
- **Non-blank string** → field is updated (valid)
- **Blank / whitespace** → rejected with `400` (invalid)

```json
// ✅ Valid — field not updated
{ "firstName": null }

// ✅ Valid — field updated
{ "firstName": "John" }

// ❌ Invalid — blank string
{ "firstName": "" }
{ "firstName": "   " }
```

## Clearing Fields

By default, `null` means "don't touch this field", not "set to null". To "clear" a field via PATCH, a separate convention is needed. If clearing fields is required, document this in the API contract.
