---
name: rest-api-design
description: >
  Design stack-agnostic REST API contracts — the HTTP-observable behavior
  that both backend and frontend implementations rely on. Use this skill
  when designing new endpoints, reviewing existing API contracts,
  establishing conventions for a new project, or deciding how a resource
  should be exposed on the wire.
---

# REST API Design Conventions

Apply these conventions when designing REST API endpoints.

## Scope

This skill defines **contract-level** REST API conventions — the HTTP-observable behavior of endpoints: URIs, verbs, status codes, headers, content negotiation, request/response shapes, error format, pagination, and authentication/rate-limiting semantics. Language- and framework-agnostic.

Implementation details (framework wiring, libraries, annotations, code organization) are deliberately out of scope.

Out of specification (define when a concrete case arises): bulk operations, long-running async (`202 Accepted` + polling), multipart file upload, deprecation / sunset policy, `ETag`/`If-Match` optimistic concurrency (introduce when multi-editor conflicts become a concrete business requirement).

## Non-negotiable rules

1. All endpoints under `/api/v1/...` — URI versioning.
2. Each endpoint has one default representation — for collections, a paged list of list-items; for single resources, all fields with associations carried as identifiers (scalar FK: `xxxId`; collection FK: array of UUIDs). `application/json` returns the default; alternative representations require an explicit vendor media type in `Accept`.
3. Collection endpoints always return `[]` with pagination on empty — never `404`.
4. DELETE is idempotent — return `204 No Content` whether the resource existed or not.
5. All error responses use `{code, message, details?}`.

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
| 410 Gone | Idempotency retry when the created resource no longer exists |
| 415 Unsupported Media Type | Request `Content-Type` not supported |
| 429 Too Many Requests | Rate limit exceeded |
| 500 Internal Server Error | Unexpected server error |

## Content negotiation

Same URL, alternative representations selected via `Accept` header. Vendor media type convention: `application/vnd.api.{entity}.{view}+json`.

Vendor media types are **optional** — introduce them only when an endpoint offers more than one representation. With a single representation, `application/json` is sufficient.

### Collection endpoint — `GET /customers`

| Accept header | Response | Use case |
|---------------|----------|----------|
| `application/json` *(default)* | Paged list of list-items | Tables, generic clients |
| `application/vnd.api.customer.lookup+json` | Flat array of lookup items | Dropdowns, autocomplete |

### Single-resource endpoint — `GET /customers/{id}`

| Accept header | Response | Use case |
|---------------|----------|----------|
| `application/json` *(default)* | All fields; associations as identifiers | Normal read |
| `application/vnd.api.customer.summary+json` | Reduced field set | Lightweight displays, polling |
| `application/vnd.api.customer.full+json` | Default + expanded associations | Detail screens needing related entities |

Unsupported `Accept` header → `406 Not Acceptable`.

Request bodies (POST / PUT / PATCH) require `Content-Type: application/json`. Unsupported `Content-Type` → `415 Unsupported Media Type`.

## URI conventions

### Naming

- Resource collections are **plural nouns**: `/customers`, `/orders` — never `/customer`, `/getCustomers`.
- Multi-word paths use **kebab-case**: `/payment-methods`, `/user-sessions` — never camelCase or snake_case.
- URIs contain **no verbs** — use HTTP methods instead. `POST /customers` creates; no `/customers/create`.

### Hierarchy

- **Nested** when the child belongs to exactly one parent and has no independent identity: `/customers/{id}/addresses`.
- **Flat with query filter** when the entity has independent identity and can be related to many things: `/orders?customerId={id}`.

### Lookup by alternative identifier

Use the `by-{field}` prefix for non-id lookups:

```
GET /api/v1/customers/by-email/{email}
GET /api/v1/customers/by-username/{username}
```

Avoid `/customers/email/{email}` — reads as a nested resource, not a lookup.

If the identifier may contain URL-reserved characters (`+`, `@`, `/` in emails; `#` in tags; etc.), use a query parameter instead to avoid path-decoding ambiguity across frameworks:

```
GET /api/v1/customers?email=john%2Bwork@example.com
```

### Query parameters

Filtering, searching, sorting on collections: `?status=ACTIVE`, `?search=john`, `?sort=-createdAt`.

## GET

```
GET /api/v1/customers/550e8400-...
→ 200 OK

GET /api/v1/customers?page=1&limit=20&search=john&sort=-createdAt
→ 200 OK  (always, even if empty — return [] with pagination)
```

## POST

```
POST /api/v1/customers
→ 201 Created  (body contains the created resource)
Location: /api/v1/customers/550e8400-e29b-41d4-a716-446655440001
```

## PUT — full replacement

All fields required. Null fields overwrite existing values.

```
PUT /api/v1/customers/550e8400-...
→ 200 OK  (with updated resource)
```

## PATCH — partial update

Only non-null provided fields are updated — `null` and absent fields are treated identically: ignored.

```
PATCH /api/v1/customers/550e8400-...
{ "lastName": "Smith" }
→ 200 OK  (with full updated resource)
```

## DELETE — idempotent

```
DELETE /api/v1/customers/550e8400-...
→ 204 No Content  (whether resource existed or not)
```

## Optional references

Load the reference file for each area the current task touches:

- `references/payload-conventions.md` — camelCase field names, primitive types (UUID, ISO 8601 date-time, enum `UPPER_SNAKE_CASE`), null-vs-absent semantics, audit fields.
  Load when designing JSON request/response shapes.
- `references/dto-conventions.md` — DTO naming (noun-first), DTO types per operation, JSON examples.
  Load when designing request/response shapes or DTO naming.
- `references/pagination-sorting.md` — query parameters, JSON:API sort format, paged response envelope, empty-result shape, stable sorting.
  Load when designing list endpoints.
- `references/idempotency.md` — `Idempotency-Key` for POST retries.
  Load when designing retry-safe writes.
- `references/error-format.md` — error object, error codes, validation error shape, validation rule catalog, scenario-to-HTTP mapping.
  Load when designing error responses.
- `references/lookup-endpoints.md` — strategy by data volume, `X-Total-Count`, frontend UX pattern.
  Load when designing dropdown/autocomplete endpoints.
- `references/api-security.md` — stateless auth, cookie-based tokens, rate limiting, brute-force protection, CORS.
  Load when designing authentication or security behavior.
