# Security — Self-issued JWTs (JJWT style)

Spring Security with service-issued JWTs, Bucket4j rate limiting, and login-attempt protection.

See `spring-boot-gradle-setup/references/security-jjwt.md` for dependency setup.

## Dual SecurityFilterChain

```java
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    @Bean
    @Order(1)
    public SecurityFilterChain actuatorSecurityFilterChain(HttpSecurity http) throws Exception {
        http
            .securityMatcher(EndpointRequest.toAnyEndpoint())
            .csrf(AbstractHttpConfigurer::disable)
            .authorizeHttpRequests(auth -> auth.anyRequest().permitAll());
        return http.build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain apiSecurityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**", "/api/v1/public/**").permitAll()
                .requestMatchers("/swagger-ui.html", "/swagger-ui/**", "/api-docs/**").permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(rateLimitingFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

Filter order: RateLimitingFilter → JwtAuthenticationFilter → PerUserRateLimitingFilter → UsernamePasswordAuthenticationFilter.

`PerUserRateLimitingFilter` is registered **after** `JwtAuthenticationFilter` so the principal is available (see Per-user limiter below).

## Account state

Login is gated on account lifecycle state per `rest-api-design/references/api-security.md`. The User entity carries a state enum; only `ACTIVE` permits token issuance.

```java
public enum AccountState {
    PENDING_VERIFICATION,   // email not confirmed yet
    ACTIVE,                 // normal
    DISABLED                // administratively blocked
}

public class EmailNotVerifiedException extends RuntimeException {
    public EmailNotVerifiedException(String message) { super(message); }
}

public class AccountDisabledException extends RuntimeException {
    public AccountDisabledException(String message) { super(message); }
}
```

Domain-specific states (`SUSPENDED`, `TRIAL_EXPIRED`, etc.) layer on top — each gates login the same way. Handlers for the two exceptions go into `GlobalExceptionHandler` (see Security exceptions below).

## Token delivery — HttpOnly cookie

Per the `rest-api-design` security contract, tokens travel in an `HttpOnly` cookie, never in the response body, never in `localStorage`. This is both the transport to the client on login and the credential read by the filter on subsequent requests.

### Auth controller — issuing and clearing the cookie

```java
@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final LoginAttemptService loginAttemptService;
    private final LoginAttemptProperties loginAttemptProperties;
    private final JwtProperties jwtProperties;

    @PostMapping("/login")
    public ResponseEntity<Void> login(@Valid @RequestBody LoginDto dto,
                                       HttpServletRequest request) {
        String clientIp = RequestUtils.getClientIP(request);
        String email = dto.getEmail();

        // 0. Lockout — applies before any credential work
        if (loginAttemptService.isBlocked(clientIp, email)) {
            throw new AccountTemporarilyLockedException(
                "Too many failed login attempts. Please try again later.",
                loginAttemptProperties.getPerIpEmail().getBlockDurationMinutes() * 60L);
        }

        // 1. Credentials — uniform 401 for wrong-password AND unknown email
        //    (Anti-enumeration — see below; constant-time dummy-hash idiom)
        User user;
        try {
            user = authService.verifyCredentials(dto);
        } catch (AuthenticationException ex) {
            loginAttemptService.recordFailedAttempt(clientIp, email);
            throw ex;   // → 401 UNAUTHORIZED "Invalid credentials"
        }
        loginAttemptService.clearAttempts(clientIp, email);

        // 2. Account state — after credentials; state-specific codes are safe here
        switch (user.getAccountState()) {
            case PENDING_VERIFICATION -> throw new EmailNotVerifiedException(
                "Please verify your email before logging in");
            case DISABLED -> throw new AccountDisabledException(
                "Your account has been disabled");
            case ACTIVE -> { /* continue */ }
        }

        // 3. Issue token
        String token = jwtService.generateToken(user);
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, accessTokenCookie(token).toString())
            .build();
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout() {
        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredAccessTokenCookie().toString())
            .build();
    }

    private ResponseCookie accessTokenCookie(String token) {
        return ResponseCookie.from("access_token", token)
            .httpOnly(true)
            .secure(true)
            .sameSite("Lax")
            .path("/")
            .maxAge(Duration.ofMillis(jwtProperties.getExpirationMs()))
            .build();
    }

    private ResponseCookie expiredAccessTokenCookie() {
        return ResponseCookie.from("access_token", "")
            .httpOnly(true)
            .secure(true)
            .sameSite("Lax")
            .path("/")
            .maxAge(0)
            .build();
    }
}
```

- `HttpOnly` — invisible to JavaScript (XSS mitigation).
- `Secure` — HTTPS only; disable in local dev profile only.
- `SameSite=Lax` — CSRF protection at the browser level.
- Login returns `204 No Content` with `Set-Cookie`; the token is **never** in the response body.
- Logout overwrites the cookie with `maxAge=0`.

### JwtAuthenticationFilter — reading the cookie

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        extractToken(request).ifPresent(token -> {
            try {
                Authentication auth = jwtService.toAuthentication(token);
                SecurityContextHolder.getContext().setAuthentication(auth);
            } catch (JwtException ignored) {
                // invalid/expired token — remains anonymous;
                // authorization step emits 401 on protected endpoints
            }
        });
        chain.doFilter(request, response);
    }

    private Optional<String> extractToken(HttpServletRequest request) {
        Cookie[] cookies = request.getCookies();
        if (cookies == null) return Optional.empty();
        return Arrays.stream(cookies)
            .filter(c -> "access_token".equals(c.getName()))
            .map(Cookie::getValue)
            .findFirst();
    }
}
```

