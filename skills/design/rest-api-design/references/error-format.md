# Error Response Format

Standard error shape for all REST API error responses.

## Error object

```json
{
  "code": "ERROR_CODE",
  "message": "Human-readable description",
  "details": { ... }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `code` | Always | Machine-readable error code |
| `message` | Always | Human-readable description |
| `details` | Validation only | Field-level errors; omitted (not `null`) for all other errors |

## Error codes

| Code | HTTP | When |
|------|------|------|
| `VALIDATION_ERROR` | 400 | Input/field validation failures |
| `BAD_REQUEST` | 400 | Invalid input (type mismatch, bad UUID, etc.) |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Business conflict or DB constraint violation |
| `PRECONDITION_FAILED` | 412 | `If-Match` ETag did not match current resource version |
| `PRECONDITION_REQUIRED` | 428 | `If-Match` header missing when required |
| `FORBIDDEN` | 403 | Access denied |
| `UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `TOO_MANY_REQUESTS` | 429 | Rate limit exceeded |
| `ACCOUNT_TEMPORARILY_LOCKED` | 429 | Account locked after too many failed attempts |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## Validation error (400)

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "details": {
    "firstName": "First name is required",
    "lastName": "Last name must be at most 50 characters",
    "email": "Invalid email format"
  }
}
```

- Field-level errors keyed by field name
- Class-level errors (e.g. "at least one field required") keyed by the request body schema name in camelCase
- One error per field — first encountered wins

Class-level example — empty PATCH body:

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "details": {
    "customerPatch": "At least one field required"
  }
}
```

## Validation rule catalog

Concrete rules that produce `VALIDATION_ERROR`:

| Rule | Applies to | Error message |
|------|------------|---------------|
| Required field missing | POST, PUT | "Field is required" |
| String exceeds max length | POST, PUT, PATCH | "Max N characters" |
| Invalid email format | POST, PUT, PATCH | "Invalid email" |
| Empty PATCH body or all-null fields | PATCH | "At least one field required" |
| Blank string in PATCH | PATCH | "Must not be blank" |

## Non-validation errors

`details` is omitted entirely:

```json
{ "code": "NOT_FOUND", "message": "Customer not found with id: 550e8400-..." }
{ "code": "CONFLICT", "message": "User with this email already exists" }
{ "code": "BAD_REQUEST", "message": "Invalid parameter: id" }
{ "code": "UNAUTHORIZED", "message": "Authentication required" }
{ "code": "INTERNAL_ERROR", "message": "Internal server error" }
```

## Scenario mapping

| Scenario | HTTP | Code |
|----------|------|------|
| Field validation failure | 400 | `VALIDATION_ERROR` |
| Invalid path variable (bad UUID, etc.) | 400 | `BAD_REQUEST` |
| Business input error (FK not found) | 400 | `BAD_REQUEST` |
| Resource not found | 404 | `NOT_FOUND` |
| Access denied | 403 | `FORBIDDEN` |
| Rate limit exceeded | 429 | `TOO_MANY_REQUESTS` |
| Account temporarily locked | 429 | `ACCOUNT_TEMPORARILY_LOCKED` |
| Business conflict ("already exists") | 409 | `CONFLICT` |
| DB constraint violation | 409 | `CONFLICT` |
| ETag mismatch on concurrent update | 412 | `PRECONDITION_FAILED` |
| `If-Match` missing when required | 428 | `PRECONDITION_REQUIRED` |
| Unexpected server error | 500 | `INTERNAL_ERROR` |

Never expose stack traces or internal details. Never let generic programming errors map to 4xx — they become 500.
