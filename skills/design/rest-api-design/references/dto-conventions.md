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
| `Xxx` | Response (single), default on `application/json` | All fields; associations as identifiers (scalar FK: `xxxId`; collection FK: array of UUIDs) |
| `XxxSummary` | Response on `.summary+json` | Reduced field set — lightweight display |
| `XxxFull` | Response on `.full+json` | Default + expanded associations |
| `XxxListItem` | Response (list) | Subset of fields for table/list view |
| `XxxLookup` | Response (dropdown) | Minimal: `id` + display name |

## Association expansion rules (`.full+json`)

Scalar FK and collection FK follow different naming rules in the expanded variant:

| Relation | Default (`application/json`) | Expanded (`.full+json`) |
|---|---|---|
| Scalar FK | `countryId: "uuid"` | `country: {id, name, ...}` — `Id`-suffix drops |
| Collection FK | `paymentMethods: ["uuid", "uuid"]` | `paymentMethods: [{id, name}, ...]` — same field name |

The scalar `xxxId` / `xxx` split makes the type visible from the field name (UUID-string vs object). For collections, the plural already signals multiplicity, so the field name stays — clients discriminate value shape by `Accept`.

## JSON examples

### Create (POST)

```json
// POST /api/v1/customers
{
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE",
  "countryId": "660e8400-e29b-41d4-a716-446655440010",
  "paymentMethods": ["770e8400-e29b-41d4-a716-446655440020"]
}
```

`email` is nullable — omit the field or send `"email": null`; both mean "no email". `countryId` is required. `paymentMethods` may be an empty array.

### Update (PUT)

```json
// PUT /api/v1/customers/550e8400-...
{
  "firstName": "John",
  "lastName": "Smith",
  "email": "john.smith@example.com",
  "status": "ACTIVE",
  "countryId": "660e8400-e29b-41d4-a716-446655440010",
  "paymentMethods": [
    "770e8400-e29b-41d4-a716-446655440020",
    "770e8400-e29b-41d4-a716-446655440021"
  ]
}
```

All fields required — full replacement. To clear `email`, send `"email": null` (the only way — see `payload-conventions.md` null-vs-absent).

### Patch (PATCH)

```json
// PATCH /api/v1/customers/550e8400-...
{ "lastName": "Smith" }
```

Only provided fields updated. `null` on PATCH means "don't touch" — it cannot clear `email`; use PUT for that.

### Single resource response (default)

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE",
  "countryId": "660e8400-e29b-41d4-a716-446655440010",
  "paymentMethods": [
    "770e8400-e29b-41d4-a716-446655440020",
    "770e8400-e29b-41d4-a716-446655440021"
  ],
  "createdAt": "2026-01-15T10:30:00Z",
  "updatedAt": "2026-03-02T14:05:00Z"
}
```

### Summary response

Served on `Accept: application/vnd.api.customer.summary+json`. Reduced — no associations, no audit timestamps:

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

Served on `Accept: application/vnd.api.customer.full+json`. Scalar FK expanded as a named object (`country`, `Id`-suffix dropped); collection FK expanded as an array of objects (`paymentMethods`, same field name as default):

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE",
  "country": {
    "id": "660e8400-e29b-41d4-a716-446655440010",
    "name": "United States"
  },
  "paymentMethods": [
    { "id": "770e8400-e29b-41d4-a716-446655440020", "name": "Credit Card" },
    { "id": "770e8400-e29b-41d4-a716-446655440021", "name": "Bank Transfer" }
  ],
  "createdAt": "2026-01-15T10:30:00Z",
  "updatedAt": "2026-03-02T14:05:00Z"
}
```

### List item response

Subset of fields for table display:

```json
{ "id": "550e8400-...", "firstName": "John", "lastName": "Doe", "status": "ACTIVE" }
```

### Lookup response

Minimal — for dropdown/select. Display `name` is derived (for `Customer`, `firstName + " " + lastName`):

```json
{ "id": "550e8400-...", "name": "John Doe" }
```

Dictionary lookups (`Country`, `PaymentMethod`) use the same `{id, name}` shape — see `lookup-endpoints.md`.
