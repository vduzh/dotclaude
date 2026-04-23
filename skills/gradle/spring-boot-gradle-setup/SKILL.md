---
name: spring-boot-gradle-setup
description: >
  Set up or maintain the Gradle build of a single-module Spring Boot 3.5+
  application using Kotlin DSL. Use this skill when the user needs to
  configure, extend, or troubleshoot a Spring Boot Gradle build —
  bootstrapping a new project, adding or upgrading dependencies, upgrading
  Spring Boot or Gradle versions, or fixing build-time failures.
---

# Spring Boot Gradle Setup (Kotlin DSL)

Scope: Spring Boot **application** modules (produce a `bootJar`), not library modules.

## Baseline versions

| | Version |
|---|---|
| Gradle | 9.4.1 |
| Spring Boot | 3.5.13 |
| Java (toolchain) | 25 |
| MapStruct | 1.6.3 |
| Lombok-MapStruct binding | 0.2.0 |

## Project files

```
project-root/
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties            # optional
└── gradle/
    ├── libs.versions.toml
    └── wrapper/
        ├── gradle-wrapper.jar
        └── gradle-wrapper.properties
```

## `settings.gradle.kts`

```kotlin
rootProject.name = "my-service"
```

## `gradle/libs.versions.toml`

```toml
[versions]
springBoot = "3.5.13"
mapstruct = "1.6.3"
lombokMapstructBinding = "0.2.0"

[libraries]
springBoot-bom = { module = "org.springframework.boot:spring-boot-dependencies", version.ref = "springBoot" }
mapstruct = { module = "org.mapstruct:mapstruct", version.ref = "mapstruct" }
mapstruct-processor = { module = "org.mapstruct:mapstruct-processor", version.ref = "mapstruct" }
lombok-mapstructBinding = { module = "org.projectlombok:lombok-mapstruct-binding", version.ref = "lombokMapstructBinding" }

[plugins]
springBoot = { id = "org.springframework.boot", version.ref = "springBoot" }
```

**Conventions:**
- `camelCase` in `[versions]` and in alias segments.
- Hyphens in alias names become dots in Kotlin DSL: `mapstruct-processor` → `libs.mapstruct.processor`.
- Plugin and BOM share the same `springBoot` version key.
- Do not list Spring Boot starters in the catalog; write them inline without versions.

## `build.gradle.kts`

```kotlin
plugins {
    java
    alias(libs.plugins.springBoot)
}

group = "by.vduzh.example"
version = "0.0.1-SNAPSHOT"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-parameters")
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(platform(libs.springBoot.bom))
    annotationProcessor(platform(libs.springBoot.bom))

    implementation("org.springframework.boot:spring-boot-starter")

    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    implementation(libs.mapstruct)
    annotationProcessor(libs.mapstruct.processor)
    annotationProcessor(libs.lombok.mapstructBinding)

    developmentOnly("org.springframework.boot:spring-boot-devtools")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
}
```

**Non-negotiable rules:**

1. Use the native BOM via `platform(...)`, not the `io.spring.dependency-management` plugin.
2. Apply the BOM to both `implementation` and `annotationProcessor` configurations.
3. Annotation processor order: Lombok → MapStruct → `lombok-mapstruct-binding`.
4. Add `-parameters` to the Java compiler args.
5. Call `useJUnitPlatform()` in `tasks.test`.
6. Add `org.junit.platform:junit-platform-launcher` to `testRuntimeOnly`.

## Optional stacks

Load the reference file for each stack the project uses:

- `references/rest-api.md` — HTTP stack (web, validation, OpenAPI, Actuator, Prometheus).
  Load when the project exposes HTTP endpoints.
- `references/persistence.md` — Relational persistence (Spring Data JPA, PostgreSQL, Liquibase).
  Load when the project uses a relational database.
- `references/messaging.md` — Kafka producers/consumers, optional Outbox/Deduplication custom starters.
  Load when the project publishes or consumes Kafka events.
- `references/security-oauth2.md` — OAuth2 Resource Server (Keycloak/external IdP).
  Load when the service validates JWTs issued by an external IdP.
- `references/security-jjwt.md` — Self-issued JWTs (JJWT) + rate limiting (Bucket4j + Caffeine).
  Load when the service issues and validates its own JWTs.
- `references/testing.md` — Testcontainers core (cross-stack).
  Load when the project uses Testcontainers in tests.

## Wrapper

```bash
./gradlew wrapper --gradle-version 9.4.1 --distribution-type bin
```

- Commit `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`, `gradlew`, `gradlew.bat`.
- `.gitignore` must NOT exclude `gradle-wrapper.jar`.

## `gradle.properties` (optional)

Defaults are fine for single-module projects. Add these if the build is slow or OOMs:

```properties
org.gradle.caching=true
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
```

Do not add for single-module: `org.gradle.parallel`, `org.gradle.configureondemand`, `org.gradle.daemon`.

For multi-module projects, also add `org.gradle.parallel=true`.
