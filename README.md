# dotclaude

Reusable Claude Code skill catalog. Skills live under `skills/<category>/<skill-name>/` and are copied into consuming projects via `install.sh`.

Authoring conventions: see [`CLAUDE.md`](CLAUDE.md).

## Repository structure

```
skills/
├── database/       — DB infrastructure (Docker Compose setup)
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
  - `postgresql-docker`
- **design/**
  - [`rest-api-design`](#rest-api-design)
- **gradle/**
  - [`spring-boot-gradle-setup`](#spring-boot-gradle-setup)
- **spring-boot/**
  - [`spring-boot-backend`](#spring-boot-backend)
  - `new-endpoint-checklist`
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

---

### `spring-boot-backend`

Category: `spring-boot/`

Implements and maintains Spring Boot 3.5+ backend runtime code — layered architecture, services, JPA entities, REST controllers, DTOs, exceptions, pagination, security, logging, and Liquibase migrations. Base covers cross-cutting patterns (layered arch, DI, adapter pattern, auth, transactions, entity design, idempotent delete). References add concern-specific implementation detail.

#### References

| File | Scope |
|---|---|
| `dto.md` | DTO class structure, Lombok per type, Bean Validation, `@Schema`, MapStruct mapper |
| `jpa.md` | Repository naming, With-suffix eager loading, `getReferenceById`, datasource/HikariCP |
| `exceptions.md` | Dedicated exceptions, `GlobalExceptionHandler`, `ErrorDto`, Exception-vs-Optional |
| `pagination.md` | `PagedResult`/`PagedResponse`, `SortUtil`, `@ValidSort`, Specifications, Filter objects |
| `patch.md` | `Patchable`, `@NullOrNotBlank`, `@NotEmptyPatch`, MapStruct `@BeanMapping` |
| `lookup.md` | Large/small lookup endpoints, `X-Total-Count` header |
| `security-oauth2.md` | Dual `SecurityFilterChain`, OAuth2 Resource Server (Keycloak), CORS |
| `security-jjwt.md` | Dual `SecurityFilterChain`, self-issued JWTs (JJWT), Bucket4j, login-attempt |
| `logging.md` | `key=value` format, verb tenses, PII via `@ToString` |
| `swagger.md` | `@Operation` summary/description rules, `@ApiResponse` sparing use |
| `migrations.md` | Liquibase formatted SQL, SQL Style Guide, rollback, test data contexts |

#### Example prompts

| Prompt | Loads |
|---|---|
| "Add a REST endpoint for Invoice entity with pagination and filtering." | base + `dto` + `jpa` + `pagination` + `exceptions` + `swagger` + `migrations` |
| "Implement PATCH for the Profile entity." | base + `dto` + `patch` |
| "Add a lookup endpoint for coaches." | base + `lookup` |
| "Set up exception handling for this service." | base + `exceptions` |
| "Add login-attempt protection and rate limiting." | base + `security-jjwt` |

#### Typical compositions

| Task | References |
|---|---|
| New entity + full CRUD endpoint | `dto` + `jpa` + `migrations` + `pagination` + `exceptions` + `swagger` |
| PATCH endpoint | `dto` + `patch` + `exceptions` |
| Lookup endpoint | `dto` + `lookup` |
| OAuth2 security setup (ms-profile style) | `security-oauth2` |
| Self-issued JWT security (nano-crm style) | `security-jjwt` |
| Logging review / adding logs | `logging` |

**Pairs with:** `spring-boot-gradle-setup` (build config) and `rest-api-design` (API design contracts).

---

### `rest-api-design`

Category: `design/`

Defines REST API contracts — URI conventions, HTTP verbs, status codes, content negotiation, DTO naming, pagination format, error responses, and security patterns. Language-agnostic design layer; pairs with `spring-boot-backend` for Spring implementation detail.

#### References

| File | Scope |
|---|---|
| `dto-conventions.md` | Noun-first naming, DTO types per operation, JSON examples |
| `pagination-sorting.md` | Query parameters, JSON:API sort format, `PagedResponse` shape, stable sorting |
| `error-format.md` | Error codes, validation error shape, scenario-to-HTTP mapping |
| `lookup-endpoints.md` | Strategy by data volume, `X-Total-Count`, frontend UX pattern |
| `api-security.md` | Stateless auth, HttpOnly cookies, rate limiting, brute-force protection |

#### Example prompts

| Prompt | Loads |
|---|---|
| "Design the DTO structure for an Invoice endpoint." | base + `dto-conventions` |
| "What format should pagination use?" | base + `pagination-sorting` |
| "How should error responses look?" | base + `error-format` |
| "Design a lookup endpoint for athletes." | base + `lookup-endpoints` |
| "What security patterns should the auth endpoints use?" | base + `api-security` |
