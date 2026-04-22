# dotclaude

Reusable Claude Code skill catalog. Skills live under `skills/<category>/<skill-name>/` and are copied into consuming projects via `install.sh`.

Authoring conventions: see [`CLAUDE.md`](CLAUDE.md).

## Repository structure

```
skills/
├── database/       — schema migrations, DB Docker setup, SQL style
├── design/         — language-agnostic API/UX design (REST conventions, pagination, error formats)
├── gradle/         — build configuration (build.gradle.kts, plugins, dependencies)
├── spring-boot/    — Spring Boot runtime patterns (layered architecture, DI, JPA, security)
└── ui/             — frontend patterns (React, Ant Design)
```

## Installing skills into a project

```bash
./install.sh <project-path> <skill-name> [<skill-name> ...]
./install.sh <project-path> --all
./install.sh <project-path> --list
```

Skills are copied to `<project-path>/.claude/skills/<skill-name>/`. Claude Code picks them up on the next session.

## How skill loading works (progressive disclosure)

1. **Startup** — Claude Code loads only `name` + `description` of every skill (~100 tokens each).
2. **Activation** — when your message semantically matches a skill's description, Claude reads that skill's full `SKILL.md` body into context.
3. **References** — if the skill has a `references/` directory, Claude reads individual reference files on demand (via `Read` tool) based on what your message asks for. Unused references stay on disk.

**Implication:** name the concerns in your prompt (REST, DB, Kafka, JWT, etc.) — vague prompts don't trigger references.

---

## Skills catalog

- **database/**
  - `liquibase-migrations`
  - `postgresql-docker`
- **design/**
  - `api-security`
  - `dto-conventions`
  - `error-response-format`
  - `lookup-endpoints`
  - `pagination-sorting`
  - `rest-api-design`
- **gradle/**
  - [`spring-boot-gradle-setup`](#spring-boot-gradle-setup)
- **spring-boot/**
  - `dto-implementation`
  - `exception-handling`
  - `logging-conventions`
  - `lookup-implementation`
  - `new-endpoint-checklist`
  - `pagination-filtering`
  - `patch-implementation`
  - `spring-data-jpa`
  - `spring-layered-arch`
  - `spring-security`
  - `swagger-docs`
- **ui/**
  - `antd-patterns`
  - `react-component-patterns`
  - `react-state-management`
  - `tanstack-query`

Links point to per-skill usage sections below. Skills without a link have their instructions only in their `SKILL.md`.

---

## Per-skill usage

### `spring-boot-gradle-setup`

Category: `gradle/`

Configures the Gradle build of a single-module Spring Boot 3.5+ application (Kotlin DSL). Base covers BOM, Lombok + MapStruct, core Spring Boot starter, and the minimum test config. References add stack-specific dependencies.

#### References

| File | Scope |
|---|---|
| `rest-api.md` | HTTP stack: web, validation, OpenAPI, Actuator, Prometheus |
| `persistence.md` | Spring Data JPA + PostgreSQL + Liquibase |
| `messaging.md` | Kafka core + custom Outbox/Deduplication (local Nexus) |
| `security-oauth2.md` | OAuth2 Resource Server + Keycloak converter |
| `security-jjwt.md` | Self-issued JWTs (JJWT) + rate limiting (Bucket4j + Caffeine) |
| `testing.md` | Testcontainers core (cross-stack) |

#### Example prompts

| Prompt | Loads |
|---|---|
| "Set up a Spring Boot Gradle build for a REST API with PostgreSQL." | base + `rest-api` + `persistence` + `testing` |
| "Add a Kafka consumer with Outbox to this project." | base + `messaging` |
| "This service validates JWTs from Keycloak." | base + `security-oauth2` |
| "Set up a REST API with self-issued JWT auth." | base + `rest-api` + `security-jjwt` |

#### Typical compositions

| Service type | References |
|---|---|
| CRUD REST service | `rest-api` + `persistence` + `testing` |
| Event-driven microservice (ms-profile style) | `rest-api` + `persistence` + `messaging` + `security-oauth2` + `testing` |
| Pure Kafka consumer (no HTTP) | `messaging` + `persistence` + `testing` |
| SaaS API with self-issued auth (nano-crm style) | `rest-api` + `persistence` + `security-jjwt` |

**Tip:** vague prompts like "set up the build" may load only `SKILL.md` and produce a minimal skeleton. Name the concerns explicitly — or pass a composition directly: *"compose rest-api + persistence + testing"*.
