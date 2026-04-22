# Persistence dependencies

Dependencies for relational persistence with Spring Data JPA, PostgreSQL, and Liquibase.

## `build.gradle.kts`

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    runtimeOnly("org.liquibase:liquibase-core")
    runtimeOnly("org.postgresql:postgresql")

    testImplementation("org.testcontainers:postgresql")
}
```
