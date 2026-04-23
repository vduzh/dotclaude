# Lookup Endpoints

Design pattern for dropdown/autocomplete endpoints.

```
GET /api/v1/customers
Accept: application/vnd.api.customer.lookup+json
```

Lookup endpoints return a flat array `T[]` — not a paginated wrapper.

**Default sort:** by display name ascending, unless the client specifies an explicit `sort` parameter.

## Strategy by data volume

| Dataset | Expected volume | Strategy | X-Total-Count |
|---------|----------------|----------|:---:|
| Customers, Users | 10-10000 | Server-side search | Yes |
| Payment Methods | <50/user | Load all | No |
| Currencies | ~50 global | Load all | No |
| Dictionaries | ~10-20 | Load all | No |

## Large lookup (server-side search)

Query parameters: `search` (case-insensitive partial match), `limit` (default 50, max 100 — differs from pagination defaults).
Response header: `X-Total-Count` — total matching records.

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

When `search` is absent, return the first `limit` records sorted by display name. An empty search is valid — do not return `400`.

## Small lookup (load all)

No search, no pagination, no `X-Total-Count`:

```
GET /api/v1/currencies
Accept: application/vnd.api.currency.lookup+json
→ 200 OK
[
  { "id": "550e8400-...", "code": "USD", "name": "US Dollar" }
]
```

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

- Debounce 300ms on search input
- `hasMore = X-Total-Count > items.length`
