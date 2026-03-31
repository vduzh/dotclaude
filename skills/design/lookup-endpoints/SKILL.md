---
name: lookup-endpoints
description: Lookup endpoint design — strategy by data volume, X-Total-Count header, server-side search for large datasets, frontend UX pattern
---

# Lookup Endpoints

Apply these patterns when implementing lookup/autocomplete endpoints for dropdown/select components.

## Content Type

```java
@GetMapping(produces = "application/vnd.api.{entity}.lookup+json")
```

Lookup endpoints return `List<T>` (NOT `PagedResponse`).

## Strategy by Data Volume

| Dataset | Expected Volume | Strategy | X-Total-Count |
|---------|----------------|----------|---------------|
| Athletes, Users | 10-10000 | Server-side search | ✅ Yes |
| Payment Methods | <50/user | Load all | ❌ No |
| Currencies | ~50 global | Load all | ❌ No |
| Dictionaries | ~10-20 | Load all | ❌ No |

## Large Lookups (Server-Side Search)

Query parameters:
- `search` (string) — filter by name/email (ILIKE)
- `limit` (integer, default: 50, max: 100) — result limit

Response headers:
- `X-Total-Count` — total matching records (for "Showing 20 of 150" UI)

```java
@GetMapping(produces = "application/vnd.api.athlete.lookup+json")
public ResponseEntity<List<AthleteLookupDto>> getAthletesAsLookup(
        @AuthenticationPrincipal UserDetails userDetails,
        @Valid @ModelAttribute AthleteLookupSearchParams params) {
    UUID userId = getCurrentUserId(userDetails);
    PagedResult<AthleteLookupDto> result = athleteService.searchAthletesAsLookup(userId, params);

    return ResponseEntity.ok()
        .header("X-Total-Count", String.valueOf(result.total()))
        .body(result.content());  // List<T> — contract unchanged
}
```

## Small Lookups (Load All)

No search, no pagination, no X-Total-Count — just return the full list:

```java
@GetMapping(produces = "application/vnd.api.currency.lookup+json")
public List<CurrencyLookupDto> getCurrenciesAsLookup() {
    return currencyService.getAllAsLookup();
}
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
