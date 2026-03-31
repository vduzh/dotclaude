---
name: dto-conventions
description: DTO naming and structure conventions — noun-first naming, separate DTOs per operation, request/response JSON contracts
---

# DTO Conventions

Apply these conventions when designing API request/response contracts.

## Noun-First Naming

Name DTOs as `{Entity}{Operation}` — noun first, NOT verb first:

```
✅ Customer, CustomerCreate, CustomerUpdate, CustomerListItem, CustomerLookup
❌ CreateCustomer, UpdateCustomer
```

## Separate DTOs Per Operation

Each entity gets its own set of request/response structures:

| DTO | HTTP | Purpose |
|-----|------|---------|
| `XxxCreate` | POST body | All required fields for creation |
| `XxxUpdate` | PUT body | All fields required (full replacement) |
| `XxxPatch` | PATCH body | All fields optional, at least one required |
| `Xxx` | Response (single) | Full resource representation |
| `XxxListItem` | Response (list) | Subset of fields for table/list view |
| `XxxLookup` | Response (dropdown) | Minimal fields (id + display name) |
| `XxxSearchParams` | Query params | Pagination, sorting, filters |

## Request Examples

### Create (POST)

```json
// POST /api/v1/customers
{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "phone": "+1234567890"
}
```

All fields validated: required fields must be present, strings have max length, email format checked.

### Update (PUT)

```json
// PUT /api/v1/customers/550e8400-...
{
  "firstName": "John",
  "lastName": "Smith",
  "email": "john.smith@example.com",
  "phone": "+1234567890"
}
```

All fields required — this is a full replacement.

### Patch (PATCH)

```json
// PATCH /api/v1/customers/550e8400-...
{
  "lastName": "Smith"
}
```

Only provided fields are updated. Empty body or `{}` → `400 Bad Request` (at least one field required). Blank strings → `400 Bad Request` (field is either `null`/absent or a valid non-blank value).

## Response Examples

### Single Resource (Xxx)

```json
// GET /api/v1/customers/550e8400-...  →  200 OK
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "phone": "+1234567890",
  "status": "active",
  "createdAt": "2025-01-15T10:30:00Z"
}
```

### List Item (XxxListItem)

Subset of fields optimized for table display:

```json
{
  "id": "550e8400-...",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "active"
}
```

### Lookup (XxxLookup)

Minimal — for dropdown/select components:

```json
{
  "id": "550e8400-...",
  "name": "John Doe"
}
```

## Validation Rules

| Rule | When | Error |
|------|------|-------|
| Required field missing | Create, Update | `400` — "Field is required" |
| String exceeds max length | Create, Update, Patch | `400` — "Max N characters" |
| Invalid email format | Create, Update, Patch | `400` — "Invalid email" |
| Empty patch body | Patch | `400` — "At least one field required" |
| Blank string in patch | Patch | `400` — "Must not be blank" |

