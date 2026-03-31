---
name: patch-implementation
description: Spring Boot PATCH implementation — Patchable interface, @NullOrNotBlank and @NotEmptyPatch validators, MapStruct @BeanMapping for partial updates
---

# PATCH Implementation (Spring Boot)

Spring Boot implementation of the PATCH design pattern (see `patch-operations` skill for API contract).

## Patchable Interface

All Patch DTOs implement `Patchable` — a contract for validation and optimization:

```java
public interface Patchable {
    boolean isEmpty();
}
```

## Patch DTO

```java
@Data
@Builder
@ToString(onlyExplicitlyIncluded = true)
@NotEmptyPatch
@Schema(name = "ProfilePatch")
public class ProfilePatchDto implements Patchable {

    @NullOrNotBlank @Size(max = 50)
    @Schema(description = "First name")
    private String firstName;

    @NullOrNotBlank @Size(max = 50)
    @Schema(description = "Last name")
    private String lastName;

    @Override
    public boolean isEmpty() {
        return firstName == null && lastName == null;
    }
}
```

## Custom Validators

### @NullOrNotBlank

Allows `null` (field not provided) but rejects blank/whitespace. Standard `@NotBlank` would reject `null`, which is wrong for PATCH semantics.

```java
@Constraint(validatedBy = NullOrNotBlankValidator.class)
@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface NullOrNotBlank {
    String message() default "must not be blank";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

public class NullOrNotBlankValidator implements ConstraintValidator<NullOrNotBlank, String> {
    @Override
    public boolean isValid(String value, ConstraintValidatorContext ctx) {
        return value == null || !value.trim().isEmpty();
    }
}
```

### @NotEmptyPatch

Class-level — validates that at least one field is non-null:

```java
@Constraint(validatedBy = NotEmptyPatchValidator.class)
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface NotEmptyPatch {
    String message() default "At least one field must be provided";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

public class NotEmptyPatchValidator implements ConstraintValidator<NotEmptyPatch, Patchable> {
    @Override
    public boolean isValid(Patchable value, ConstraintValidatorContext ctx) {
        return value != null && !value.isEmpty();
    }
}
```

## MapStruct: @BeanMapping for Patch Only

**Critical:** Set `nullValuePropertyMappingStrategy = IGNORE` only on the patch method via `@BeanMapping`. Never at `@Mapper` level — it would break PUT's `updateEntityFromDto`.

```java
@Mapper(componentModel = "spring")
public interface ProfileMapper {

    // PUT — all fields overwrite (including nulls)
    void updateEntityFromDto(ProfileUpdateDto dto, @MappingTarget ProfileEntity entity);

    // PATCH — only non-null fields update
    @BeanMapping(nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE)
    void patchEntityFromDto(ProfilePatchDto dto, @MappingTarget ProfileEntity entity);
}
```

## Service

Empty patches are rejected at validation layer (`@NotEmptyPatch` + `@Valid` → 400). Service also skips DB write as a defensive layer:

```java
@Transactional
public ProfileDto patch(UUID id, ProfilePatchDto dto) {
    if (dto.isEmpty()) {
        return findById(id);
    }

    ProfileEntity entity = getEntityOrThrow(id);
    mapper.patchEntityFromDto(dto, entity);
    repository.save(entity);
    return mapper.toDto(entity);
}
```

## Controller

```java
@PatchMapping("/{id}")
@Operation(summary = "Patch profile",
           description = "Partial update — at least one field required")
public ProfileDto patch(@PathVariable UUID id,
                        @Valid @RequestBody ProfilePatchDto dto) {
    return profileService.patch(id, dto);
}
```
