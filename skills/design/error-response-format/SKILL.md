---
name: error-response-format
description: Standardized error response format — error object with code/message/details, field-level validation errors, consistent structure across all endpoints
---

# Error Response Format

Apply this format for all error responses in REST APIs.

## Error Object Structure

```json
{
  "code": "ERROR_CODE",
  "message": "Human-readable description",
  "details": { ... }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | string | Always | Machine-readable error code |
| `message` | string | Always | Human-readable description |
| `details` | object | Validation only | Field-level errors (omitted when `null`) |

## Error Codes

| Code | HTTP Status | When |
|------|-------------|------|
| `VALIDATION_ERROR` | 400 | Input/field validation failures |
| `BAD_REQUEST` | 400 | Invalid input (type mismatch, bad UUID, etc.) |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Business conflict or DB constraint violation |
| `FORBIDDEN` | 403 | Access denied |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## Validation Error (400)

Includes `details` — a map of field-level errors:

```json
// POST /api/v1/profiles  →  400 Bad Request
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

Rules:
- Field-level errors are keyed by **field name**
- Class-level errors (e.g., "at least one field required") are keyed by **object name**
- **One error per field** (first encountered wins) — avoids duplicate messages

## Non-Validation Errors

`details` is omitted (not `null`, not `{}` — simply absent from the response):

```json
// GET /api/v1/profiles/bad-id  →  404 Not Found
{
  "code": "NOT_FOUND",
  "message": "Profile not found with id: 550e8400-..."
}
```

```json
// POST /api/v1/profiles  →  409 Conflict
{
  "code": "CONFLICT",
  "message": "User with this email already exists"
}
```

```json
// GET /api/v1/profiles/not-a-uuid  →  400 Bad Request
{
  "code": "BAD_REQUEST",
  "message": "Invalid parameter: id"
}
```

```json
// Any endpoint  →  500 Internal Server Error
{
  "code": "INTERNAL_ERROR",
  "message": "Internal server error"
}
```

## Error Scenario-to-HTTP Mapping

| Scenario | HTTP | Code |
|----------|------|------|
| Field validation failure | 400 | `VALIDATION_ERROR` |
| Invalid path variable (bad UUID, etc.) | 400 | `BAD_REQUEST` |
| Business input error (FK not found, etc.) | 400 | `BAD_REQUEST` |
| Resource not found | 404 | `NOT_FOUND` |
| Access denied | 403 | `FORBIDDEN` |
| Business conflict ("already exists") | 409 | `CONFLICT` |
| DB constraint violation | 409 | `CONFLICT` |
| Unexpected server error | 500 | `INTERNAL_ERROR` |

## Design Principles

- Use **dedicated error types** for business semantics (not found, conflict, bad request). Never let generic programming errors (null pointer, illegal state) map to 4xx — they should become 500.
- **Never expose stack traces** or internal details in error responses.
- **Log server errors** (500) with full stack trace. Log client errors (4xx) at debug level only.
