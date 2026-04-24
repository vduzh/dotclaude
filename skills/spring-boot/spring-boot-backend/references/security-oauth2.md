# Security — OAuth2 Resource Server (Keycloak)

Spring Security as OAuth2 Resource Server — validate JWTs issued by an external IdP (Keycloak).

See `spring-boot-gradle-setup/references/security-oauth2.md` for dependency setup.

## SecurityConfig

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    @Value("${app.cors.allowed-origins:http://localhost:4200}")
    private List<String> allowedOrigins;

    @Bean
    public KeycloakJwtGrantedAuthoritiesConverter grantedAuthoritiesConverter() {
        var converter = new KeycloakJwtGrantedAuthoritiesConverter();
        converter.setClaimNames(List.of("realm_access.roles"));
        return converter;
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter(
            KeycloakJwtGrantedAuthoritiesConverter grantedAuthoritiesConverter) {
        var converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(grantedAuthoritiesConverter);
        return converter;
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(allowedOrigins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Content-Type", "Accept", "Idempotency-Key"));
        config.setExposedHeaders(List.of("X-Total-Count", "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"));
        config.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return source;
    }

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
    public SecurityFilterChain apiSecurityFilterChain(
            HttpSecurity http,
            JwtAuthenticationConverter converter,
            BearerTokenResolver bearerTokenResolver) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(Customizer.withDefaults())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/public/**").permitAll()
                .requestMatchers("/swagger-ui/**", "/swagger-ui.html", "/v3/api-docs/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .bearerTokenResolver(bearerTokenResolver)
                .jwt(jwt -> jwt.jwtAuthenticationConverter(converter)))
            .sessionManagement(session -> session.sessionCreationPolicy(STATELESS));
        return http.build();
    }
}
```

## Token delivery — HttpOnly cookie

Per the `rest-api-design` security contract, the access token travels in an `HttpOnly` cookie, not in an `Authorization` header. The BFF that exchanges the IdP authorization code for a token sets the cookie; subsequent requests carry it automatically via the browser.

Replace the default `BearerTokenResolver` (which reads from `Authorization`) with a cookie-based one:

```java
@Component
public class CookieBearerTokenResolver implements BearerTokenResolver {

    private static final String COOKIE_NAME = "access_token";

    @Override
    public String resolve(HttpServletRequest request) {
        Cookie[] cookies = request.getCookies();
        if (cookies == null) return null;
        return Arrays.stream(cookies)
            .filter(c -> COOKIE_NAME.equals(c.getName()))
            .map(Cookie::getValue)
            .findFirst()
            .orElse(null);
    }
}
```

The BFF endpoint that completes the OAuth2 code exchange writes the cookie:

```java
ResponseCookie cookie = ResponseCookie.from("access_token", accessToken)
    .httpOnly(true).secure(true).sameSite("Lax").path("/")
    .maxAge(Duration.ofSeconds(expiresIn))
    .build();
return ResponseEntity.noContent()
    .header(HttpHeaders.SET_COOKIE, cookie.toString())
    .build();
```

The filter chain then reads the token via `CookieBearerTokenResolver`, never from `Authorization`.

## Method-level security

Use `@PreAuthorize` for role-based access control:

```java
@PreAuthorize("hasRole('admin')")
@DeleteMapping("/{id}")
public ResponseEntity<Void> delete(@PathVariable UUID id) { ... }

@PreAuthorize("hasAnyRole('user', 'admin')")
@GetMapping("/{id}")
public CustomerDto findById(@PathVariable UUID id) { ... }
```

## Security exceptions in GlobalExceptionHandler

```java
@ExceptionHandler(AuthenticationException.class)
@ResponseStatus(HttpStatus.UNAUTHORIZED)
public ErrorDto handleAuth(AuthenticationException ex) {
    return ErrorDto.builder().code("UNAUTHORIZED").message("Authentication required").build();
}

@ExceptionHandler(AccessDeniedException.class)
@ResponseStatus(HttpStatus.FORBIDDEN)
public ErrorDto handleAccessDenied(AccessDeniedException ex) {
    return ErrorDto.builder().code("FORBIDDEN").message("Access denied").build();
}
```

## YAML config

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI}

app:
  cors:
    allowed-origins: ${APP_CORS_ALLOWED_ORIGINS:http://localhost:4200}
```
