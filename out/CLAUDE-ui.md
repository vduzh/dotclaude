# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nano CRM is a training business management system for fitness trainers. Built with React 18, TypeScript, Vite, Ant Design 5, Zustand, and TanStack Query.

## Development Commands

```bash
# Development
npm run dev                # Start dev server with development profile (localhost:3000)
npm run dev:test           # Start dev server with test profile (localhost:3000 → test backend)
npm run type-check         # Run TypeScript type checking (no emit)
npm run lint               # Run TypeScript linter

# Production
npm run build              # Build with test profile for production (TypeScript + Vite → dist/)
npm run preview            # Preview production build at http://localhost:8080
npm start                  # Production server (port 8080, host 0.0.0.0)
```

## Environment Configuration

### Environment Profiles

**Development Profile (`dev`):**
- Frontend: `http://localhost:3000`
- Backend: `http://localhost:8080/api/v1`
- File: `.env.development`
- Use: `npm run dev`

**Test Profile (`test`):**
- Frontend: `https://nano-crm.virtualnomad.agency`
- Backend: `https://nano-crm-api.virtualnomad.agency/api/v1`
- File: `.env.test`
- Use: `npm run dev:test` or `npm run build`

### Backend API Path Structure

**IMPORTANT:** Backend resources are located at `/api/v1` path.

The `VITE_API_BASE_URL` should specify **only the base URL** (without `/api/v1`). The `/api/v1` prefix is automatically added in `src/utils/constants.ts`:

```typescript
export const API_CONFIG = {
  BASE_URL: `${import.meta.env.VITE_API_BASE_URL || 'http://localhost:8080'}/api/v1`,
};
```

## Architecture

### Project Structure

```
src/
├── api/
│   ├── client.ts              # Axios client with interceptors
│   └── services/              # API service implementations
├── components/
│   ├── common/                # Reusable UI components
│   ├── features/              # Feature-specific components
│   └── layouts/               # Layout components (DashboardLayout)
├── hooks/                     # Custom React hooks (useDebounce, etc.)
├── pages/                     # Route pages (*.Page.tsx)
├── routes/                    # React Router configuration
├── store/                     # Zustand stores (authStore, uiStore)
├── types/                     # TypeScript type definitions (*.types.ts)
└── utils/                     # Utility functions and constants
```

### API Client Configuration

- Base client in `src/api/client.ts` uses axios with interceptors
- Request interceptor adds Bearer token from `authStore`
- Response interceptor handles global errors (401 → logout, 403/404/500 → messages)
- Timeout: 10 seconds (configured in `utils/constants.ts`)

### Authentication Flow

1. Login → receives token from backend
2. Token stored in `authStore` (Zustand) and localStorage
3. `apiClient` interceptor adds token to all requests
4. 401 response → clears query cache, logs out, redirects to `/auth/login`
5. `ProtectedRoute` component guards dashboard routes

### Role-Based Access Control

Routes can be protected with `ProtectedRoute` component:
```typescript
<ProtectedRoute allowedRoles={['coach']}>
  <AthletesPage />
</ProtectedRoute>
```

Roles: `coach`, `admin`, `athlete`

### TypeScript Configuration

- Strict mode enabled (`tsconfig.json`)
- No `any` types allowed (`noImplicitAny: true`)
- Path alias `@/*` maps to `src/*`
- Unused locals/parameters not allowed

## Adding a New API Service

1. Define types in `types/entity.types.ts`
2. Create service implementation: `api/services/entityService.ts`
3. Implement CRUD methods using `apiClient` from `@/api/client`
4. Follow REST API patterns (PagedResponse wrapper, JSON:API sorting)

## YooKassa Payment Integration

### Payment Flow

1. User initiates top-up → `TopUpBalanceModal` opens
2. User enters amount → API creates payment → redirects to YooKassa
3. User completes/cancels payment → redirects back to `PaymentResultPage`
4. Frontend polls for payment status until final state

### Payment Statuses

```typescript
type PaymentStatus = 'pending' | 'succeeded' | 'canceled' | 'expired';
```

| Status | Description | UI |
|--------|-------------|-----|
| `pending` | Waiting for payment confirmation | Loading spinner |
| `succeeded` | Payment successful, balance updated | Success result |
| `canceled` | User canceled or payment failed | Error result |
| `expired` | Payment timed out (24h without completion) | Warning result |

### PaymentResultPage Polling

- Polls every 3 seconds for payment status
- Max 20 attempts (1 minute total)
- Stops polling when status is `succeeded`, `canceled`, or `expired`
- Shows timeout message if max attempts reached

### Related Files

- `types/payment.types.ts` — `PaymentStatus` type
- `pages/PaymentResultPage.tsx` — payment result display with polling
- `components/common/TopUpBalanceModal/` — balance top-up modal
- `api/services/balanceService.ts` — payment API calls

## Jira Integration Workflow

When working with Jira tickets via MCP:

1. **Before commenting**: Always propose the comment text to the user first
2. **Comment language**: Write all Jira comments in Russian for QA testers
3. **Comment content**:
   - Focus on business logic and user-facing changes (NOT technical implementation)
   - QA testers don't need to know frontend vs backend details
   - Describe WHAT was fixed in business terms, not HOW it was implemented
   - Include clear testing steps and expected results
4. **Wait for approval**: Display the proposed comment and wait for user confirmation before posting
5. **Only post after "OK"**: Use `mcp__jira__add_comment` only after explicit user approval
6. **Workflow order**: ALWAYS propose Jira comment FIRST, wait for approval, THEN propose Git commit message

**Comment Structure for QA:**
```
Баг исправлен.

*Проблема:*
<Brief description of the issue in business terms>

*Что исправлено:*
<What was fixed from user perspective — business logic changes>

*Для тестирования:*
<Step-by-step testing instructions>

*Ожидаемый результат:*
<Expected behavior after fix>
```

**IMPORTANT**: Never propose Git commit message before Jira comment is approved.

## Git Commit Message Guidelines

**For Jira-tracked bugs:**
```
fix(ARTREVEAL-XXX): <Jira ticket summary>
```
Example: `fix(ARTREVEAL-16): nano-crm Ошибка при удалении телеграм у атлета`

**For non-bug tasks:**
- Follow [Conventional Commits](https://www.conventionalcommits.org/)
- Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`
- Keep description concise and clear

Examples:
```
feat(athletes): add CSV import functionality
refactor(api): simplify error handling in client
chore(deps): update TypeScript to 5.3.0
```

**Process:**
1. Propose commit message to user (display as text)
2. User reviews commit message
3. **User creates commits manually** — do NOT create commits automatically unless explicitly requested

## Important Implementation Rules

1. **UI Language**: All user-facing text in English
2. **No Timestamp Fields**: Do NOT use `createdAt` or `updatedAt` fields
3. **No Console Logs**: Remove all `console.log()` from production code
4. **Route Configuration**: All routes defined in `routes/index.tsx` with lazy loading
5. **Protected Routes**: Wrap authenticated routes with `<ProtectedRoute>`
