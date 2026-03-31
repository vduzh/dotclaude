---
name: rest-api-design
description: REST API design conventions — URI versioning, HTTP methods, status codes, content negotiation, query/path params, update/delete semantics
---

# REST API Design Conventions

Apply these conventions when designing or implementing REST API endpoints.

## URI Versioning

```
/api/v1/...
/api/v2/...
```

## HTTP Methods

| Method | Purpose |
|--------|---------|
| GET | Read resource(s) |
| POST | Create resource |
| PUT | Full update (all fields required) |
| PATCH | Partial update (only provided fields) |
| DELETE | Delete resource |

## Status Codes

| Code | When |
|------|------|
| 200 OK | Successful read or update |
| 201 Created | Resource created (POST) |
| 204 No Content | Successful delete |
| 400 Bad Request | Validation error, invalid input |
| 404 Not Found | Resource not found |
| 406 Not Acceptable | Unsupported Accept header |
| 409 Conflict | Business conflict, duplicate, constraint violation |

## Content Negotiation

Support multiple representations of the same collection via `Accept` header. The **list view is the default** — it serves both `application/json` (for Swagger, generic clients) and the vendor media type. Specialized views (lookup, etc.) require an explicit vendor `Accept` header.

```java
// List view — default representation (serves application/json AND vendor type)
@GetMapping(produces = {"application/json", "application/vnd.api.profile.list+json"})

// Lookup view — requires explicit Accept header
@GetMapping(produces = "application/vnd.api.profile.lookup+json")
```

Spring automatically routes requests based on `Accept` header — no manual parsing needed.

## Query vs Path Parameters

- **Query params**: Filtering/searching collections (`?email=...`, `?status=active`)
- **Path with prefix**: Alternative unique identifier lookup (`/by-email/{email}`, `/by-username/{username}`)
- Avoid confusing patterns like `/customers/email/{email}` (looks like nested resource)

## Update Operations

- **PUT**: Full replacement — all fields required in DTO. Null fields overwrite existing values.
- **PATCH**: Partial update — null fields are ignored, only provided fields are updated.

## Delete Operations (Idempotent)

DELETE must be **idempotent** per RFC 7231:
- If resource exists → delete it, return **204 No Content**
- If resource does NOT exist → just return **204 No Content** (no 404 error)

Benefits:
- Complies with HTTP specification
- Simplifies client code (no need to handle 404 as a special case)
- Parallel requests (double-click) both return success

```java
public void deleteXxx(UUID id) {
    repository.findById(id).ifPresent(entity -> {
        repository.delete(entity);
        log.info("Deleted xxx with ID: {}", id);
    });
}
```

With business rules:
```java
public void deletePaymentMethod(UUID coachId, UUID paymentMethodId) {
    paymentMethodRepository.findByIdAndCoachId(paymentMethodId, coachId)
        .ifPresent(paymentMethod -> {
            if (subscriptionRepository.existsByPaymentMethodId(paymentMethodId)) {
                throw new IllegalStateException("Cannot delete: assigned to subscriptions");
            }
            paymentMethodRepository.delete(paymentMethod);
        });
}
```

> Business checks (cannot delete resource in use) are only performed if the resource is found.
