---
name: new-endpoint-checklist
description: Step-by-step checklist for adding a new REST endpoint — entity, migration, repository, DTOs, specification, mapper, service, controller
disable-model-invocation: true
argument-hint: "[entity-name]"
---

# New Endpoint Checklist

Follow these steps to add a new REST endpoint for entity `$ARGUMENTS`:

## Steps

1. **Entity** — Create JPA entity in `model/` (or `repository/jpa/entity/`)
   - `UUID` ID, `@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder`
   - Audit fields (`@CreatedDate`, `@LastModifiedDate`) if owned entity
   - Enums in separate files in `model/enums/`

2. **Migration** — Create Liquibase migration in `db/changelog/changes/*.sql` (or `migrations/*.sql`)
   - Formatted SQL, not XML
   - SQL Style Guide formatting (uppercase keywords, snake_case names, aligned columns)
   - `TIMESTAMP WITH TIME ZONE` for timestamps, `UUID` for IDs
   - Named constraints, indexes in separate statements
   - Add rollback statement

3. **Changelog** — Add changeset to `db.changelog-master.xml` (or `.yaml`)

4. **Repository** — Create repository extending `JpaRepository<Entity, UUID>` + `JpaSpecificationExecutor<Entity>`

5. **DTOs** — Create in `dto/` package:
   - `XxxCreateDto` — POST body with validation
   - `XxxUpdateDto` — PUT body (all fields required)
   - `XxxPatchDto` — PATCH body (implements `Patchable`, `@NotEmptyPatch`)
   - `XxxDto` — Response (single resource)
   - `XxxListItemDto` — Response (list/table view)
   - `XxxLookupDto` — Response (dropdown/select)
   - `XxxSearchParams` — Query parameters with `@ValidSort`
   - All with `@Schema(name = "...")` for clean OpenAPI names

6. **Specification** — Create `XxxSpecification` for filtering
   - 1-3 params: individual arguments
   - 4+ params: create `XxxFilter` in `repository/spec/`

7. **Mapper** — Create MapStruct mapper interface
   - `@Mapper(componentModel = "spring")`
   - Methods: `toDto`, `toListItemDto`, `toLookupDto`, `toEntity`, `updateEntityFromDto`
   - `patchEntityFromDto` with `@BeanMapping(nullValuePropertyMappingStrategy = IGNORE)`

8. **Service** — Create interface + implementation
   - `@Transactional` on class, `@Transactional(readOnly = true)` on reads
   - `@RequiredArgsConstructor` for DI
   - `PagedResult<T>` for list methods (not `Page<T>`)
   - `ResourceNotFoundException` for not-found scenarios

9. **Controller** — Create `@RestController`
   - Content Negotiation (list + lookup views)
   - Pagination, filtering, sorting via `@Valid @ModelAttribute SearchParams`
   - `@Operation(summary = "...")` on all endpoints
   - Methods ordered by HTTP verb (GET, POST, PUT, PATCH, DELETE)

10. **Validation** — Add `@Valid` on request bodies and query params
    - Custom validators if needed (`@ValidSort`, `@NullOrNotBlank`, `@NotEmptyPatch`)

11. **Test** — Verify via Swagger UI
