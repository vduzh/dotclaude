# Lookup Endpoints

Design pattern for dropdown/autocomplete endpoints.

```
GET /api/v1/customers
Accept: application/vnd.api.customer.lookup+json
```

Lookup endpoints return a flat JSON array — not a paginated wrapper.

**Default sort:** by display name ascending, unless the client specifies an explicit `sort` parameter.

## Strategy by data volume

| Dataset | Expected volume | Strategy | X-Total-Count |
|---------|----------------|----------|:---:|
| Customers | 10-10000 | Server-side search | Yes |
| Countries | ~200 global | Server-side search | Yes |
| Payment Methods | ~5-10 global | Load all | No |
| Other dictionaries | ~10-20 | Load all | No |

The catalog uses `Country` and `PaymentMethod` as the two canonical dictionaries — one of each strategy, so implementers see both shapes side by side.

## Large lookup (server-side search)

Query parameters: `search` (case-insensitive partial match), `limit` (default 50, max 100 — differs from pagination defaults).
Response header: `X-Total-Count` — total matching records.

### Customer example

```
GET /api/v1/customers?search=john&limit=20
Accept: application/vnd.api.customer.lookup+json
→ 200 OK
X-Total-Count: 150

[
  { "id": "550e8400-...", "name": "John Doe" },
  { "id": "550e8401-...", "name": "John Smith" }
]
```

### Country example

```
GET /api/v1/countries?search=united&limit=20
Accept: application/vnd.api.country.lookup+json
→ 200 OK
X-Total-Count: 3

[
  { "id": "660e8400-...", "name": "United Arab Emirates" },
  { "id": "660e8401-...", "name": "United Kingdom" },
  { "id": "660e8402-...", "name": "United States" }
]
```

When `search` is absent, return the first `limit` records sorted by display name. An empty search is valid — do not return `400`.

## Small lookup (load all)

No search, no pagination, no `X-Total-Count` — the client filters in memory.

### PaymentMethod example

```
GET /api/v1/payment-methods
Accept: application/vnd.api.payment-method.lookup+json
→ 200 OK

[
  { "id": "770e8400-...", "name": "Bank Transfer" },
  { "id": "770e8401-...", "name": "Credit Card" }
]
```

Sorted by `name` ascending by default.

## Frontend UX

```
┌─────────────────────────────┐
│ Select customer...       ▼  │
├─────────────────────────────┤
│ 🔍 Search...                │  ← show for large lists
├─────────────────────────────┤
│ John Smith                  │
│ John Doe                    │
│ ─────────────────────────── │
│ Showing 20 of 150           │  ← when X-Total-Count > items.length
└─────────────────────────────┘
```

- Debounce 300ms on search input (large lookups only)
- `hasMore = X-Total-Count > items.length`
- Small lookups (payment methods, other short dictionaries) skip the search box entirely
