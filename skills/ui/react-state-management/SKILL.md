---
name: react-state-management
description: React state management strategy — priority order (useState → TanStack Query → Zustand → URL params), never store server data in Zustand
---

# React State Management Strategy

Apply this priority order when deciding where to place state.

## Priority Order

| Priority | Tool | What to Store | Examples |
|----------|------|---------------|---------|
| 1 | `useState` | UI-only state | Modal open/close, toggles, form inputs |
| 2 | TanStack Query | ALL server state | API data, caching, background refetch |
| 3 | Zustand | Global client state only | Auth token, UI preferences (sidebar, theme) |
| 4 | URL parameters | Shareable state | Filters, pagination, search, active tab |

## Rules

### NEVER store server data in Zustand

```typescript
// ❌ Bad — server data in Zustand
const useAthleteStore = create((set) => ({
  athletes: [],
  fetchAthletes: async () => {
    const data = await athleteService.getAthletes();
    set({ athletes: data });
  },
}));

// ✅ Good — server data in TanStack Query
const { data: athletes } = useQuery({
  queryKey: ['athletes'],
  queryFn: athleteService.getAthletes,
});
```

### Zustand — only for global client state

```typescript
// ✅ Auth store — client-only state
interface AuthStore {
  token: string | null;
  isAuthenticated: boolean;
  login: (token: string) => void;
  logout: () => void;
}

// ✅ UI store — client-only preferences
interface UiStore {
  sidebarCollapsed: boolean;
  toggleSidebar: () => void;
}
```

### URL parameters — for shareable state

Filters, pagination, and search should live in URL so users can share/bookmark:

```typescript
// URL: /athletes?page=2&search=john&sort=-createdAt
const [searchParams, setSearchParams] = useSearchParams();
const page = Number(searchParams.get('page')) || 1;
const search = searchParams.get('search') || '';
const sort = searchParams.get('sort') || '-createdAt';
```

## Decision Flowchart

1. Is it from an API? → **TanStack Query**
2. Is it only used in one component? → **useState**
3. Should it persist in URL for sharing? → **URL params**
4. Is it global client-only state? → **Zustand**
