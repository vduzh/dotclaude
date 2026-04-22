# DTO Conventions

Naming, structure, and JSON contracts for request/response DTOs.

## Noun-first naming

Name DTOs as `{Entity}{Operation}` — noun first:

```
✅ Customer, CustomerCreate, CustomerUpdate, CustomerListItem, CustomerLookup
❌ CreateCustomer, UpdateCustomer
```

## DTO types per operation

| DTO | HTTP | Purpose |
|-----|------|---------|
| `XxxCreate` | POST body | All required fields for creation |
| `XxxUpdate` | PUT body | All fields required (full replacement) |
| `XxxPatch` | PATCH body | All fields optional, at least one required |
| `Xxx` | Response (single) | Full resource representation |
| `XxxListItem` | Response (list) | Subset of fields for table/list view |
| `XxxLookup` | Response (dropdown) | Minimal fields (id + display name) |
| `XxxSearchParams` | Query params | Pagination, sorting, filters |

## JSON examples

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

All fields required — full replacement.

### Patch (PATCH)

```json
// PATCH /api/v1/customers/550e8400-...
{ "lastName": "Smith" }
```

Only provided fields updated. Empty body `{}` → `400`. Blank strings → `400`.

### Single resource response

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "active",
  "createdAt": "2025-01-15T10:30:00Z"
}
```

### List item response

Subset of fields for table display:

```json
{ "id": "550e8400-...", "firstName": "John", "lastName": "Doe", "status": "active" }
```

### Lookup response

Minimal — for dropdown/select:

```json
{ "id": "550e8400-...", "name": "John Doe" }
```

## Validation rules

| Rule | When | Error |
|------|------|-------|
| Required field missing | Create, Update | 400 — "Field is required" |
| String exceeds max length | Create, Update, Patch | 400 — "Max N characters" |
| Invalid email format | Create, Update, Patch | 400 — "Invalid email" |
| Empty patch body | Patch | 400 — "At least one field required" |
| Blank string in patch | Patch | 400 — "Must not be blank" |
