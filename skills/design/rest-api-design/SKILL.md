---
name: rest-api-design
description: REST API design conventions — URI versioning, HTTP methods, status codes, content negotiation, query/path params, update/delete/patch semantics
---

# REST API Design Conventions

Apply these conventions when designing or implementing REST API endpoints.

## URI Versioning

```
/api/v1/...
/api/v2/...
```

## HTTP Methods

| Method | Purpose |
|--------|---------|
| GET | Read resource(s) |
| POST | Create resource |
| PUT | Full update (all fields required) |
| PATCH | Partial update (only provided fields) |
| DELETE | Delete resource |

## Status Codes

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

## Content Negotiation

The same URL can return **different representations** of a resource depending on the `Accept` header. This avoids creating separate URLs for each view.

**Vendor media type convention:** `application/vnd.api.{entity}.{view}+json`

| View | Accept Header | Response | Use Case |
|------|--------------|----------|----------|
| List | `application/vnd.api.profile.list+json` | `PagedResponse<ProfileListItem>` | Tables with pagination |
| Lookup | `application/vnd.api.profile.lookup+json` | `ProfileLookup[]` | Dropdowns/selects |
| Detail | `application/vnd.api.profile.detail+json` | `Profile` (extended) | Detail view with related data |
| Default | `application/json` | Same as list view | Swagger, generic clients |

```
# Same URL, different representations:
GET /api/v1/profiles
Accept: application/vnd.api.profile.list+json    → paginated list with subset of fields
Accept: application/vnd.api.profile.lookup+json   → flat array with id + name
Accept: application/json                           → default (same as list)
```

**Rules:**
- **List view is the default** — serves both `application/json` and the vendor type
- **Specialized views** (lookup, detail, etc.) require an explicit vendor `Accept` header
- Unsupported `Accept` header → `406 Not Acceptable`
- The framework routes requests based on `Accept` header automatically — no manual parsing

## Query vs Path Parameters

- **Query params**: Filtering/searching collections (`?email=...`, `?status=active`)
- **Path with prefix**: Alternative unique identifier lookup (`/by-email/{email}`, `/by-username/{username}`)
- Avoid confusing patterns like `/customers/email/{email}` (looks like nested resource)

## GET — Read

```
# Single resource
GET /api/v1/profiles/550e8400-...
→ 200 OK  (resource found)
→ 404 Not Found  (resource not found)

# Collection (with pagination, filtering, sorting)
GET /api/v1/profiles?page=1&limit=20&search=john&sort=-createdAt
→ 200 OK  (always, even if empty — return [] with pagination)
```

## POST — Create

```
POST /api/v1/profiles
Content-Type: application/json

{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com"
}
```

Response: `201 Created` with created resource (including generated `id`).

## PUT — Full Replacement

All fields required. Null fields overwrite existing values.

```
PUT /api/v1/profiles/550e8400-...
Content-Type: application/json

{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com"
}
```

Response: `200 OK` with updated resource.

## PATCH — Partial Update

Only provided (non-null) fields are updated. Absent/null fields are **ignored**.

```
PATCH /api/v1/profiles/550e8400-...
Content-Type: application/json

{
  "lastName": "Smith"
}
```

Response: `200 OK` with full updated resource.

**Validation rules:**
- Empty body `{}` or all-null fields → `400 Bad Request` (at least one field required)
- Blank string `""` or `"   "` → `400 Bad Request` (field is either absent or a valid non-blank value)
- `null` means "don't touch this field", not "set to null"

## DELETE — Idempotent

DELETE must be **idempotent** per RFC 7231:
- If resource exists → delete it, return **204 No Content**
- If resource does NOT exist → just return **204 No Content** (no 404 error)

```
DELETE /api/v1/profiles/550e8400-...

→ 204 No Content  (whether resource existed or not)
```

**With business rules:** If the resource is found and cannot be deleted (e.g., in use by other resources), return `409 Conflict`. Business checks are only performed if the resource is found — if not found, return 204 silently.
