# DTO Conventions

Naming, structure, and JSON contracts for request/response DTOs.

## Noun-first naming

Name DTOs as `{Entity}{Operation}` — noun first:

```
✅ Customer, CustomerCreate, CustomerUpdate, CustomerListItem, CustomerLookup
❌ CreateCustomer, UpdateCustomer
```

## DTO types per operation

| DTO | Used for | Purpose |
|-----|------|---------|
| `XxxCreate` | POST body | All required fields for creation |
| `XxxUpdate` | PUT body | All fields required (full replacement) |
| `XxxPatch` | PATCH body | All fields optional, at least one required |
| `Xxx` | Response (single) — GET `/{id}`, POST 201, PUT 200, PATCH 200 | All fields, no associations — default representation |
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

### Single resource response (default)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "phone": "+1234567890",
  "status": "ACTIVE",
  "createdAt": "2026-01-15T10:30:00Z",
  "updatedAt": "2026-03-02T14:05:00Z"
}
```

### Summary response

Served on `Accept: application/vnd.api.customer.summary+json`. Reduced field set — no audit timestamps, no associations:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE"
}
```

### Full response

Served on `Accept: application/vnd.api.customer.full+json`. Default fields plus expanded associations inlined as nested objects:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "phone": "+1234567890",
  "status": "ACTIVE",
  "createdAt": "2026-01-15T10:30:00Z",
  "updatedAt": "2026-03-02T14:05:00Z",
  "addresses": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "street": "123 Main St",
      "city": "New York",
      "country": "US"
    }
  ],
  "preferredPaymentMethod": {
    "id": "bb112233-4455-6677-8899-aabbccddeeff",
    "type": "CREDIT_CARD",
    "last4": "4242"
  }
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

Lookup items MAY include an entity-specific identifier field when it carries display meaning (e.g. `code` for currencies, `iso` for countries):

```json
{ "id": "550e8400-...", "code": "USD", "name": "US Dollar" }
```

