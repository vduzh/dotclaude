# Self-issued JWT dependencies

Spring Security with service-issued JWTs (JJWT library) plus rate limiting and login-attempt protection (Bucket4j + Caffeine).

## `libs.versions.toml`

```toml
[versions]
jjwt = "0.12.6"
bucket4j = "8.10.1"
caffeine = "3.1.8"

[libraries]
jjwt-api = { module = "io.jsonwebtoken:jjwt-api", version.ref = "jjwt" }
jjwt-impl = { module = "io.jsonwebtoken:jjwt-impl", version.ref = "jjwt" }
jjwt-jackson = { module = "io.jsonwebtoken:jjwt-jackson", version.ref = "jjwt" }
bucket4j-caffeine = { module = "com.bucket4j:bucket4j-caffeine", version.ref = "bucket4j" }
caffeine = { module = "com.github.ben-manes.caffeine:caffeine", version.ref = "caffeine" }
```

## `build.gradle.kts`

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-security")

    implementation(libs.jjwt.api)
    runtimeOnly(libs.jjwt.impl)
    runtimeOnly(libs.jjwt.jackson)

    implementation(libs.bucket4j.caffeine)
    implementation(libs.caffeine)

    testImplementation("org.springframework.security:spring-security-test")
}
```
