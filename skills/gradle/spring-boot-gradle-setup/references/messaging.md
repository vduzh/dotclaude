# Messaging dependencies

## Core (Spring Kafka)

### `build.gradle.kts`

```kotlin
dependencies {
    implementation("org.springframework.kafka:spring-kafka")

    testImplementation("org.springframework.kafka:spring-kafka-test")
}
```

## Custom starters (Outbox + Deduplication + Event Dispatcher)

Pulled from local Nexus. Use when the service follows the Outbox CDC pattern or consumes events with idempotency guarantees.

### `libs.versions.toml`

```toml
[versions]
eventDispatcher = "1.0.2"
eventDeduplication = "1.2.3"
outboxEvent = "1.3.2"

[libraries]
event-dispatcher = { module = "by.vduzh.event.dispatcher:event-dispatcher", version.ref = "eventDispatcher" }
event-deduplication = { module = "by.vduzh.deduplication:event-deduplication-spring-boot-starter", version.ref = "eventDeduplication" }
outbox-event = { module = "by.vduzh.outbox:outbox-event-spring-boot-starter", version.ref = "outboxEvent" }
```

### `build.gradle.kts`

```kotlin
repositories {
    maven {
        name = "nexusReleases"
        url = uri("http://localhost:8081/repository/maven-releases/")
        isAllowInsecureProtocol = true
    }
    maven {
        name = "nexusSnapshots"
        url = uri("http://localhost:8081/repository/maven-snapshots/")
        isAllowInsecureProtocol = true
    }
}

dependencies {
    implementation(libs.event.dispatcher)
    implementation(libs.event.deduplication)
    implementation(libs.outbox.event)
}
```
