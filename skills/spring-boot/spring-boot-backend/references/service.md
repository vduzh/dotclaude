# Service Conventions

Interface/Impl structure, CRUD skeleton, transaction management, ownership verification, and helper methods.

## Interface + Impl

```java
// service/CustomerService.java
public interface CustomerService {
    CustomerDto getById(UUID userId, UUID id);
    PagedResult<CustomerListItemDto> search(UUID userId, CustomerSearchParams params);
    CustomerDto create(UUID userId, CustomerCreateDto dto);
    CustomerDto update(UUID userId, UUID id, CustomerUpdateDto dto);
    CustomerDto patch(UUID userId, UUID id, CustomerPatchDto dto);
    void delete(UUID userId, UUID id);
}
```

Method order: find/read → create → update → patch → delete.

## Class-level annotations

```java
@Service
@Transactional
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {

    private final CustomerRepository customerRepository;
    private final CountryRepository countryRepository;
    private final CustomerMapper customerMapper;
}
```

| Annotation | Purpose |
|---|---|
| `@Service` | Spring component |
| `@Transactional` | Default transaction for all methods |
| `@RequiredArgsConstructor` | Constructor injection |

## Transaction management

Class-level `@Transactional` applies to all methods. Override per method when needed:

```java
@Service
@Transactional
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {

    @Override
    @Transactional(readOnly = true)
    public CustomerDto getById(UUID userId, UUID id) { ... }

    @Override
    public CustomerDto create(UUID userId, CustomerCreateDto dto) { ... }
}
```

| Operation | Annotation |
|-----------|-----------|
| Read (get, find, search) | `@Transactional(readOnly = true)` |
| Write (create, update, patch, delete) | Class-level `@Transactional` (default) |
| Isolated retry-safe write | `@Transactional(propagation = Propagation.REQUIRES_NEW)` |
| Pessimistic locking | `@Transactional(isolation = Isolation.READ_COMMITTED)` |

## CRUD service skeleton

```java
@Service
@Transactional
@RequiredArgsConstructor
public class CustomerServiceImpl implements CustomerService {

    private final CustomerRepository customerRepository;
    private final CountryRepository countryRepository;
    private final CustomerMapper customerMapper;

    // --- Read ---

    @Override
    @Transactional(readOnly = true)
    public CustomerDto getById(UUID userId, UUID id) {
        CustomerEntity entity = getOrThrow(
                customerRepository.findByIdWithCountry(id),
                "Customer not found: id=" + id);
        return customerMapper.toDto(entity);
    }

    @Override
    @Transactional(readOnly = true)
    public PagedResult<CustomerListItemDto> search(UUID userId, CustomerSearchParams params) {
        Specification<CustomerEntity> spec = CustomerSpecification.withFilters(userId, params);
        Pageable pageable = PageableUtil.of(params.getPage(), params.getLimit(),
                params.getSort(), SortUtil.by("lastName", Sort.Direction.ASC));
        Page<CustomerEntity> page = customerRepository.findAll(spec, pageable);
        return PagedResult.of(page.map(customerMapper::toListItemDto));
    }

    // --- Create ---

    @Override
    public CustomerDto create(UUID userId, CustomerCreateDto dto) {
        UUID id = UUID.randomUUID();
        CustomerEntity entity = customerMapper.toEntity(dto);
        entity.setId(id);
        entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
        customerRepository.save(entity);
        return customerMapper.toDto(entity);
    }

    // --- Update ---

    @Override
    public CustomerDto update(UUID userId, UUID id, CustomerUpdateDto dto) {
        CustomerEntity entity = getOrThrow(
                customerRepository.findById(id),
                "Customer not found: id=" + id);
        customerMapper.updateEntity(dto, entity);
        entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
        customerRepository.save(entity);
        return customerMapper.toDto(entity);
    }

    // --- Patch ---

    @Override
    public CustomerDto patch(UUID userId, UUID id, CustomerPatchDto dto) {
        CustomerEntity entity = getOrThrow(
                customerRepository.findById(id),
                "Customer not found: id=" + id);
        customerMapper.patchEntity(dto, entity);
        if (dto.getCountryId() != null) {
            entity.setCountry(countryRepository.getReferenceById(dto.getCountryId().getValue()));
        }
        customerRepository.save(entity);
        return customerMapper.toDto(entity);
    }

    // --- Delete ---

    @Override
    public void delete(UUID userId, UUID id) {
        customerRepository.findById(id).ifPresent(customerRepository::delete);
    }

    // --- Helpers ---

    private <T> T getOrThrow(Optional<T> optional, String message) {
        return optional.orElseThrow(() -> new ResourceNotFoundException(message));
    }
}
```

## Idempotent delete

DELETE is always idempotent — return silently whether the resource exists or not:

```java
public void delete(UUID userId, UUID id) {
    customerRepository.findById(id).ifPresent(customerRepository::delete);
}
```

With business-rule guard — check only if resource is found:

```java
public void delete(UUID userId, UUID id) {
    customerRepository.findById(id).ifPresent(entity -> {
        if (entity.getStatus() != AccountStatus.INACTIVE) {
            throw new ConflictException("Cannot delete: customer must be INACTIVE first");
        }
        customerRepository.delete(entity);
    });
}
```

## Ownership verification

Multi-tenant operations verify that the resource belongs to the authenticated user:

```java
@Override
@Transactional(readOnly = true)
public CustomerDto getById(UUID userId, UUID id) {
    CustomerEntity entity = getOrThrow(
            customerRepository.findByIdAndUserId(id, userId),
            "Customer not found: id=" + id);
    return customerMapper.toDto(entity);
}
```

Repository method `findByIdAndUserId` returns `Optional.empty()` if the resource exists but belongs to another user — the caller gets a 404, not a 403. This prevents resource enumeration.

## Mapper usage

Services call mapper methods for Entity ↔ DTO conversion. See `references/mapper.md` for the mapper interface, method naming, and ignore rules.

## FK assignment

Use `getReferenceById()` for setting foreign keys — no SELECT needed:

```java
entity.setCountry(countryRepository.getReferenceById(dto.getCountryId()));
```

See `references/jpa.md` for details on `getReferenceById` vs `findById`.

## Non-failing side effects

Notification sends and other side effects must not fail the main operation:

```java
@Override
public CustomerDto create(UUID userId, CustomerCreateDto dto) {
    // ... create and save entity ...

    try {
        notificationService.sendWelcomeEmail(entity);
    } catch (Exception e) {
        // log and swallow — see references/logging.md
    }

    return customerMapper.toDto(entity);
}
```

## Services accept DTOs only

Services never accept transport-specific objects. Each entry point (controller, Kafka consumer, scheduler) converts to service DTOs before calling:

```java
// ✅ Good — service is transport-agnostic
public CustomerDto create(UUID userId, CustomerCreateDto dto) { ... }

// ❌ Bad — leaks HTTP concern
public CustomerDto create(UUID userId, HttpServletRequest request) { ... }
```
