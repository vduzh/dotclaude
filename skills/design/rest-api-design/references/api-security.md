# API Security Design

Stateless authentication, token storage, rate limiting, and brute-force protection patterns.

## Stateless authentication

REST APIs must be stateless:
- No server-side sessions, no session cookies
- CSRF protection disabled (no session to hijack)
- Each request carries its own credentials (token)

## Token storage: HttpOnly cookies

Store tokens in HttpOnly cookies, not localStorage or response body:

```
Set-Cookie: access_token=eyJ...; HttpOnly; Secure; SameSite=Lax; Path=/
```

| Flag | Purpose |
|------|---------|
| `HttpOnly` | Prevents JavaScript access (XSS protection) |
| `Secure` | HTTPS only (disable for localhost dev) |
| `SameSite=Lax` | CSRF protection via same-site policy |

localStorage is vulnerable to XSS — any injected script can read it. HttpOnly cookies are invisible to JavaScript.

## Rate limiting

Protect public endpoints (login, register, forgot-password) from abuse.

**Algorithm:** Token Bucket — allows burst traffic while enforcing average rate.

**Key:** `{clientIP}:{endpoint}` — separate limits per IP per endpoint:

```
1.2.3.4 + /login    → 30 req/min
1.2.3.4 + /register → 3 req/min
```

**Response:** `429 Too Many Requests` + `{"code": "TOO_MANY_REQUESTS", ...}`

**Client IP detection** (behind proxies — check in order):
1. `X-Forwarded-For` first IP
2. `X-Real-IP`
3. `request.getRemoteAddr()`

## Brute-force protection

**Key:** `{clientIP}:{email}` — blocks specific IP+account combination after N failed attempts.

```
1.2.3.4 + john@example.com → 5 failures → blocked 15 min
5.6.7.8 + john@example.com → not blocked (different IP)
```

IP:email key (not just email) prevents Account Lockout Attack — attacker can only block their own IP's access, not the victim's access from their IP.

**Response:** `429 Too Many Requests` + `{"code": "ACCOUNT_TEMPORARILY_LOCKED", ...}`

**Flow:** check if blocked → attempt auth → on failure increment counter → on success clear counter.

## Endpoint classification

| Category | Auth required | Rate limited | Examples |
|----------|:---:|:---:|---------|
| Public | No | Yes | `/auth/login`, `/auth/register`, `/auth/forgot-password` |
| Health/Docs | No | No | `/`, `/swagger-ui.html`, `/api-docs` |
| Protected | Yes | No | `/api/v1/customers`, `/api/v1/profiles` |
| Admin | Yes (admin role) | No | `/api/v1/admin/*` |