The filter reads only from the cookie — never from an `Authorization` header. Keeping a single source of truth avoids confusion and closes the XSS-via-localStorage path.

## Anti-enumeration patterns

Implementing `rest-api-design/references/api-security.md` anti-enumeration norms on the Spring side.

### Login — constant-time dummy hash for unknown users

The credential-check path MUST take comparable time whether the email exists or not. A naive `findByEmail(email).map(u -> encoder.matches(...)).orElseThrow(...)` short-circuits the BCrypt work for unknown emails — BCrypt takes ~100 ms, the "not found" path returns in ~1 ms. A timing attacker distinguishes the two with a dozen probes.

Hash the provided password against a dummy stored hash when the user doesn't exist:

```java
@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    // Precomputed BCrypt hash of a fixed random string — never matches a real password.
    // Keeps wall-clock comparable between the "user found" and "user not found" branches.
    private static final String DUMMY_HASH =
        "$2a$10$WLgUkItIcxfhPK8FTwDnJe8CVdYqfpqIQBLQ9z5jmAbZMRhYtp3Ci";

    @Override
    public User verifyCredentials(LoginDto dto) {
        User user = userRepository.findByEmailIgnoreCase(dto.getEmail()).orElse(null);
        String storedHash = (user != null) ? user.getPasswordHash() : DUMMY_HASH;

        boolean passwordMatches = passwordEncoder.matches(dto.getPassword(), storedHash);

        if (!passwordMatches || user == null) {
            throw new BadCredentialsException("Invalid credentials");
        }
        return user;
    }
}
```

- The BCrypt call runs in both branches — wall-clock comparable.
- `AuthenticationException` → `GlobalExceptionHandler` emits `401 UNAUTHORIZED` with generic `"Invalid credentials"`. Same code, same body for wrong-password and unknown-email.

### Forgot-password / resend-verification — always-success response

Endpoints that dispatch email based on a user-provided identifier MUST return the same body regardless of whether the identifier exists:

```java
@PostMapping("/forgot-password")
public ResponseEntity<MessageDto> forgotPassword(@Valid @RequestBody ForgotPasswordDto dto) {
    emailTriggerCooldownService.checkAndRecord(dto.getEmail(), "forgot-password");
    passwordResetService.sendResetEmailIfUserExists(dto.getEmail());
    return ResponseEntity.ok(MessageDto.of(
        "If your email is registered, you will receive a password reset link."));
}
```

- The service looks up the user internally, dispatches mail only if found, never signals existence back up.
- The response is byte-identical for known and unknown emails.
- The same pattern applies to `/resend-verification` and any endpoint whose semantic is "send email if we know this address".

