# PATCH Implementation

`Patchable` interface, `@NullOrNotBlank`, `@NotEmptyPatch` validators, MapStruct `@BeanMapping` for partial updates.

## Patchable interface

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

## Custom validators

### @NullOrNotBlank

Allows `null` (field not provided) but rejects blank/whitespace:

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

## MapStruct: @BeanMapping on patch method only

Set `nullValuePropertyMappingStrategy = IGNORE` only on the patch method via `@BeanMapping`. Never at `@Mapper` level — it would break PUT's `updateEntityFromDto`:

```java
@Mapper(componentModel = "spring")
public interface ProfileMapper {

    // PUT — all fields overwrite (including nulls)
    void updateEntityFromDto(ProfileUpdateDto dto, @MappingTarget ProfileEntity entity);

    // PATCH — only non-null fields update
    @BeanMapping(nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE)
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void patchEntityFromDto(ProfilePatchDto dto, @MappingTarget ProfileEntity entity);
}
```

## Service

Empty patches are rejected at validation layer (`@NotEmptyPatch` + `@Valid` → 400). Service skips DB write as a defensive layer:

```java
@Transactional
public ProfileDto patch(UUID id, ProfilePatchDto dto) {
    if (dto.isEmpty()) {
        return findById(id);
    }
    ProfileEntity entity = repository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("Profile not found: " + id));
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
