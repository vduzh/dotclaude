# Security — Self-issued JWTs

Spring Security with service-issued JWTs, HttpOnly cookies, account-state gating, anti-enumeration, login-attempt protection, and CORS.

Implements the security contract from `the `rest-api-design` skill`.

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
            .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
```

Rate-limiting filters are registered here when enabled — see `references/rate-limiting.md`.

## Account state

Login gated on lifecycle state per `the `rest-api-design` skill`. Only `ACTIVE` permits token issuance.

```java
public enum AccountState {
    PENDING_VERIFICATION,
    ACTIVE,
    DISABLED
}
```

## Token delivery — HttpOnly cookie

Tokens travel in `HttpOnly` cookies, never in the response body or `Authorization` header.

### Auth controller

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

        if (loginAttemptService.isBlocked(clientIp, email)) {
            throw new AccountTemporarilyLockedException(
                "Too many failed login attempts. Please try again later.",
                loginAttemptProperties.getPerIpEmail().getBlockDurationMinutes() * 60L);
        }

        User user;
        try {
            user = authService.verifyCredentials(dto);
        } catch (AuthenticationException ex) {
            loginAttemptService.recordFailedAttempt(clientIp, email);
            throw ex;
        }
        loginAttemptService.clearAttempts(clientIp, email);

        switch (user.getAccountState()) {
            case PENDING_VERIFICATION -> throw new EmailNotVerifiedException(
                "Please verify your email before logging in");
            case DISABLED -> throw new AccountDisabledException(
                "Your account has been disabled");
            case ACTIVE -> { /* continue */ }
        }

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
            .httpOnly(true).secure(true).sameSite("Lax").path("/").maxAge(0)
            .build();
    }
}
```

Login returns `204 No Content` with `Set-Cookie` — token never in body. Logout overwrites with `maxAge=0`.

### JwtAuthenticationFilter

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
                // invalid/expired — remains anonymous
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

Reads only from cookie — never from `Authorization` header.

## Anti-enumeration

Implements `the `rest-api-design` skill` anti-enumeration norms.

### Login — constant-time dummy hash

```java
@Service
@RequiredArgsConstructor
public class AuthServiceImpl implements AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

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

BCrypt runs in both branches — wall-clock comparable.

### Forgot-password / resend-verification — always-success

```java
@PostMapping("/forgot-password")
public ResponseEntity<MessageDto> forgotPassword(@Valid @RequestBody ForgotPasswordDto dto) {
    passwordResetService.sendResetEmailIfUserExists(dto.getEmail());
    return ResponseEntity.ok(MessageDto.of(
        "If your email is registered, you will receive a password reset link."));
}
```

Response is byte-identical for known and unknown emails.

## CORS

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(corsAllowedOrigins));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    config.setAllowedHeaders(List.of("Content-Type", "Accept", "Idempotency-Key"));
    config.setExposedHeaders(List.of("X-Total-Count", "X-RateLimit-Limit",
        "X-RateLimit-Remaining", "X-RateLimit-Reset"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}
```

- `allowCredentials(true)` — required for cookie-based auth.
- `allowedOrigins` — explicit allow-list, never `*`.
- `Authorization` not listed — auth uses cookies.
- `Vary: Origin` added automatically by Spring when `allowedOrigins` is a concrete list.

## Login Attempt Protection

Two counters per `the `rest-api-design` skill`:

| Counter | Key | Threshold | Block |
|---|---|---|---|
| Per IP-email | `{ip}:{email}` | 5 / 15 min | 15-min cooldown |
| Per email | `{email}` | 20 / 1 h | 1-h cooldown + owner notified |

```java
@Service
@RequiredArgsConstructor
public class LoginAttemptServiceImpl implements LoginAttemptService {

    private final Cache<String, Integer> perIpEmailLoginAttempts;
    private final Cache<String, Integer> perEmailLoginAttempts;
    private final LoginAttemptProperties properties;

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
        increment(perIpEmailLoginAttempts, ip + ":" + e);
        int emailCount = increment(perEmailLoginAttempts, e);
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

### Cache beans

Login attempt caches live in a dedicated `CacheConfig` — **not** in `SecurityConfig` (avoids circular dependency).

```java
@Configuration
@RequiredArgsConstructor
public class CacheConfig {

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

Rate-limiting cache beans also go here — see `references/rate-limiting.md`.

## Persisted secret hashing

Tokens stored server-side (refresh, password-reset, email-verification) — stored hashed. SHA-256 is sufficient for high-entropy tokens.

```java
public final class TokenHashUtil {
    private TokenHashUtil() {}

    public static String generateToken() {
        byte[] bytes = new byte[64];
        new SecureRandom().nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

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

Usage: issue side stores `TokenHashUtil.hash(plaintext)`, redemption side looks up by `findByTokenHash(TokenHashUtil.hash(incoming))`.

**Passwords** use `PasswordEncoder` (BCrypt), not SHA-256.

## Client IP detection

Never read `X-Forwarded-For` directly — let Tomcat's `RemoteIpValve` resolve it.

```yaml
server:
  forward-headers-strategy: native
  tomcat:
    remoteip:
      remote-ip-header: X-Forwarded-For
      internal-proxies: "10\\.\\d+\\.\\d+\\.\\d+|172\\.(1[6-9]|2\\d|3[01])\\.\\d+\\.\\d+"
```

```java
public class RequestUtils {
    public static String getClientIP(HttpServletRequest request) {
        return request.getRemoteAddr();
    }
}
```

## Security exceptions

```java
public class AccountTemporarilyLockedException extends RuntimeException {
    private final long retryAfterSeconds;
    public AccountTemporarilyLockedException(String message, long retryAfterSeconds) {
        super(message);
        this.retryAfterSeconds = retryAfterSeconds;
    }
    public long getRetryAfterSeconds() { return retryAfterSeconds; }
}

public class EmailNotVerifiedException extends RuntimeException {
    public EmailNotVerifiedException(String message) { super(message); }
}

public class AccountDisabledException extends RuntimeException {
    public AccountDisabledException(String message) { super(message); }
}
```

### GlobalExceptionHandler entries

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
    secret: ${APP_JWT_SECRET}
    expiration-ms: 86400000             # 24 hours
    refresh-expiration-ms: 2592000000   # 30 days

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
