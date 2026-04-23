# Payload Conventions

JSON wire format for request and response bodies — field naming, types, null semantics.

## Field naming

All JSON field names use **camelCase**: `firstName`, `createdAt`, `paymentMethodId`. Never `snake_case`, `kebab-case`, or `PascalCase`.

Acronyms follow the lowercase-after-first-letter rule: `userId`, `apiKey`, `httpStatus` — not `userID`, `APIKey`.

## Types

| Type | JSON form | Example |
|------|-----------|---------|
| `string` | string | `"John"` |
| `integer` | number (no decimals) | `20` |
| `number` | number (decimals allowed) | `19.99` |
| `boolean` | `true` / `false` (not string) | `true` |
| `uuid` | string — lowercase 8-4-4-4-12 hex | `"550e8400-e29b-41d4-a716-446655440001"` |
| `date-time` | string — ISO 8601 UTC with `Z` | `"2026-04-23T10:30:00Z"` |
| `date` | string — ISO 8601 calendar date | `"2026-04-23"` |
| `email` | string — RFC 5322 | `"john@example.com"` |
| `phone` | string — E.164 | `"+1234567890"` |
| `enum` | string — `UPPER_SNAKE_CASE` | `"ACTIVE"`, `"PENDING_APPROVAL"` |

**IDs** are always `uuid`. No sequential numeric IDs on the wire.

**Date-time** is always UTC; the client converts to local timezone for display. Millisecond precision (`...:30:00.123Z`) is allowed when the precision matters.

**Enums** are closed per API version. New values may be added in minor versions; removals only in major versions. Clients must handle unknown values defensively — never crash on an unexpected value.

## Null vs absent

`null` and an absent field mean different things depending on the operation:

| Operation | `"field": null` | Field absent |
|-----------|-----------------|--------------|
| POST / PUT (create / full replace) | Store as null | Error if required; null if optional |
| PATCH (partial update) | "Don't touch this field" | "Don't touch this field" |
| Response | Explicit null | Field omitted (servers may omit null optionals) |

**Key consequence for PATCH:** there is no way to explicitly set a field to `null` via PATCH — `null` means "ignore". To null-out a field, use `PUT` (full replacement).

This follows JSON Merge Patch semantics (RFC 7396).

## Audit fields

All resources include audit timestamps in their default representation:

- `createdAt` (`date-time`) — when the resource was created.
- `updatedAt` (`date-time`) — when the resource was last modified; equals `createdAt` until first change.

Audit fields are **read-only** on the wire — never accepted in POST / PUT / PATCH bodies; always set by the server.

## Canonical example

A response body combining all conventions:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "firstName": "John",
  "lastName": "Doe",
  "email": "john@example.com",
  "status": "ACTIVE",
  "createdAt": "2026-04-23T10:30:00Z",
  "updatedAt": "2026-04-23T10:30:00Z"
}
```
