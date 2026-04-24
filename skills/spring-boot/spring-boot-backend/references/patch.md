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
@Schema(name = "CustomerPatch")
public class CustomerPatchDto implements Patchable {

    @NullOrNotBlank @Size(max = 50)
    @Schema(description = "First name")
    private String firstName;

    @NullOrNotBlank @Size(max = 50)
    @Schema(description = "Last name")
    private String lastName;

    @Email @Size(max = 255)
    @Schema(description = "Email address")
    private String email;

    @Schema(description = "Account status")
    private AccountStatus status;

    @Schema(description = "Country ID")
    private UUID countryId;

    @Schema(description = "Payment method IDs")
    private List<UUID> paymentMethods;

    @Override
    public boolean isEmpty() {
        return firstName == null && lastName == null && email == null
            && status == null && countryId == null && paymentMethods == null;
    }
}
```

Note: `email` cannot be cleared via PATCH — `null` means "don't touch" per the `rest-api-design` payload contract. Use PUT for that.

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
public interface CustomerMapper {

    // PUT — all fields overwrite (including nulls)
    void updateEntityFromDto(CustomerUpdateDto dto, @MappingTarget CustomerEntity entity);

    // PATCH — only non-null fields update; associations handled by the service
    @BeanMapping(nullValuePropertyMappingStrategy = NullValuePropertyMappingStrategy.IGNORE)
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "country", ignore = true)
    @Mapping(target = "paymentMethods", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void patchEntityFromDto(CustomerPatchDto dto, @MappingTarget CustomerEntity entity);
}
```

## Service

Empty patches are rejected at the validation layer (`@NotEmptyPatch` + `@Valid` → 400). The service still checks `isEmpty()` as a defensive layer, and resolves FK fields manually (the mapper ignores associations — see `references/dto.md`):

```java
@Transactional
public CustomerDto patch(UUID id, CustomerPatchDto dto) {
    if (dto.isEmpty()) {
        return findById(id);
    }
    CustomerEntity entity = repository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("Customer not found: " + id));

    mapper.patchEntityFromDto(dto, entity);

    if (dto.getCountryId() != null) {
        entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
    }
    if (dto.getPaymentMethods() != null) {
        entity.setPaymentMethods(dto.getPaymentMethods().stream()
            .map(paymentMethodRepository::getReferenceById)
            .collect(Collectors.toSet()));
    }

    repository.save(entity);
    return mapper.toDto(entity);
}
```

- `if (dto.getCountryId() != null)` mirrors MapStruct's null-ignore: a PATCH that omits `countryId` leaves the existing country untouched.
- `paymentMethods` is a full-collection replacement on PATCH — sending `[]` clears the customer's methods; omitting the field keeps them. This matches the general "null/absent = don't touch, value = replace" PATCH semantics.

## Controller

```java
@PatchMapping("/{id}")
@Operation(summary = "Patch customer",
           description = "Partial update — at least one field required")
public CustomerDto patch(@PathVariable UUID id,
                         @Valid @RequestBody CustomerPatchDto dto) {
    return customerService.patch(id, dto);
}
```