## CORS

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(corsAllowedOrigins));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    config.setAllowedHeaders(List.of("Content-Type", "Accept", "Idempotency-Key"));
    config.setExposedHeaders(List.of("X-Total-Count", "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}
```

- `allowCredentials(true)` is required for cookie-based auth — the browser only sends cookies cross-origin when this is set.
- `allowedOrigins` must be an explicit allow-list — `*` is incompatible with credentials.
- `Authorization` is **not** in allowed/exposed headers: auth uses cookies, so there is no `Authorization` header to transmit or read.
- `X-Total-Count` must be exposed so JavaScript can read it (lookup pagination).
- `X-RateLimit-Limit`/`-Remaining`/`-Reset` expose the rate-limit budget on every response — clients throttle proactively instead of reacting to 429 (see Rate Limiting below).
- `Idempotency-Key` is an allowed inbound header for idempotent POST retries (see `references/idempotency.md`).
- Always list allowed headers explicitly under `allowCredentials(true)` — never wildcard `*`.
- `Vary: Origin` is required by the contract when `Allow-Origin` is computed per request from an allow-list. Spring adds it automatically when `allowedOrigins` is a concrete list (not `*`) — no explicit configuration is needed, but verify it is present in actual responses; a reverse proxy that strips or overrides `Vary` breaks cache correctness.

## Rate Limiting (Bucket4j + Caffeine)

### Properties

```java
@ConfigurationProperties(prefix = "app.rate-limiting")
@Data
public class RateLimitingProperties {
    private boolean enabled = true;
    private int defaultRequestsPerMinute = 5;
    private Map<String, EndpointLimit> endpoints = new HashMap<>();
    private PerUser perUser = new PerUser();
    private CacheProperties cache = new CacheProperties();

    public int getRequestsPerMinute(String endpoint) {
        EndpointLimit limit = endpoints.get(endpoint);
        return limit != null ? limit.getRequestsPerMinute() : defaultRequestsPerMinute;
    }

    @Data
    public static class PerUser {
        private boolean enabled = true;
        private int defaultRequestsPerMinute = 60;
        private Map<String, EndpointLimit> groups = new HashMap<>();

        public int getRequestsPerMinute(String group) {
            EndpointLimit limit = groups.get(group);
            return limit != null ? limit.getRequestsPerMinute() : defaultRequestsPerMinute;
        }
    }

    @Data
    public static class EndpointLimit {
        private int requestsPerMinute;
    }

    @Data
    public static class CacheProperties {
        private int expireAfterAccessMinutes = 5;
        private int maximumSize = 10000;
    }
}
```

### Cache config

Cache beans must live in a dedicated `CacheConfig`, **not** in `SecurityConfig`. Placing them in `SecurityConfig` creates a circular dependency:

```
SecurityConfig → RateLimitingFilter → Cache<String, Bucket> → SecurityConfig
```

```java
@Configuration
@RequiredArgsConstructor
public class CacheConfig {

    @Bean
    public Cache<String, Bucket> rateLimitBuckets(RateLimitingProperties props) {
        return Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofMinutes(props.getCache().getExpireAfterAccessMinutes()))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }

    @Bean
    public Cache<String, Bucket> perUserRateLimitBuckets(RateLimitingProperties props) {
        return Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofMinutes(props.getCache().getExpireAfterAccessMinutes()))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }

    @Bean
    public Cache<String, Instant> emailCooldownCache(EmailCooldownProperties props) {
        return Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofSeconds(props.getCooldownSeconds() + 60L))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }

    @Bean
    public Cache<String, Integer> perIpEmailLoginAttempts(LoginAttemptProperties props) {
        return Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofMinutes(props.getPerIpEmail().getBlockDurationMinutes()))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }

    @Bean
    public Cache<String, Integer> perEmailLoginAttempts(LoginAttemptProperties props) {
        return Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofMinutes(props.getPerEmail().getBlockDurationMinutes()))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }
}
```

`SecurityConfig` defines only `SecurityFilterChain` and `PasswordEncoder`.

### Per-endpoint filter (public auth endpoints)

Keys by `{clientIP, endpoint}` — protects unauthenticated endpoints (`/api/v1/auth/**`) before any credential work.

```java
@Component
@RequiredArgsConstructor
public class RateLimitingFilter extends OncePerRequestFilter {

    private final Cache<String, Bucket> buckets;
    private final RateLimitingProperties properties;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        if (!properties.isEnabled()) { chain.doFilter(request, response); return; }
        String endpoint = resolveEndpoint(request.getRequestURI());
        if (endpoint == null) { chain.doFilter(request, response); return; }

        int rpm = properties.getRequestsPerMinute(endpoint);
        String key = RequestUtils.getClientIP(request) + ":" + endpoint;
        Bucket bucket = buckets.get(key, k -> createBucket(rpm));
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        RateLimitHeaders.set(response, rpm, probe);

        if (!probe.isConsumed()) {
            long retryAfter = TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill());
            throw new RateLimitExceededException("Too many requests. Please try again later.", Math.max(1, retryAfter));
        }
        chain.doFilter(request, response);
    }

    private Bucket createBucket(int rpm) {
        return Bucket.builder().addLimit(Bandwidth.simple(rpm, Duration.ofMinutes(1))).build();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/v1/auth/");
    }
}
```

### Per-user filter (protected endpoints)

Keys by `{userId, endpoint-group}` — applies to authenticated requests. Runs **after** `JwtAuthenticationFilter` so the principal is in `SecurityContextHolder`.

```java
@Component
@RequiredArgsConstructor
public class PerUserRateLimitingFilter extends OncePerRequestFilter {

    private final Cache<String, Bucket> perUserRateLimitBuckets;
    private final RateLimitingProperties properties;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                     HttpServletResponse response,
                                     FilterChain chain) throws ServletException, IOException {
        if (!properties.getPerUser().isEnabled()) { chain.doFilter(request, response); return; }

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || "anonymousUser".equals(auth.getPrincipal())) {
            chain.doFilter(request, response);
            return;
        }

        String group = resolveGroup(request);
        if (group == null) { chain.doFilter(request, response); return; }

        UUID userId = ((CustomUserDetails) auth.getPrincipal()).getUserId();
        int rpm = properties.getPerUser().getRequestsPerMinute(group);
        String key = userId + ":" + group;

        Bucket bucket = perUserRateLimitBuckets.get(key, k ->
            Bucket.builder().addLimit(Bandwidth.simple(rpm, Duration.ofMinutes(1))).build());
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        RateLimitHeaders.set(response, rpm, probe);

        if (!probe.isConsumed()) {
            long retryAfter = TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill());
            throw new RateLimitExceededException("Too many requests. Please try again later.", Math.max(1, retryAfter));
        }
        chain.doFilter(request, response);
    }

    private String resolveGroup(HttpServletRequest request) {
        String method = request.getMethod();
        if ("POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method) || "DELETE".equals(method)) {
            return "mutations";
        }
        // Extend with explicit matchers for expensive reads (wide filters, aggregations, bulk lookups).
        return null;   // untracked — no limit
    }
}
```

Register in `SecurityConfig` after `JwtAuthenticationFilter`:

```java
.addFilterAfter(perUserRateLimitingFilter, JwtAuthenticationFilter.class)
```

Group resolution is project-specific. The default `mutations` bucket covers all `POST`/`PUT`/`PATCH`/`DELETE` as a single budget per user; add explicit groups (`expensive-reads`, `admin-ops`) as needs emerge.

### `X-RateLimit-*` response headers

Both filters emit rate-limit headers on **every** response (success AND 429), so clients can throttle proactively. Helper:

```java
public final class RateLimitHeaders {
    private RateLimitHeaders() {}

    public static void set(HttpServletResponse response, int limit, ConsumptionProbe probe) {
        response.setHeader("X-RateLimit-Limit", String.valueOf(limit));
        response.setHeader("X-RateLimit-Remaining", String.valueOf(Math.max(0, probe.getRemainingTokens())));
        response.setHeader("X-RateLimit-Reset",
            String.valueOf(TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill())));
    }
}
```

Already added to CORS `exposedHeaders` above — JavaScript clients can read them cross-origin.

### Email-triggering endpoint cooldown

A third, narrow limiter for endpoints that send email on request (`/auth/forgot-password`, `/auth/resend-verification`). Keys by `{email, endpoint}` — blocks email-bombing from IP rotation.

```java
@Service
@RequiredArgsConstructor
public class EmailTriggerCooldownService {

    private final Cache<String, Instant> emailCooldownCache;
    private final EmailCooldownProperties properties;

    /**
     * Records a request. Silently succeeds when within cooldown — surfacing an error
     * would leak "this email has activity" (anti-enumeration).
     */
    public boolean checkAndRecord(String email, String endpoint) {
        String key = email.toLowerCase() + ":" + endpoint;
        Instant last = emailCooldownCache.getIfPresent(key);
        if (last != null && Duration.between(last, Instant.now()).getSeconds() < properties.getCooldownSeconds()) {
            return false;   // within cooldown — caller skips the email dispatch
        }
        emailCooldownCache.put(key, Instant.now());
        return true;
    }
}

