# API Security Design

Stateless authentication, token storage, rate limiting, and brute-force protection patterns.

## Scope

This contract is written for **browser-based clients** — cookies, `SameSite`, CORS all assume a browser on the other end. Non-browser clients (mobile apps, CLI tools, server-to-server) use `Authorization: Bearer <token>` with an equivalent token payload — HttpOnly-cookie storage doesn't apply there, and the CSRF/XSS threat model differs. Supporting non-browser clients from the same API is possible but out of scope here; define separately when needed.

## Transport: HTTPS only

All endpoints MUST be served over TLS. Plain-HTTP requests MUST be redirected to `https://` or rejected at the edge (load balancer, reverse proxy). The `Secure` cookie flag is load-bearing — without TLS, the access-token cookie travels in plaintext and the whole auth story collapses.

No `http://` in production. Local dev (`localhost`) may use plain HTTP with the `Secure` flag disabled in that profile only.

## Stateless authentication

REST APIs must be stateless:
- No server-side sessions, no session cookies
- No server-side CSRF tokens — browser-level CSRF protection comes from `SameSite=Lax` on the cookie (see Token storage below)
- Each request carries its own credentials (token)

**CSRF protection rests entirely on `SameSite=Lax`.** This is sufficient only because the contract requires `GET` (and other safe methods) to have no side effects — a rule already enforced by the REST conventions in this skill. `Lax` blocks cross-site `POST`/`PUT`/`PATCH`/`DELETE` at the browser level. If the API ever adopts side-effecting safe methods (don't), add explicit CSRF tokens as defence-in-depth.

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

## Persisted secrets

Any authentication token persisted on the server — refresh tokens, password-reset tokens, email-verification tokens, API keys — MUST be stored as a hash, not plaintext. The client receives the plaintext value once (cookie, email link); the server stores `hash(token)` and looks up by hashing the incoming value.

- **Algorithm:** a secure one-way hash — SHA-256 or stronger. A password-hashing function (bcrypt, argon2) is unnecessary here — tokens are high-entropy (≥128 bits of random), so offline brute-force against the hash is infeasible even with a fast hash.
- **Entropy:** tokens MUST carry at least **128 bits** of cryptographic entropy (e.g. 32+ random bytes). Short tokens are guessable over the wire before storage compromise even enters the picture.
- **Lookup:** client presents the plaintext → server hashes → finds the row by `token_hash`.
- **Why:** a DB dump, backup leak, or SQL injection must not hand an attacker usable session material. The wire stays simple (plaintext cookie/body); the storage stays safe.

**Passwords are the distinct case** — use a password-hashing function (bcrypt, argon2) with per-record salt and adaptive cost, not SHA-256. Passwords are low-entropy and require the cost factor to resist offline brute-force.

## Rate limiting

Two independent limiters apply together — a per-IP limiter on public endpoints to stop abuse before auth, and a per-user limiter on protected endpoints to stop abuse after auth.

| Limiter | Key | Applies to | Typical limits |
|---|---|---|---|
| **Per-IP** | `{clientIP}:{endpoint}` | Public endpoints (login, register, forgot-password) | 3–30 req/min depending on endpoint |
| **Per-user** | `{userId}:{endpoint-group}` | Protected endpoints, authenticated clients | A single mutations budget per user + dedicated quotas for expensive reads |

**Behavior:** short bursts allowed above the steady-state rate; sustained rate enforced over a rolling window (token-bucket style).

### Per-IP example

```
1.2.3.4 + /login    → 30 req/min
1.2.3.4 + /register →  3 req/min
```

### Per-user rationale

Per-user scope solves two gaps that pure per-IP limits leave open:

1. **Shared-IP collision** (NAT, corporate networks, public wifi) — thousands of unrelated users behind one IP don't block each other.
2. **Authenticated abuse** — a logged-in client can still hammer `POST /customers`, `POST /orders`, or expensive reads; per-IP limits on protected endpoints are typically too generous to catch this.

At minimum, rate-limit mutation verbs (`POST`/`PUT`/`PATCH`/`DELETE`) as a single budget per user, plus dedicated quotas for heavy reads (large `limit=`, complex filters, bulk lookups).

### Email-triggering endpoints

Endpoints that dispatch email on a client's request — `POST /auth/forgot-password`, `POST /auth/resend-verification`, any "email me a link" — need a third limiter on top of per-IP and per-user: a **per-`{email, endpoint}` cooldown**, a minimum interval between successive requests targeting the same email on the same endpoint.

- Typical cooldown: **60 seconds**.
- Scope: per `{email, endpoint}` — different endpoints do not share the cooldown.
- On exceed: `429 Too Many Requests` with `Retry-After`. The response MUST also obey Anti-enumeration (below) — the error cannot reveal whether the email is registered.

Without this limiter, an attacker or a buggy client can flood the victim's inbox via the server — per-IP rate limits don't stop this because the attacker rotates IPs while the victim's mailbox fills up.

### Response headers

Every response on a rate-limited endpoint — both success and 429 — includes:

```
X-RateLimit-Limit:     30
X-RateLimit-Remaining: 12
X-RateLimit-Reset:     45
```

- `Limit` — the ceiling that applies to this request.
- `Remaining` — requests left in the current window.
- `Reset` — seconds until the window resets.

Well-behaved clients throttle before reaching zero; naive clients react to 429. Expose these headers in CORS `Access-Control-Expose-Headers` alongside `X-Total-Count`.

### 429 response

`429 Too Many Requests` with `Retry-After: <seconds>` header + `{"code": "TOO_MANY_REQUESTS", ...}` body.

### Client IP detection (behind proxies)

Check in order:
1. `X-Forwarded-For` first IP — **trust only when the request arrives from a known proxy**; accepting this header from arbitrary clients allows IP spoofing and rate-limit bypass.
2. `X-Real-IP` — same trust constraint as `X-Forwarded-For`.
3. Remote peer address (socket-level client IP) — always trustworthy.

## Brute-force protection

Two thresholds apply in parallel — the first catches typos and single-source brute-force, the second stops distributed attacks that rotate IPs.

| Key | Threshold | Effect | Protects against |
|---|---|---|---|
| `{clientIP}:{email}` | 5 failures / 15 min | `429 ACCOUNT_TEMPORARILY_LOCKED` | Typos, misplaced credentials, single-source brute-force |
| `{email}` (any IP) | 20 failures / 1 h | `429 ACCOUNT_TEMPORARILY_LOCKED` + notify the account owner | Distributed brute-force (botnet, VPN rotation) |

The `{clientIP, email}` key prevents an **Account Lockout Attack** — an attacker cannot lock a victim out from the victim's own IP. The broader `{email}` ceiling prevents an attacker rotating IPs from grinding the password indefinitely.

```
1.2.3.4 + john@example.com → 5 failures → blocked 15 min (IP+email)
5.6.7.8 + john@example.com → not blocked under IP+email key
...but 20 failures across any mix of IPs on the same email
   → account-wide cooldown + email alert to the owner
```

**Response:** `429 Too Many Requests` with `Retry-After: <seconds until lockout expires>` header + `{"code": "ACCOUNT_TEMPORARILY_LOCKED", ...}` body.

**Flow:** check if blocked → attempt auth → on failure increment both counters → on success clear both counters.

## Account state

Accounts carry a lifecycle state that gates authentication. Minimum states:

| State | Meaning | Login permitted? |
|---|---|---|
| `PENDING_VERIFICATION` | Registration succeeded; email not yet confirmed | No |
| `ACTIVE` | Normal state | Yes |
| `DISABLED` | Administratively blocked | No |

Additional domain states (`SUSPENDED`, `ARCHIVED`, `TRIAL_EXPIRED`, etc.) live in the business layer and are out of scope here — but the same gate rule applies: **a token is issued only from `ACTIVE`**.

### Login gating

Order of checks on `POST /auth/login`:

1. **Credentials** — if wrong: `401 UNAUTHORIZED` with a generic message (see Anti-enumeration). The response does NOT depend on whether the account exists.
2. **State** — if credentials correct but the account is not `ACTIVE`:
   - `PENDING_VERIFICATION` → `403 FORBIDDEN`, code `EMAIL_NOT_VERIFIED`.
   - `DISABLED` → `403 FORBIDDEN`, code `ACCOUNT_DISABLED`.

State-specific error codes are safe **only after** the credential check — knowing the password already defeats the enumeration concern on this path. Never reveal state on a credential-failure response.

## Anti-enumeration

Unauthenticated endpoints that touch account existence MUST NOT let a client learn whether an account exists. Same response body, same status code, and comparable timing for "account exists" and "account does not exist".

| Endpoint | Pattern |
|---|---|
| `POST /auth/login` (wrong credentials) | `401 UNAUTHORIZED`, `{"code": "UNAUTHORIZED", "message": "Invalid credentials"}` — **same for wrong-password and no-such-user** |
| `POST /auth/forgot-password` | Always `200 OK` with generic body (e.g. "If your email is registered, you will receive a password reset link") — regardless of whether the email is in the DB |
| `POST /auth/resend-verification` | Always `200 OK` with generic body — regardless of email existence or current verification state |
| `GET /users/by-email/{email}` (unauthenticated) | `401 UNAUTHORIZED` (auth required); never leak existence via 404 vs 200 |

### Constant-time behavior

Uniform response bodies are not enough — response **time** must also be uniform. A timing-attacker can distinguish:

- Real password hash compared (~100 ms with bcrypt) vs short-circuit "user not found" (~1 ms).
- DB SELECT hit (returns a row) vs miss (returns empty quickly).

Mitigation: perform the work even when the account doesn't exist — hash the provided password against a dummy hash, execute any downstream steps that would otherwise short-circuit. The wall-clock response time must carry no signal about account existence.

### Scope

Anti-enumeration applies to **unauthenticated** endpoints. Authenticated domain endpoints (`GET /customers/by-email/{email}` called by a logged-in user) MAY and SHOULD return `404 NOT_FOUND` for missing entities — hiding domain data from a legitimate user would break the API.

## Logout

Logout clears the cookie:

```
Set-Cookie: access_token=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0
```

The browser drops the cookie immediately.

The underlying JWT remains technically valid server-side until its expiration (see Out of specification — token revocation). In the browser context this is not observable: `HttpOnly` prevents JavaScript from ever holding the token outside the cookie jar, so clearing the cookie is equivalent to invalidating the client's access. The gap only matters if the same token is extracted elsewhere (server logs, XSS-with-CSRF, exfiltration) — which is what `HttpOnly` + `Secure` exist to prevent.

## CORS — cookie-based cross-origin auth

Cookie-based auth across origins requires these headers on every response:

```
Access-Control-Allow-Origin:      https://app.example.com
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers:    X-Total-Count, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
Vary:                             Origin
```

| Header | Purpose |
|--------|---------|
| `Access-Control-Allow-Origin` | Must be a **specific origin** — `*` is incompatible with credentials. Multiple origins require per-request matching against an allow-list. |
| `Access-Control-Allow-Credentials: true` | Enables cookie transmission across origins; without it, the browser drops the cookie from the request. |
| `Access-Control-Expose-Headers` | Custom response headers the client reads — `X-Total-Count` (lookup pagination), `X-RateLimit-*` (rate budget), plus any other custom headers the API emits. |
| `Vary: Origin` | Required when `Allow-Origin` is computed per-request from an allow-list — prevents client/CDN caches from serving an origin-A response back to origin B (cache-poisoning). |

Preflight (`OPTIONS`) must be handled for non-simple methods (PUT / PATCH / DELETE, or POST with `Content-Type: application/json`) — respond with the same allow-origin / credentials headers plus `Access-Control-Allow-Methods` and `Access-Control-Allow-Headers`.

## Endpoint classification

| Category | Auth required | Per-IP rate limit | Per-user rate limit | Examples |
|----------|:---:|:---:|:---:|---------|
| Public | No | Yes | — | `/auth/login`, `/auth/register`, `/auth/forgot-password` |
| Health/Docs | No | No | — | `/`, `/swagger-ui.html`, `/api-docs` |
| Protected | Yes | No | Yes (mutations + expensive reads) | `/api/v1/customers`, `/api/v1/orders` |
| Admin | Yes (admin role) | No | Yes | `/api/v1/admin/*` |

## Out of specification

**Token refresh:** whether to implement a refresh-token flow is not mandated — a long-lived access token without refresh (e.g. 24h JWT) is one option; short-lived access tokens paired with a refresh cookie is another. Either is contract-compliant. Introduce a dedicated section when the access-token lifetime is short enough to need renewal mid-session.

If refresh tokens are implemented, they MUST follow these invariants:

1. **Scope-limited cookie.** The refresh cookie is set with `Path=/api/v1/auth` (or the actual auth-endpoint prefix) — the browser never sends it to product endpoints, reducing the attack surface for exfiltration. The access-token cookie stays at `Path=/`.
2. **Rotation on every use.** Each successful refresh issues a new refresh token and revokes the presented one. The new token is independent — not a derivation of the old.
3. **Family revocation on reuse.** The server records the chain of rotations (each token knows its predecessor). If a client presents a token that has already been rotated (revoked) — a sure sign of theft and replay — the server treats it as compromise and revokes the **entire family**. Both attacker and legitimate user are forced to re-authenticate; the attack window closes.
4. **Server-side revocation on logout.** Logout revokes the refresh token in storage, not only clears the cookie — an exfiltrated refresh token becomes unusable the moment the user logs out.
5. **Hashed storage.** Per Persisted secrets — refresh tokens live in the DB as hashes, never plaintext.

**Token revocation:** a valid JWT remains usable until its expiration — the server has no mechanism to invalidate individual tokens mid-session (password change, account compromise, employee offboarding). The mitigation relies on a bounded access-token lifetime (e.g. 24h) plus periodic refresh. If immediate revocation becomes a business requirement, introduce a server-side blocklist (a `revoked_tokens` table consulted on every authenticated request) — not specified here.

**Non-browser clients:** mobile apps, CLI tools, and server-to-server flows. These use `Authorization: Bearer <token>` with an equivalent token payload; HttpOnly cookies, `SameSite`, and CORS do not apply. Specify separately when a concrete client class needs to be supported.
