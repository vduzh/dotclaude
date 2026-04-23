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

Filter order: RateLimitingFilter → JwtAuthenticationFilter → UsernamePasswordAuthenticationFilter.

## CORS

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

When `allowCredentials(true)`, always list allowed headers explicitly — never wildcard `*`.

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

### Cache config

```java
@Bean
public Cache<String, Bucket> rateLimitBuckets(RateLimitingProperties props) {
    return Caffeine.newBuilder()
        .expireAfterAccess(Duration.ofMinutes(props.getCache().getExpireAfterAccessMinutes()))
        .maximumSize(props.getCache().getMaximumSize())
        .build();
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
        if (!properties.isEnabled()) { chain.doFilter(request, response); return; }
        String endpoint = resolveEndpoint(request.getRequestURI());
        if (endpoint == null) { chain.doFilter(request, response); return; }

        String key = RequestUtils.getClientIP(request) + ":" + endpoint;
        Bucket bucket = buckets.get(key, k -> createBucket(resolveRpm(endpoint)));
        if (!bucket.tryConsume(1)) throw new RateLimitExceededException("Rate limit exceeded");
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

## Login Attempt Protection (Caffeine)

Key: `IP:email.toLowerCase()` — prevents Account Lockout attack (attacker can only block own IP's access, not the victim's).

```java
@Service
@RequiredArgsConstructor
public class LoginAttemptServiceImpl implements LoginAttemptService {

    private final Cache<String, Integer> attemptsCache;
    private final LoginAttemptProperties properties;

    @Override
    public void recordFailedAttempt(String ip, String email) {
        String key = ip + ":" + email.toLowerCase();
        attemptsCache.put(key, attemptsCache.get(key, k -> 0) + 1);
    }

    @Override
    public boolean isBlocked(String ip, String email) {
        if (!properties.isEnabled()) return false;
        return attemptsCache.get(ip + ":" + email.toLowerCase(), k -> 0)
            >= properties.getMaxAttempts();
    }
}

@Bean
public Cache<String, Integer> loginAttemptCache(LoginAttemptProperties props) {
    return Caffeine.newBuilder()
        .expireAfterWrite(Duration.ofMinutes(props.getBlockDurationMinutes()))
        .maximumSize(props.getCache().getMaximumSize())
        .build();
}
```

## Client IP detection

```java
public class RequestUtils {
    public static String getClientIP(HttpServletRequest request) {
        String xff = request.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isEmpty()) return xff.split(",")[0].trim();
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isEmpty()) return realIp;
        return request.getRemoteAddr();
    }
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
@ResponseStatus(HttpStatus.TOO_MANY_REQUESTS)
public ErrorDto handleRateLimit(RateLimitExceededException ex) {
    return ErrorDto.builder().code("TOO_MANY_REQUESTS").message(ex.getMessage()).build();
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