@ConfigurationProperties(prefix = "app.email-cooldown")
@Data
public class EmailCooldownProperties {
    private long cooldownSeconds = 60;
    private CacheProperties cache = new CacheProperties();

    @Data
    public static class CacheProperties {
        private int maximumSize = 10_000;
    }
}
```

Used in `AuthController` on every email-dispatching endpoint:

```java
@PostMapping("/forgot-password")
public ResponseEntity<MessageDto> forgotPassword(@Valid @RequestBody ForgotPasswordDto dto) {
    if (emailTriggerCooldownService.checkAndRecord(dto.getEmail(), "forgot-password")) {
        passwordResetService.sendResetEmailIfUserExists(dto.getEmail());
    }
    // Always same response — cooldown hits and cache misses are indistinguishable to the client.
    return ResponseEntity.ok(MessageDto.of(
        "If your email is registered, you will receive a password reset link."));
}
```

The dispatch is skipped on cooldown; the response stays identical — consistent with Anti-enumeration.

## Login Attempt Protection (Caffeine)

Two independent counters defend against two distinct attack shapes: single-source brute-force and distributed brute-force.

| Counter | Key | Threshold | Block | Attack defeated |
|---|---|---|---|---|
| Per IP-email | `{ip}:{email.toLowerCase()}` | 5 failures / 15 min | 15-min cooldown on this IP for this email | Typos, single-source brute-force, Account Lockout Attack |
| Per email | `{email.toLowerCase()}` | 20 failures / 1 h | 1-h cooldown on this email, any IP + owner notified | Distributed brute-force (botnet, VPN rotation) |

Both thresholds check in `isBlocked`; both counters increment on every failure; both clear on successful login.

```java
@Service
@RequiredArgsConstructor
public class LoginAttemptServiceImpl implements LoginAttemptService {

