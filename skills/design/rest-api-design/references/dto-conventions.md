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
| `Xxx` | Response (single) | All fields, no associations — default representation |
| `XxxSummary` | Response (single, summary) | Reduced field set — used when endpoint offers `.summary+json` |
| `XxxFull` | Response (single, full) | Default + expanded associations — used when endpoint offers `.full+json` |
| `XxxListItem` | Response (list) | Subset of fields for table/list view |
| `XxxLookup` | Response (dropdown) | Minimal fields (id + display name) |

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

Only provided fields updated.

### Single resource response

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE",
  "createdAt": "2025-01-15T10:30:00Z",
  "updatedAt": "2025-03-02T14:05:00Z"
}
```

### List item response

Subset of fields for table display:

```json
{ "id": "550e8400-...", "firstName": "John", "lastName": "Doe", "status": "ACTIVE" }
```

### Lookup response

Minimal — for dropdown/select:

```json
{ "id": "550e8400-...", "name": "John Doe" }
```

## Validation

Per-DTO validation rules and the error shape they produce live in `references/error-format.md` (see "Validation rule catalog").
