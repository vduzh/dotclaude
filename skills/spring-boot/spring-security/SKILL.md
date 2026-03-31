---
name: spring-security
description: Spring Security for REST APIs — dual SecurityFilterChain, stateless JWT, rate limiting with Bucket4j, login attempt protection, security exceptions
---

# Spring Security (REST API)

Spring Boot implementation of API security patterns (see `api-security` skill for design).

## Dual SecurityFilterChain

Two filter chains — actuator (no auth) and API (JWT auth):

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
                .requestMatchers("/", "/api/v1/auth/**", "/api/v1/public/**").permitAll()
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

**Filter chain order:** RateLimitingFilter → JwtAuthenticationFilter → UsernamePasswordAuthenticationFilter

## CORS Configuration

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of(corsAllowedOrigins));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    config.setAllowedHeaders(List.of("Content-Type", "Authorization", "Accept"));
    config.setExposedHeaders(List.of("Authorization", "X-Total-Count"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}
```

When `allowCredentials(true)`, always list headers explicitly — never wildcard `*`.

## Rate Limiting (Bucket4j + Caffeine)

### Properties

```java
@ConfigurationProperties(prefix = "app.rate-limiting")
@Data
public class RateLimitingProperties {
    private boolean enabled = true;
    private int defaultRequestsPerMinute = 5;
    private Map<String, EndpointLimit> endpoints = new HashMap<>();
    private CacheProperties cache = new CacheProperties();

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

### Cache Config

```java
@Configuration
@RequiredArgsConstructor
public class RateLimitConfig {

    @Bean
    public Cache<String, Bucket> rateLimitBuckets(RateLimitingProperties props) {
        return Caffeine.newBuilder()
            .expireAfterAccess(Duration.ofMinutes(props.getCache().getExpireAfterAccessMinutes()))
            .maximumSize(props.getCache().getMaximumSize())
            .build();
    }
}
```

### Filter

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
        if (!properties.isEnabled()) {
            chain.doFilter(request, response);
            return;
        }

        String endpoint = resolveEndpoint(request.getRequestURI());
        if (endpoint == null) {
            chain.doFilter(request, response);
            return;
        }

        String clientIp = RequestUtils.getClientIP(request);
        String key = clientIp + ":" + endpoint;
        int rpm = resolveRpm(endpoint);

        Bucket bucket = buckets.get(key, k -> createBucket(rpm));
        if (!bucket.tryConsume(1)) {
            throw new RateLimitExceededException("Rate limit exceeded");
        }

        chain.doFilter(request, response);
    }

    private Bucket createBucket(int rpm) {
        return Bucket.builder()
            .addLimit(Bandwidth.simple(rpm, Duration.ofMinutes(1)))
            .build();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/v1/auth/");
    }
}
```

## Login Attempt Protection (Caffeine)

```java
@Service
@RequiredArgsConstructor
public class LoginAttemptServiceImpl implements LoginAttemptService {

    private final Cache<String, Integer> attemptsCache;
    private final LoginAttemptProperties properties;

    @Override
    public void recordFailedAttempt(String ip, String email) {
        String key = buildKey(ip, email);
        int attempts = attemptsCache.get(key, k -> 0) + 1;
        attemptsCache.put(key, attempts);
    }

    @Override
    public void clearAttempts(String ip, String email) {
        attemptsCache.invalidate(buildKey(ip, email));
    }

    @Override
    public boolean isBlocked(String ip, String email) {
        if (!properties.isEnabled()) return false;
        int attempts = attemptsCache.get(buildKey(ip, email), k -> 0);
        return attempts >= properties.getMaxAttempts();
    }

    private String buildKey(String ip, String email) {
        return ip + ":" + email.toLowerCase();
    }
}
```

### Cache Config

```java
@Bean
public Cache<String, Integer> loginAttemptCache(LoginAttemptProperties props) {
    return Caffeine.newBuilder()
        .expireAfterWrite(Duration.ofMinutes(props.getBlockDurationMinutes()))
        .maximumSize(props.getCache().getMaximumSize())
        .build();
}
```

## Client IP Detection

```java
public class RequestUtils {
    public static String getClientIP(HttpServletRequest request) {
        String xff = request.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isEmpty()) {
            return xff.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isEmpty()) {
            return realIp;
        }
        return request.getRemoteAddr();
    }
}
```

## Security Exceptions in GlobalExceptionHandler

```java
@ExceptionHandler(AuthenticationException.class)
@ResponseStatus(HttpStatus.UNAUTHORIZED)
public ErrorDto handleAuth(AuthenticationException ex) {
    return ErrorDto.builder().code("UNAUTHORIZED").message("Invalid credentials").build();
}

@ExceptionHandler(RateLimitExceededException.class)
@ResponseStatus(HttpStatus.TOO_MANY_REQUESTS)
public ErrorDto handleRateLimit(RateLimitExceededException ex) {
    return ErrorDto.builder().code("TOO_MANY_REQUESTS").message(ex.getMessage()).build();
}

@ExceptionHandler(AccountTemporarilyLockedException.class)
@ResponseStatus(HttpStatus.TOO_MANY_REQUESTS)
public ErrorDto handleLocked(AccountTemporarilyLockedException ex) {
    return ErrorDto.builder().code("ACCOUNT_TEMPORARILY_LOCKED").message(ex.getMessage()).build();
}

@ExceptionHandler(AccountDisabledException.class)
@ResponseStatus(HttpStatus.FORBIDDEN)
public ErrorDto handleDisabled(AccountDisabledException ex) {
    return ErrorDto.builder().code("ACCOUNT_DISABLED").message(ex.getMessage()).build();
}
```

## YAML Configuration

```yaml
app:
  jwt:
    secret: ${APP_JWT_SECRET}         # min 256-bit key
    expiration-ms: 86400000           # 24 hours
    refresh-expiration-ms: 2592000000 # 30 days

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
    cache:
      expire-after-access-minutes: 5
      maximum-size: 10000

  login-attempt:
    enabled: true
    max-attempts: 5
    block-duration-minutes: 15
    cache:
      expire-after-write-minutes: 15
      maximum-size: 10000
```
