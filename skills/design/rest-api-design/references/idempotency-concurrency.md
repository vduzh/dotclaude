# Idempotency and Concurrency Control

Optional patterns for retry-safety on non-idempotent operations and optimistic concurrency on updates.

## Idempotency keys (POST)

POST is not idempotent — a retried request creates duplicates. Clients that need retry-safety send an `Idempotency-Key` header:

```
POST /api/v1/orders
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440001
Content-Type: application/json

{ ... }
```

Server behavior when the endpoint supports idempotency:

| Situation | Response |
|-----------|----------|
| First request with this key | Process normally; cache `{status, headers, body}` keyed by `{Idempotency-Key, path}` for at least 24 hours |
| Retry with the same key and same body | Replay the cached response — same status, body, headers; no reprocessing |
| Same key with a different body | `409 Conflict` with `CONFLICT` code |

**Key format:** `uuid` recommended (128 bits of entropy). Clients generate; servers never generate keys on the client's behalf.

**When to apply:** high-stakes POST operations — creating orders, charging cards, sending notifications. Skip for safe reads or already-idempotent verbs (PUT, DELETE).

## Optimistic concurrency (ETag / If-Match)

Prevents the lost-update problem when multiple clients modify the same resource. Applies to PUT and PATCH.

### Read emits an ETag

```
GET /api/v1/customers/550e8400-...
→ 200 OK
ETag: "3a1b7f"

{ ... }
```

### Update sends If-Match

```
PUT /api/v1/customers/550e8400-...
If-Match: "3a1b7f"

{ ... }
```

Server behavior when the endpoint enforces optimistic concurrency:

| Situation | Response |
|-----------|----------|
| `If-Match` matches the current resource version | Apply update; return a new `ETag` in the response |
| `If-Match` does not match (resource changed) | `412 Precondition Failed` with `PRECONDITION_FAILED` code |
| `If-Match` absent on a mandatory endpoint | `428 Precondition Required` with `PRECONDITION_REQUIRED` code |

**ETag format:** opaque server-generated string — typically a hash of the representation or a version counter. Clients must not interpret it.

Use **strong** ETags (`"abc"`); weak ETags (`W/"abc"`) are for byte-level cache validation, not concurrency.

**When to apply:** resources edited by multiple concurrent users (admin consoles, collaborative edits). Skip for single-user resources or append-only data.

## Status codes summary

| Code | Condition | Error code |
|------|-----------|------------|
| `409 Conflict` | `Idempotency-Key` reuse with different body | `CONFLICT` |
| `412 Precondition Failed` | `If-Match` ETag mismatch | `PRECONDITION_FAILED` |
| `428 Precondition Required` | `If-Match` missing on an endpoint that requires it | `PRECONDITION_REQUIRED` |
