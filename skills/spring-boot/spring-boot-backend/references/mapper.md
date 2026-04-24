# MapStruct Mapper Conventions

Mapper interface structure, method naming, ignore rules, sub-mappers, and collection helpers.

## Mapper interface

```java
@Mapper(componentModel = "spring", uses = { CountryMapper.class, PaymentMethodMapper.class })
public interface CustomerMapper {

    // --- Read methods (Entity → DTO) ---

    // Default response — FK as identifiers
    @Mapping(target = "countryId", source = "country.id")
    @Mapping(target = "paymentMethods", source = "paymentMethods", qualifiedByName = "paymentMethodIds")
    CustomerDto toDto(CustomerEntity entity);

    // Full response — FK expanded via sub-mappers (resolved through `uses`)
    @Mapping(target = "country", source = "country")
    @Mapping(target = "paymentMethods", source = "paymentMethods")
    CustomerFullDto toFullDto(CustomerEntity entity);

    CustomerSummaryDto toSummaryDto(CustomerEntity entity);

    CustomerListItemDto toListItemDto(CustomerEntity entity);

    // Lookup — derived display name
    @Mapping(target = "name",
             expression = "java(entity.getFirstName() + \" \" + entity.getLastName())")
    CustomerLookupDto toLookupDto(CustomerEntity entity);

    // --- Write methods (DTO → Entity) ---

    // Create — associations resolved by the service, not the mapper
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "country", ignore = true)
    @Mapping(target = "paymentMethods", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    CustomerEntity toEntity(CustomerCreateDto dto);

    // Update — full replacement of scalar fields
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "country", ignore = true)
    @Mapping(target = "paymentMethods", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void updateEntity(CustomerUpdateDto dto, @MappingTarget CustomerEntity entity);

    // --- Collection helpers ---

    @Named("paymentMethodIds")
    default List<UUID> toPaymentMethodIds(Set<PaymentMethodEntity> entities) {
        return entities.stream().map(PaymentMethodEntity::getId).toList();
    }
}
```

## Method naming

| Method | Direction | Used by |
|--------|-----------|---------|
| `toDto` | Entity → default response DTO | Service: get, create, update, patch |
| `toFullDto` | Entity → expanded response DTO | Service: get (full variant) |
| `toSummaryDto` | Entity → summary DTO | Service: get (summary variant) |
| `toListItemDto` | Entity → list item DTO | Service: search (`page.map(mapper::toListItemDto)`) |
| `toLookupDto` | Entity → lookup DTO | Service: search lookup |
| `toEntity` | Create DTO → new Entity | Service: create |
| `updateEntity` | Update DTO → existing Entity | Service: update |
| `patchEntity` | Patch DTO → existing Entity | Service: patch (see `references/patch.md`) |

## Ignore rules

Write methods (`toEntity`, `updateEntity`, `patchEntity`) must ignore:

| Field | Why |
|-------|-----|
| `id` | Set by service (`UUID.randomUUID()`) or preserved on update |
| Associations (`country`, `paymentMethods`) | Resolved by service via `getReferenceById` |
| `createdAt`, `updatedAt` | Managed by `@EnableJpaAuditing` |

## Sub-mappers via `uses`

```java
@Mapper(componentModel = "spring", uses = { CountryMapper.class, PaymentMethodMapper.class })
```

`uses` wires sub-mappers for the full variant — MapStruct calls `CountryMapper.toLookupDto()` automatically when mapping `CustomerFullDto.country`. No inline expressions needed.

## componentModel

Always `"spring"` — mappers are injected via constructor like any other dependency:

```java
@Service
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {
    private final CustomerMapper customerMapper;
}
```

## nullValuePropertyMappingStrategy

Do NOT set at `@Mapper` level. Use `@BeanMapping(nullValuePropertyMappingStrategy = IGNORE)` only on patch methods — see `references/patch.md`.
