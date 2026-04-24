# Pagination, Filtering, Sorting

Mandatory for all list endpoints.

## Query parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | integer | 1 | 1-indexed page number |
| `limit` | integer | 20 | Items per page (1-100) |
| `sort` | string | `-createdAt` | JSON:API sort format |
| `search` | string | — | Case-insensitive partial match across multiple fields |
| Filter params | varies | — | Entity-specific filters (`status`, `countryId`, etc.) |

Values outside the documented ranges (e.g. `limit=0`, `limit=200`, `page=0`) → `400 VALIDATION_ERROR`.

## JSON:API sort format

- Ascending: `sort=lastName`
- Descending: `sort=-createdAt` (prefix with `-`)
- Multiple fields: `sort=lastName,-createdAt` (comma-separated)

```
GET /api/v1/customers?page=2&limit=50&search=john&sort=lastName,-createdAt
```

## Paged response envelope

```json
{
  "data": [
    { "id": "550e8400-...", "firstName": "John", "lastName": "Doe", "status": "ACTIVE" }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 156,
    "totalPages": 8
  }
}
```

**Not applicable** (return a plain JSON array or a single object, no pagination wrapper): lookup endpoints, single resource `GET /{id}`, mutations, reference/dictionary endpoints.

## Empty results

Return `[]` with zero totals — never `404`:

```json
{ "data": [], "pagination": { "page": 1, "limit": 20, "total": 0, "totalPages": 0 } }
```

## Stable sorting

The server always appends `id` as the final tiebreaker regardless of the client-specified `sort` — this prevents records from shifting between pages when multiple records share the same sort value.