    private final Cache<String, Integer> perIpEmailLoginAttempts;
    private final Cache<String, Integer> perEmailLoginAttempts;
    private final LoginAttemptProperties properties;
    private final NotificationService notificationService;

    @Override
    public boolean isBlocked(String ip, String email) {
        if (!properties.isEnabled()) return false;
        String e = email.toLowerCase();
        return perIpEmailLoginAttempts.get(ip + ":" + e, k -> 0) >= properties.getPerIpEmail().getMaxAttempts()
            || perEmailLoginAttempts.get(e, k -> 0) >= properties.getPerEmail().getMaxAttempts();
    }

    @Override
    public void recordFailedAttempt(String ip, String email) {
        if (!properties.isEnabled()) return;
        String e = email.toLowerCase();
        int ipCount = increment(perIpEmailLoginAttempts, ip + ":" + e);
        int emailCount = increment(perEmailLoginAttempts, e);

        // Notify the account owner the first time the email-global threshold is crossed —
        // not on every subsequent failure while still blocked.
        if (emailCount == properties.getPerEmail().getMaxAttempts()) {
            notificationService.notifySuspiciousActivity(e);
        }
    }

    @Override
    public void clearAttempts(String ip, String email) {
        if (!properties.isEnabled()) return;
        String e = email.toLowerCase();
        perIpEmailLoginAttempts.invalidate(ip + ":" + e);
        perEmailLoginAttempts.invalidate(e);
    }

