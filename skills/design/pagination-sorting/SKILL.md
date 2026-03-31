---
name: pagination-sorting
description: Pagination, filtering, and sorting design — query parameters, JSON:API sort format, PagedResponse wrapper format, search and filter conventions
---

# Pagination, Filtering, Sorting

MANDATORY for all list endpoints.

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `page` | integer | 1 | 1-indexed page number |
| `limit` | integer | 20 | Items per page (1-100) |
| `sort` | string | `-createdAt` | JSON:API format sort |
| `search` | string | — | Search across multiple fields (case-insensitive partial match) |
| Filter params | varies | — | Entity-specific filters (`status`, `countryId`, etc.) |

## JSON:API Sort Format

- **Ascending**: `sort=name`
- **Descending**: `sort=-createdAt` (prefix with `-`)
- **Multiple fields**: `sort=name,-createdAt` (comma-separated)

Example:
```
GET /api/v1/customers?page=2&limit=50&search=john&sort=name,-createdAt
```

## PagedResponse Format

All list endpoints return a paginated wrapper:

```json
{
  "data": [
    { "id": "550e8400-...", "firstName": "John", "status": "active" },
    { "id": "550e8401-...", "firstName": "Jane", "status": "active" }
  ],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 156,
    "totalPages": 8
  }
}
```

**NOT affected** (return `T[]` directly):
- Lookup endpoints (`*.lookup+json`)
- Single resource endpoints (`GET /{id}`)
- Mutation endpoints (POST, PUT, PATCH, DELETE)
- Reference/dictionary endpoints

## Empty Results

Return empty array `[]` with pagination showing zero total — **NOT** 404:

```json
{
  "data": [],
  "pagination": {
    "page": 1,
    "perPage": 20,
    "total": 0,
    "totalPages": 0
  }
}
```

## Filter Strategy

- **1-3 filter parameters**: Pass as individual query parameters (`?search=john&countryId=...`)
- **4+ filter parameters**: Group into a filter object on the server side

## Stable Sorting

Always append the primary key (`id`) as the final sort field to guarantee deterministic ordering across pages. Without this, records can shift between pages when multiple records share the same sort value.
