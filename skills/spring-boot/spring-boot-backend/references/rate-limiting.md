# Rate Limiting (Bucket4j + Caffeine)

Per-endpoint and per-user rate limiting with `X-RateLimit-*` headers, plus email-trigger cooldown.

Implements the rate-limiting contract from the `rest-api-design` skill. Pairs with `references/security-jwt.md` — register filters in `SecurityConfig`.

## Properties

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

## Cache beans

Add to `CacheConfig` (see `references/security-jwt.md` for login-attempt caches in the same class):

```java
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
```

## Per-endpoint filter (public auth endpoints)

Keys by `{clientIP, endpoint}`. Runs **before** `JwtAuthenticationFilter`.

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
            throw new RateLimitExceededException(
                "Too many requests. Please try again later.", Math.max(1, retryAfter));
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

## Per-user filter (protected endpoints)

Keys by `{userId, endpoint-group}`. Runs **after** `JwtAuthenticationFilter`.

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
            throw new RateLimitExceededException(
                "Too many requests. Please try again later.", Math.max(1, retryAfter));
        }
        chain.doFilter(request, response);
    }

    private String resolveGroup(HttpServletRequest request) {
        String method = request.getMethod();
        if ("POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method) || "DELETE".equals(method)) {
            return "mutations";
        }
        return null;
    }
}
```

## SecurityConfig registration

```java
.addFilterBefore(rateLimitingFilter, UsernamePasswordAuthenticationFilter.class)
.addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
.addFilterAfter(perUserRateLimitingFilter, JwtAuthenticationFilter.class)
```

Filter order: RateLimitingFilter → JwtAuthenticationFilter → PerUserRateLimitingFilter.

## X-RateLimit-* response headers

Both filters emit headers on **every** response (success and 429):

```java
public final class RateLimitHeaders {
    private RateLimitHeaders() {}

    public static void set(HttpServletResponse response, int limit, ConsumptionProbe probe) {
        response.setHeader("X-RateLimit-Limit", String.valueOf(limit));
        response.setHeader("X-RateLimit-Remaining",
            String.valueOf(Math.max(0, probe.getRemainingTokens())));
        response.setHeader("X-RateLimit-Reset",
            String.valueOf(TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill())));
    }
}
```

Already added to CORS `exposedHeaders` in `references/security-jwt.md`.

## Email-trigger cooldown

Per-`{email, endpoint}` cooldown for endpoints that dispatch email (`/auth/forgot-password`, `/auth/resend-verification`).

```java
@Service
@RequiredArgsConstructor
public class EmailTriggerCooldownService {

    private final Cache<String, Instant> emailCooldownCache;
    private final EmailCooldownProperties properties;

    public boolean checkAndRecord(String email, String endpoint) {
        String key = email.toLowerCase() + ":" + endpoint;
        Instant last = emailCooldownCache.getIfPresent(key);
        if (last != null && Duration.between(last, Instant.now()).getSeconds()
                < properties.getCooldownSeconds()) {
            return false;
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

Usage in AuthController:

```java
@PostMapping("/forgot-password")
public ResponseEntity<MessageDto> forgotPassword(@Valid @RequestBody ForgotPasswordDto dto) {
    if (emailTriggerCooldownService.checkAndRecord(dto.getEmail(), "forgot-password")) {
        passwordResetService.sendResetEmailIfUserExists(dto.getEmail());
    }
    return ResponseEntity.ok(MessageDto.of(
        "If your email is registered, you will receive a password reset link."));
}
```

Response stays identical on cooldown — consistent with anti-enumeration.

## RateLimitExceededException

```java
public class RateLimitExceededException extends RuntimeException {
    private final long retryAfterSeconds;
    public RateLimitExceededException(String message, long retryAfterSeconds) {
        super(message);
        this.retryAfterSeconds = retryAfterSeconds;
    }
    public long getRetryAfterSeconds() { return retryAfterSeconds; }
}
```

### GlobalExceptionHandler entry

```java
@ExceptionHandler(RateLimitExceededException.class)
public ResponseEntity<ErrorDto> handleRateLimit(RateLimitExceededException ex) {
    return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
        .header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()))
        .body(ErrorDto.builder().code("TOO_MANY_REQUESTS").message(ex.getMessage()).build());
}
```

## YAML config

```yaml
app:
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
```