    private static int increment(Cache<String, Integer> cache, String key) {
        int next = cache.get(key, k -> 0) + 1;
        cache.put(key, next);
        return next;
    }
}
```

`notificationService.notifySuspiciousActivity(email)` is the project's email hook — emails the owner "someone is attempting to log into your account from multiple IPs; if this wasn't you, change your password immediately". The notification service itself is out of scope for this reference — wire to your existing mailer. Fire-and-forget; a failed email MUST NOT break the login path.

## Persisted secret hashing

Tokens stored server-side — refresh tokens, password-reset tokens, email-verification tokens — MUST be stored hashed per the contract. SHA-256 is sufficient: tokens are high-entropy (≥128 bits), so offline brute-force against the hash is infeasible. A password-hashing function (BCrypt, Argon2) is unnecessary here and actively wrong — passwords need it, random tokens don't.

```java
public final class TokenHashUtil {
    private TokenHashUtil() {}

    /** URL-safe random token — 512 bits of entropy. */
    public static String generateToken() {
        byte[] bytes = new byte[64];
        new SecureRandom().nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    /** SHA-256 → Base64. Stored, never the plaintext. */
    public static String hash(String token) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(token.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
```

Usage pattern:

```java
// Issue side
String plaintext = TokenHashUtil.generateToken();
entity.setTokenHash(TokenHashUtil.hash(plaintext));
repository.save(entity);
return plaintext;                // to client (cookie, email link)

// Redemption side
String incoming = request.getParameter("token");
TokenEntity found = repository.findByTokenHash(TokenHashUtil.hash(incoming))
    .orElseThrow(() -> new ResourceNotFoundException("Invalid or expired token"));
```

**Passwords are the exception** — use the configured `PasswordEncoder` (BCrypt). See Anti-enumeration above for the dummy-hash idiom on the credential-check path.

`TokenHashUtil` is the building block for the refresh-token flow (see `references/refresh-tokens.md`) and any other server-persisted token (password-reset, email-verification).

## Client IP detection

Never read `X-Forwarded-For` / `X-Real-IP` from the application code directly — those headers can be set by any client and would let an attacker forge the IP used as the rate-limit / brute-force key (see `rest-api-design/references/api-security.md`).

Let Tomcat resolve the real client IP via `RemoteIpValve`, driven by a config-level allow-list of trusted proxies. `request.getRemoteAddr()` then returns the forged-proof value — the forwarded-header IP when the request arrives from a trusted proxy, the TCP peer address otherwise.

### application.yml

```yaml
server:
  forward-headers-strategy: native      # enables Tomcat RemoteIpValve
  tomcat:
    remoteip:
      remote-ip-header: X-Forwarded-For
      # CIDR regex of your reverse proxies (nginx / ELB / k8s ingress).
      # Requests from outside this range have their X-Forwarded-For ignored.
      internal-proxies: "10\\.\\d+\\.\\d+\\.\\d+|172\\.(1[6-9]|2\\d|3[01])\\.\\d+\\.\\d+|192\\.168\\.\\d+\\.\\d+"
```

Replace `internal-proxies` with the concrete CIDR(s) of your actual proxies — the RFC 1918 default shown above is only safe when the app is reachable solely through the proxy network.

### RequestUtils

```java
public class RequestUtils {
    public static String getClientIP(HttpServletRequest request) {
        return request.getRemoteAddr();
    }
}
```

No manual header reading — `RemoteIpValve` has already normalised `getRemoteAddr()` to the real client IP. Configure the reverse proxy to always **overwrite** (never forward) `X-Forwarded-For` from untrusted clients.

## Security exception classes

Both 429 exceptions carry `retryAfterSeconds` — the handler uses it for the `Retry-After` response header.

```java
public class RateLimitExceededException extends RuntimeException {
    private final long retryAfterSeconds;

    public RateLimitExceededException(String message, long retryAfterSeconds) {
        super(message);
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public long getRetryAfterSeconds() { return retryAfterSeconds; }
}

public class AccountTemporarilyLockedException extends RuntimeException {
    private final long retryAfterSeconds;

    public AccountTemporarilyLockedException(String message, long retryAfterSeconds) {
        super(message);
        this.retryAfterSeconds = retryAfterSeconds;
    }

    public long getRetryAfterSeconds() { return retryAfterSeconds; }
}
```

`AccountTemporarilyLockedException` is thrown by the auth controller using the configured block duration:

```java
if (loginAttemptService.isBlocked(clientIp, email)) {
    throw new AccountTemporarilyLockedException(
        "Too many failed login attempts. Please try again later.",
        loginAttemptProperties.getBlockDurationMinutes() * 60L
    );
}
```

## Security exceptions in GlobalExceptionHandler

```java
@ExceptionHandler(AuthenticationException.class)
@ResponseStatus(HttpStatus.UNAUTHORIZED)
public ErrorDto handleAuth(AuthenticationException ex) {
    return ErrorDto.builder().code("UNAUTHORIZED").message("Invalid credentials").build();
}

@ExceptionHandler(AccessDeniedException.class)
@ResponseStatus(HttpStatus.FORBIDDEN)
public ErrorDto handleAccessDenied(AccessDeniedException ex) {
    return ErrorDto.builder().code("FORBIDDEN").message("Access denied").build();
}

@ExceptionHandler(RateLimitExceededException.class)
public ResponseEntity<ErrorDto> handleRateLimit(RateLimitExceededException ex) {
    return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
        .header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()))
        .body(ErrorDto.builder().code("TOO_MANY_REQUESTS").message(ex.getMessage()).build());
}

@ExceptionHandler(AccountTemporarilyLockedException.class)
public ResponseEntity<ErrorDto> handleAccountLocked(AccountTemporarilyLockedException ex) {
    return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
        .header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()))
        .body(ErrorDto.builder().code("ACCOUNT_TEMPORARILY_LOCKED").message(ex.getMessage()).build());
}

