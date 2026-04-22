# REST API dependencies

Dependencies for building REST HTTP endpoints with OpenAPI documentation and Actuator.

## `libs.versions.toml`

```toml
[versions]
springdocOpenapi = "2.7.0"

[libraries]
springdoc-openapi = { module = "org.springdoc:springdoc-openapi-starter-webmvc-ui", version.ref = "springdocOpenapi" }
```

## `build.gradle.kts`

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("io.micrometer:micrometer-registry-prometheus")
    implementation(libs.springdoc.openapi)
}
```

Default URLs:
- Swagger UI: `/swagger-ui.html`
- OpenAPI JSON: `/v3/api-docs`
- Actuator: `/actuator/health`, `/actuator/prometheus` (exposure configured via `application.yml`)
