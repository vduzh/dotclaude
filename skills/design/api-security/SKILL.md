---
name: api-security
description: REST API security design — stateless authentication, rate limiting with IP:endpoint key, brute-force protection with IP:email key, cookie-based tokens
---

# REST API Security Design

Apply these patterns when designing security for stateless REST APIs.

## Stateless Authentication

REST APIs must be stateless — no server-side sessions:
- No session cookies, no session storage
- CSRF protection disabled (no session to hijack)
- Each request carries its own credentials (token)

## Token Storage: HttpOnly Cookies

Store tokens in **HttpOnly cookies**, not in localStorage or response body:

```
Set-Cookie: access_token=eyJ...; HttpOnly; Secure; SameSite=Lax; Path=/
```

| Flag | Purpose |
|------|---------|
| `HttpOnly` | Prevents JavaScript access (XSS protection) |
| `Secure` | Only sent over HTTPS (disable for localhost dev) |
| `SameSite=Lax` | CSRF protection (allows same-site navigation) |

**Why not localStorage?** XSS vulnerability — any injected script can read localStorage. HttpOnly cookies are invisible to JavaScript.

**Why not response body?** Frontend would need to store the token somewhere (localStorage, memory), losing HttpOnly protection.

## Rate Limiting

Protect public endpoints (login, register, forgot-password) from abuse.

**Algorithm:** Token Bucket — allows burst traffic while enforcing average rate.

**Key:** `{clientIP}:{endpoint}` — separate limits per IP per endpoint.

```
IP 1.2.3.4 calling /login   → bucket "1.2.3.4:login"   (30 req/min)
IP 1.2.3.4 calling /register → bucket "1.2.3.4:register" (3 req/min)
```

**Response when exceeded:** `429 Too Many Requests`

```json
{ "code": "TOO_MANY_REQUESTS", "message": "Rate limit exceeded" }
```

**Client IP detection** behind proxies — check headers in order:
1. `X-Forwarded-For` (first IP in comma-separated list)
2. `X-Real-IP`
3. `request.getRemoteAddr()` (fallback)

## Brute-Force Protection

Separate from rate limiting — tracks **failed login attempts** per IP+email combination.

**Key:** `{clientIP}:{email}` — blocks specific IP+account combination after N failed attempts.

```
IP 1.2.3.4 + john@example.com → 5 failures → blocked for 15 min
IP 5.6.7.8 + john@example.com → not blocked (different IP)
```

**Why IP:email, not just email?** Prevents **Account Lockout Attack** — attacker can only block their own IP's access to victim's account, not the victim's access from their IP.

**Response when blocked:** `429 Too Many Requests`

```json
{ "code": "ACCOUNT_TEMPORARILY_LOCKED", "message": "Too many failed attempts. Try again in 15 minutes" }
```

**Flow:**
1. Check if `IP:email` is blocked → if yes, reject immediately
2. Attempt authentication
3. On failure → increment counter
4. On success → clear counter

## Endpoint Classification

| Category | Auth Required | Rate Limited | Examples |
|----------|:------------:|:------------:|---------|
| Public | No | Yes | `/auth/login`, `/auth/register`, `/auth/forgot-password` |
| Health/Docs | No | No | `/`, `/swagger-ui.html`, `/api-docs` |
| Protected | Yes | No | `/api/v1/customers`, `/api/v1/profiles` |
| Admin | Yes (admin role) | No | `/api/v1/admin/*` |