@ExceptionHandler(EmailNotVerifiedException.class)
@ResponseStatus(HttpStatus.FORBIDDEN)
public ErrorDto handleEmailNotVerified(EmailNotVerifiedException ex) {
    return ErrorDto.builder().code("EMAIL_NOT_VERIFIED").message(ex.getMessage()).build();
}

@ExceptionHandler(AccountDisabledException.class)
@ResponseStatus(HttpStatus.FORBIDDEN)
public ErrorDto handleAccountDisabled(AccountDisabledException ex) {
    return ErrorDto.builder().code("ACCOUNT_DISABLED").message(ex.getMessage()).build();
}
```

## YAML config

```yaml
app:
  jwt:
    secret: ${APP_JWT_SECRET}           # min 256-bit key
    expiration-ms: 86400000             # 24 hours
    refresh-expiration-ms: 2592000000   # 30 days

  rate-limiting:
    enabled: true
    default-requests-per-minute: 5
    endpoints:
      login:
        requests-per-minute: 30
      register:
        requests-per-minute: 3
      forgot-password:
        requests-per-minute: 3
      resend-verification:
        requests-per-minute: 3
    per-user:
      enabled: true
      default-requests-per-minute: 60
      groups:
        mutations:
          requests-per-minute: 60
        expensive-reads:
          requests-per-minute: 20
    cache:
      expire-after-access-minutes: 5
      maximum-size: 10000

  email-cooldown:
    cooldown-seconds: 60
    cache:
      maximum-size: 10000

  login-attempt:
    enabled: true
    per-ip-email:
      max-attempts: 5
      block-duration-minutes: 15
    per-email:
      max-attempts: 20
      block-duration-minutes: 60
    cache:
      maximum-size: 10000
```

`LoginAttemptProperties` matches this shape:

```java
@ConfigurationProperties(prefix = "app.login-attempt")
@Data
public class LoginAttemptProperties {
    private boolean enabled = true;
    private Threshold perIpEmail = new Threshold(5, 15);
    private Threshold perEmail = new Threshold(20, 60);
    private CacheProperties cache = new CacheProperties();

    @Data @AllArgsConstructor @NoArgsConstructor
    public static class Threshold {
        private int maxAttempts;
        private int blockDurationMinutes;
    }

    @Data
    public static class CacheProperties {
        private int maximumSize = 10000;
    }
}
```
