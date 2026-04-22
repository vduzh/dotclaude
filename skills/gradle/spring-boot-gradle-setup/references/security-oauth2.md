# OAuth2 Resource Server dependencies

Spring Security as OAuth2 Resource Server — validate JWTs issued by an external IdP (Keycloak, Okta, etc.).

## `libs.versions.toml`

```toml
[versions]
keycloakJwtAuthoritiesConverter = "0.1.2"

[libraries]
keycloak-jwtAuthoritiesConverter = { module = "io.github.vduzh:keycloak-jwt-authorities-converter", version.ref = "keycloakJwtAuthoritiesConverter" }
```

## `build.gradle.kts`

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-oauth2-resource-server")
    implementation(libs.keycloak.jwtAuthoritiesConverter)

    testImplementation("org.springframework.security:spring-security-test")
}
```
