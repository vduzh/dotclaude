---
name: react-component-patterns
description: React component conventions — TypeScript strict mode, component structure with barrel exports, error/loading/empty states, memoization rules
---

# React Component Patterns

Apply these patterns when creating or modifying React components.

## TypeScript Strict Rules

- **No `any` type** — TypeScript strict mode is enabled
- All components must be typed with TypeScript interfaces
- Use `React.FC<Props>` for functional components

```typescript
interface AthleteCardProps {
  athlete: Athlete;
  onEdit: (id: string) => void;
}

const AthleteCard: React.FC<AthleteCardProps> = ({ athlete, onEdit }) => {
  // ...
};
```

## Component Structure

Components in folders with `index.ts` barrel export:

```
components/
├── common/                        # Reusable UI components
│   ├── AthleteModal/
│   │   ├── AthleteModal.tsx       # Component implementation
│   │   └── index.ts               # export { AthleteModal } from './AthleteModal'
│   └── ConfirmButton/
│       ├── ConfirmButton.tsx
│       └── index.ts
├── features/                      # Feature-specific components
└── layouts/                       # Layout components
```

## Type Definitions

All types in `types/*.types.ts` organized by domain:

```typescript
// types/athlete.types.ts
export interface Athlete {
  id: string;
  firstName: string;
  lastName: string;
}

export interface AthleteCreate {
  firstName: string;
  lastName: string;
  email: string;
}

export interface AthleteUpdate { ... }
export interface AthleteFilters { ... }
```

Common types:
```typescript
// types/common.types.ts
export interface PagedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    perPage: number;
    total: number;
    totalPages: number;
  };
}
```

## Error/Loading/Empty States

Always handle all three states:

```typescript
if (isLoading) return <Spin size="large" tip="Loading..." />;
if (error) return <Alert type="error" message="Failed to load" />;
if (!data?.length) return <Empty description="No data" />;
```

## Memoization Rules

```typescript
// useCallback — for event handlers passed to children
const handleEdit = useCallback((id: string) => {
  setEditingId(id);
}, []);

// useMemo — for expensive calculations
const filteredItems = useMemo(
  () => items.filter(item => item.name.includes(search)),
  [items, search]
);

// React.memo — for components that re-render frequently
const AthleteRow = React.memo<AthleteRowProps>(({ athlete, onEdit }) => {
  // ...
});
```

## Route Pages

Pages use lazy loading with Suspense:

```typescript
// routes/index.tsx
const AthletesPage = lazy(() => import('@/pages/AthletesPage'));

<Suspense fallback={<LoadingSpinner />}>
  <AthletesPage />
</Suspense>
```

## Path Alias

Use `@/` alias for imports (resolves to `src/`):

```typescript
import { athleteService } from '@/api/services/athleteService';
import { useDebounce } from '@/hooks/useDebounce';
```

## Code Quality

- All user-facing text in English
- No `console.log()` in production code
- Unused locals/parameters not allowed
