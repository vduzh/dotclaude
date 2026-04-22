# Testing dependencies

Cross-stack test infrastructure (Testcontainers core). Stack-specific test helpers are in their respective stack references.

## `build.gradle.kts`

```kotlin
dependencies {
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:junit-jupiter")
}
```
