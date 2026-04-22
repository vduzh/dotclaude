---
name: rest-api-design
description: >
  Design REST API contracts for a Spring Boot backend — URI conventions, HTTP
  verbs, status codes, content negotiation, DTO naming, pagination, error
  responses, and security patterns. Use this skill when designing or reviewing
  API endpoints, request/response shapes, error formats, or security behavior.
---

# REST API Design Conventions

Apply these conventions when designing or implementing REST API endpoints.

## Non-negotiable rules

1. All endpoints under `/api/v1/...` — URI versioning.
2. List view is the default representation — serves both `application/json` and the vendor type; specialized views (lookup, detail) require an explicit `Accept` header.
3. DELETE is idempotent — return `204 No Content` whether the resource existed or not.
4. Collection endpoints always return `[]` with pagination on empty — never `404`.
5. All error responses use `{code, message, details?}` — see `references/error-format.md`.

## HTTP methods

| Method | Purpose |
|--------|---------|
| GET | Read resource(s) |
| POST | Create resource |
| PUT | Full update (all fields required) |
| PATCH | Partial update (only provided fields) |
| DELETE | Delete resource |

## Status codes

| Code | When |
|------|------|
| 200 OK | Successful read or update |
| 201 Created | Resource created (POST) |
| 204 No Content | Successful delete |
| 400 Bad Request | Validation error, invalid input |
| 401 Unauthorized | Missing or invalid authentication |
| 403 Forbidden | Authenticated but insufficient permissions |
| 404 Not Found | Resource not found |
| 406 Not Acceptable | Unsupported Accept header |
| 409 Conflict | Business conflict, duplicate, constraint violation |
| 429 Too Many Requests | Rate limit exceeded |

## Content negotiation

Same URL, different representations via `Accept` header. Vendor media type convention: `application/vnd.api.{entity}.{view}+json`

| View | Accept header | Response | Use case |
|------|--------------|----------|----------|
| List | `application/vnd.api.profile.list+json` | `PagedResponse<ProfileListItem>` | Tables with pagination |
| Lookup | `application/vnd.api.profile.lookup+json` | `ProfileLookup[]` | Dropdowns/selects |
| Default | `application/json` | Same as list view | Swagger, generic clients |

- List view is the default — also served for `application/json`
- Lookup and other specialized views require explicit vendor `Accept` header
- Unsupported `Accept` header → `406 Not Acceptable`

## Query vs path parameters

- **Query params**: filtering/searching collections (`?email=...`, `?status=active`)
- **Path with prefix**: alternative unique identifier (`/by-email/{email}`, `/by-username/{username}`)
- Avoid `/customers/email/{email}` — looks like a nested resource

## GET

```
GET /api/v1/profiles/550e8400-...
→ 200 OK  |  404 Not Found

GET /api/v1/profiles?page=1&limit=20&search=john&sort=-createdAt
→ 200 OK  (always, even if empty — return [] with pagination)
```

## POST

```
POST /api/v1/profiles
→ 201 Created  (with created resource including generated id)
```

## PUT — full replacement

All fields required. Null fields overwrite existing values.

```
PUT /api/v1/profiles/550e8400-...
→ 200 OK  (with updated resource)
```

## PATCH — partial update

Only provided (non-null) fields are updated. Absent/null fields are ignored.

```
PATCH /api/v1/profiles/550e8400-...
{ "lastName": "Smith" }
→ 200 OK  (with full updated resource)
```

Validation rules:
- Empty body `{}` or all-null fields → `400 Bad Request`
- Blank string `""` → `400 Bad Request` (field is either absent or a valid non-blank value)
- `null` means "don't touch this field", not "set to null"

## DELETE — idempotent

```
DELETE /api/v1/profiles/550e8400-...
→ 204 No Content  (whether resource existed or not)
```

With business rules: if resource is found but cannot be deleted (e.g., in use), return `409 Conflict`. Business checks only run if resource is found.

## Optional references

Load the reference file for each area the current task touches:

- `references/dto-conventions.md` — DTO naming (noun-first), DTO types per operation, JSON examples.
  Load when designing request/response shapes or DTO naming.
- `references/pagination-sorting.md` — query parameters, JSON:API sort format, `PagedResponse` wrapper, stable sorting.
  Load when designing list endpoints.
- `references/error-format.md` — error codes, validation error shape, scenario-to-HTTP mapping.
  Load when designing error responses.
- `references/lookup-endpoints.md` — strategy by data volume, `X-Total-Count`, frontend UX pattern.
  Load when designing dropdown/autocomplete endpoints.
- `references/api-security.md` — stateless auth, cookie-based tokens, rate limiting, brute-force protection.
  Load when designing authentication or security behavior.
