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
        config.setAllowedHeaders(List.of("Content-Type", "Authorization", "Accept"));
        config.setExposedHeaders(List.of("Authorization", "X-Total-Count"));
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
            JwtAuthenticationConverter converter) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(Customizer.withDefaults())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/public/**").permitAll()
                .requestMatchers("/swagger-ui/**", "/swagger-ui.html", "/v3/api-docs/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(converter)))
            .sessionManagement(session -> session.sessionCreationPolicy(STATELESS));
        return http.build();
    }
}
```

## Method-level security

Use `@PreAuthorize` for role-based access control:

```java
@PreAuthorize("hasRole('admin')")
@DeleteMapping("/{id}")
public ResponseEntity<Void> delete(@PathVariable UUID id) { ... }

@PreAuthorize("hasAnyRole('user', 'admin')")
@GetMapping("/{id}")
public ProfileDto findById(@PathVariable UUID id) { ... }
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
