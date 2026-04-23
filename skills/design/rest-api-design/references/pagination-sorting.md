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

## JSON:API sort format

- Ascending: `sort=name`
- Descending: `sort=-createdAt` (prefix with `-`)
- Multiple fields: `sort=name,-createdAt` (comma-separated)

```
GET /api/v1/customers?page=2&limit=50&search=john&sort=name,-createdAt
```

## Paged response envelope

```json
{
  "data": [
    { "id": "550e8400-...", "firstName": "John", "status": "ACTIVE" }
  ],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 156,
    "totalPages": 8
  }
}
```

**Not applicable** (return `T[]` directly): lookup endpoints, single resource `GET /{id}`, mutations, reference/dictionary endpoints.

## Empty results

Return `[]` with zero totals — never `404`:

```json
{ "data": [], "pagination": { "page": 1, "perPage": 20, "total": 0, "totalPages": 0 } }
```

## Filter strategy

- 1-3 filter parameters: individual query params (`?search=john&countryId=...`)
- 4+ filter parameters: group into a filter object server-side

## Stable sorting

Always append `id` as the final sort field — prevents records from shifting between pages when multiple records share the same sort value.
