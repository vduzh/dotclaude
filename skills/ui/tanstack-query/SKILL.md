---
name: tanstack-query
description: TanStack Query patterns — caching strategy, query invalidation after mutations, polling, queryKeys conventions
---

# TanStack Query Patterns

Apply these patterns when working with TanStack Query (React Query).

## Caching Strategy: No Cache by Default

```typescript
// queryClient.ts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 0,               // Data always considered stale
      gcTime: 10 * 60 * 1000,     // 10 min — keep in memory for instant display
      refetchOnWindowFocus: true,  // Refetch when user returns to tab
    },
  },
});
```

**Why:** CRM/business data changes frequently, stale data causes confusion. Every page visit = fresh data. `gcTime > 0` enables instant UI while refetching in background.

**Override for static data:**
```typescript
useQuery({
  queryKey: queryKeys.currencies.lookup(),
  queryFn: currencyService.getCurrenciesLookup,
  staleTime: 5 * 60 * 1000, // 5 minutes — rarely changes
});
```

## Query Keys Convention

```typescript
export const queryKeys = {
  athletes: {
    all: () => ['athletes'] as const,
    list: (params: AthleteFilters) => ['athletes', 'list', params] as const,
    detail: (id: string) => ['athletes', id] as const,
    lookup: () => ['athletes', 'lookup'] as const,
  },
};
```

## Query Invalidation After Mutations

```typescript
const createAthlete = useMutation({
  mutationFn: athleteService.create,
  onSuccess: () => {
    // CREATE — invalidate all collection queries
    queryClient.invalidateQueries({ queryKey: queryKeys.athletes.all() });
  },
});

const updateAthlete = useMutation({
  mutationFn: athleteService.update,
  onSuccess: (_, { id }) => {
    // UPDATE/PATCH — invalidate specific + collections
    queryClient.invalidateQueries({ queryKey: queryKeys.athletes.detail(id) });
    queryClient.invalidateQueries({ queryKey: queryKeys.athletes.all() });
  },
});

const deleteAthlete = useMutation({
  mutationFn: athleteService.delete,
  onSuccess: (_, id) => {
    // DELETE — remove from cache + invalidate collections
    queryClient.removeQueries({ queryKey: queryKeys.athletes.detail(id) });
    queryClient.invalidateQueries({ queryKey: queryKeys.athletes.all() });
  },
});
```

## Polling Pattern

For status updates (payments, long-running tasks):

```typescript
const { data } = useQuery({
  queryKey: ['payments', paymentId],
  queryFn: () => paymentService.getStatus(paymentId),
  refetchInterval: (query) => {
    const status = query.state.data?.status;
    if (status === 'succeeded' || status === 'canceled' || status === 'expired') {
      return false; // Stop polling
    }
    return 3000; // Poll every 3 seconds
  },
});
```

## Smooth Pagination

Use `placeholderData: keepPreviousData` for smooth table transitions:

```typescript
const { data, isPlaceholderData } = useQuery({
  queryKey: queryKeys.athletes.list({ page, limit, sort, search }),
  queryFn: () => athleteService.getList({ page, limit, sort, search }),
  placeholderData: keepPreviousData, // Keep old data while loading next page
});
```

## Multi-Tab Behavior

- Each browser tab has isolated cache
- `refetchOnWindowFocus: true` ensures data updates when switching tabs
- No real-time sync between tabs (would require WebSocket)
