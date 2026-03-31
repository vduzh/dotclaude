---
name: lookup-endpoints
description: Lookup endpoint design — strategy by data volume, X-Total-Count header, server-side search for large datasets, frontend UX pattern
---

# Lookup Endpoints

Apply these patterns when designing lookup/autocomplete endpoints for dropdown/select components.

## Content Type

```
GET /api/v1/athletes
Accept: application/vnd.api.athlete.lookup+json
```

Lookup endpoints return a **flat array** `T[]` (NOT a paginated wrapper).

## Strategy by Data Volume

| Dataset | Expected Volume | Strategy | X-Total-Count |
|---------|----------------|----------|---------------|
| Athletes, Users | 10-10000 | Server-side search | Yes |
| Payment Methods | <50/user | Load all | No |
| Currencies | ~50 global | Load all | No |
| Dictionaries | ~10-20 | Load all | No |

## Large Lookups (Server-Side Search)

Query parameters:
- `search` (string) — filter by name/email (case-insensitive partial match)
- `limit` (integer, default: 50, max: 100) — result limit

Response headers:
- `X-Total-Count` — total matching records (for "Showing 20 of 150" UI)

```
GET /api/v1/athletes?search=john&limit=20
Accept: application/vnd.api.athlete.lookup+json

→ 200 OK
X-Total-Count: 150

[
  { "id": "550e8400-...", "name": "John Doe" },
  { "id": "550e8401-...", "name": "John Smith" },
  ...
]
```

## Small Lookups (Load All)

No search, no pagination, no X-Total-Count — just return the full list:

```
GET /api/v1/currencies
Accept: application/vnd.api.currency.lookup+json

→ 200 OK

[
  { "id": "550e8400-...", "code": "USD", "name": "US Dollar" },
  { "id": "550e8401-...", "code": "EUR", "name": "Euro" },
  ...
]
```

## Frontend UX Pattern

```
┌─────────────────────────────┐
│ Select athlete...        ▼  │
├─────────────────────────────┤
│ 🔍 Search...                │  ← always show for large lists
├─────────────────────────────┤
│ John Smith                  │
│ John Doe                    │
│ ...                         │
│ ─────────────────────────── │
│ Showing 20 of 150           │  ← if X-Total-Count > items.length
└─────────────────────────────┘
```

Frontend behavior:
- Debounce 300ms on search input
- Show "Showing X of Y" when `X-Total-Count > items.length`
- `hasMore = totalCount > items.length`
