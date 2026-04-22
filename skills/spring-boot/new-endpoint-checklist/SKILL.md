---
name: new-endpoint-checklist
description: Step-by-step checklist for adding a new REST endpoint — entity, migration, repository, DTOs, specification, mapper, service, controller
disable-model-invocation: true
argument-hint: "[entity-name]"
---

# New Endpoint Checklist

Requires the `spring-boot-backend` skill for implementation conventions.

Follow these steps to add a new REST endpoint for entity `$ARGUMENTS`:

1. Create Liquibase migration.
2. Register the migration in the master changelog.
3. Create JPA entity.
4. Create Spring Data JPA repository.
5. Create DTOs.
6. Create Specification.
7. Create MapStruct mapper.
8. Create service (interface + implementation).
9. Create REST controller.
