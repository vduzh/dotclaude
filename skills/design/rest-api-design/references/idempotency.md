# Idempotency

Optional pattern for retry-safety on non-idempotent operations. An `Idempotency-Key` on a POST request guarantees the operation executes **at most once**; retries return the current state of the created resource.

## Idempotency keys (POST)

POST is not idempotent — a retried request creates duplicates. Clients that need retry-safety send an `Idempotency-Key` header:

```
POST /api/v1/orders
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440001
Content-Type: application/json

{ ... }
```

## Semantics

An `Idempotency-Key` marks a single logical operation. It guarantees:

1. The side effect (resource creation, outbound call, external charge) happens **at most once**, regardless of how many retries arrive — including concurrent retries.
2. Retries return the **current** state of the created resource — not a snapshot from the first response.

## Key scoping

The key is scoped by `{Idempotency-Key, endpoint path}`. The same key value MAY be reused across different endpoints — they are independent operations:

```
POST /api/v1/orders          Idempotency-Key: K   → operation A
POST /api/v1/notifications   Idempotency-Key: K   → operation B (separate)
```

## Observable behavior

| Situation | Response |
|-----------|----------|
| First request with this key on this path | `201 Created` with the created resource body |
| Retry with the same key, same path, same body | `201 Created` with the **current** resource state |
| Retry with the same key and path but different body | `409 Conflict` with `CONFLICT` code |
| Retry when the created resource no longer exists | `410 Gone` with `GONE` code |

A successful retry is indistinguishable from the first request by status code — both return `201 Created`. The response body on retry reflects the current state of the resource, not the body that was returned on the first request.

### Invariants

- Concurrent requests with the same `{key, path}` and same body MUST NOT both produce side effects — only one takes effect; the others observe the same outcome as a sequential retry.
- A retry response MUST reflect the current state of the resource, not a cached response body.
- A retry with a different body MUST be rejected — idempotency is tied to the pair (key, operation payload).

## Body-mismatch detection

On retry, the server compares the request body against the body of the first accepted request. On mismatch → `409 Conflict` — this indicates a client bug (key collision or accidental reuse with different data).

## Key format

`uuid` recommended — 128 bits of entropy. Clients generate the key; servers never generate keys on a client's behalf. Keys MUST be unique per logical operation on the client side.

## Retention

The once-only guarantee holds for at least **24 hours** after the first request. After this window, the server MAY accept the same key value as a new operation — clients should not rely on longer retention.

The retention window bounds how long the guarantee holds. It does not bound data freshness — retries inside the window always return the current state.

## When to apply

High-stakes POST operations where a duplicate is costly — creating orders, charging cards, sending notifications, enrolling users. Skip for:

- Safe reads (GET).
- Already-idempotent verbs (PUT, DELETE).
- Low-risk POSTs where a duplicate is harmless.

## Status codes summary

| Code | Condition | Error code |
|------|-----------|------------|
| `201 Created` | First request or successful retry (current resource returned) | — |
| `409 Conflict` | Same key reused with different request body | `CONFLICT` |
| `410 Gone` | Retry when the created resource no longer exists | `GONE` |
