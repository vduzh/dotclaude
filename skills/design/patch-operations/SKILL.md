---
name: patch-operations
description: PATCH endpoint design — Patchable interface, @NullOrNotBlank, @NotEmptyPatch validation, MapStruct @BeanMapping for partial updates
---

# PATCH Operations

Apply these patterns when implementing PATCH (partial update) endpoints.

## Patchable Interface

All Patch DTOs implement `Patchable` — a contract that allows validation and optimization:

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
@NotEmptyPatch  // class-level: at least one field must be non-null
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

Allows `null` (field not provided) but rejects blank/whitespace strings. Standard `@NotBlank` would reject `null`, which is wrong for PATCH semantics.

```java
@Constraint(validatedBy = NullOrNotBlankValidator.class)
@Target(ElementType.FIELD)
@Retention(RetentionPolicy.RUNTIME)
public @interface NullOrNotBlank {
    String message() default "must not be blank";
    // ...
}

public class NullOrNotBlankValidator implements ConstraintValidator<NullOrNotBlank, String> {
    @Override
    public boolean isValid(String value, ConstraintValidatorContext ctx) {
        return value == null || !value.trim().isEmpty();
    }
}
```

### @NotEmptyPatch

Class-level annotation — validates that at least one field is non-null (rejects empty PATCH body):

```java
@Constraint(validatedBy = NotEmptyPatchValidator.class)
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface NotEmptyPatch {
    String message() default "At least one field must be provided";
    // ...
}

public class NotEmptyPatchValidator implements ConstraintValidator<NotEmptyPatch, Patchable> {
    @Override
    public boolean isValid(Patchable value, ConstraintValidatorContext ctx) {
        return value != null && !value.isEmpty();
    }
}
```

## MapStruct: @BeanMapping for Patch Only

**Critical:** Set `nullValuePropertyMappingStrategy = IGNORE` per-method via `@BeanMapping`, only on patch methods. Never at `@Mapper` level — otherwise PUT's `updateEntityFromDto` would silently skip null fields instead of overwriting them.

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

## Service Layer Optimization

Empty patches are rejected at validation layer (`@NotEmptyPatch` + `@Valid` → 400 automatically). Service also skips DB write as a defensive layer:

```java
@Transactional
public ProfileDto patch(UUID id, ProfilePatchDto dto) {
    if (dto.isEmpty()) {
        return findById(id);  // defensive: no DB write
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
public ProfileDto patch(@PathVariable UUID id,
                        @Valid @RequestBody ProfilePatchDto dto) {
    return profileService.patch(id, dto);
}
```
