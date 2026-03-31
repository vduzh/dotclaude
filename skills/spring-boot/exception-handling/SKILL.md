---
name: exception-handling
description: Exception handling strategy — dedicated exception classes, Exception vs Optional, @ControllerAdvice, never use standard Java exceptions for HTTP mapping
---

# Exception Handling

Apply these patterns for exception handling in Spring Boot REST APIs.

## Dedicated Exception Classes

Use dedicated exception classes for business semantics. **Never** use `IllegalStateException`/`IllegalArgumentException` for HTTP error mapping — standard Java exceptions that escape to the generic handler become 500, which is correct for programming errors.

```java
public class ResourceNotFoundException extends RuntimeException {
    public ResourceNotFoundException(String message) { super(message); }
}

public class ConflictException extends RuntimeException {
    public ConflictException(String message) { super(message); }
}

public class BadRequestException extends RuntimeException {
    public BadRequestException(String message) { super(message); }
}
```

| Exception | HTTP Status | Use Case |
|-----------|-------------|----------|
| `ResourceNotFoundException` | 404 | Resource not found by ID |
| `BadRequestException` | 400 | Invalid business input (FK validation, etc.) |
| `ConflictException` | 409 | Business conflict ("already exists") |
| `DataIntegrityViolationException` | 409 | DB constraint violation |
| `MethodArgumentNotValidException` | 400 | Bean Validation failures |
| `MethodArgumentTypeMismatchException` | 400 | Invalid path variable (bad UUID, etc.) |
| `AccessDeniedException` | 403 | Insufficient permissions |

## Service Layer: Exception vs Optional

### Throw Exception — for REST endpoints expecting a specific resource

```java
public ProfileDto findById(UUID id) {
    return repository.findById(id)
        .map(mapper::toDto)
        .orElseThrow(() -> new ResourceNotFoundException("Profile not found with id: " + id));
}
```

### Return Optional — for internal logic where absence is valid

```java
public Optional<UserDto> findByEmail(String email) {
    return repository.findByEmail(email).map(mapper::toDto);
}
```

### Decision Table

| Scenario | Return Type | Example |
|----------|-------------|---------|
| REST `GET /resource/{id}` | Throw exception | `findById(id)` |
| REST collection search | Empty list `[]` | `searchProfiles(params)` |
| Internal service logic | `Optional<T>` | `findByEmail(email)` |
| FK validation | `existsById()` | `repository.existsById(id)` |

## Helper Method

```java
protected <T> T getOrThrow(Optional<T> optional, String message) {
    return optional.orElseThrow(() -> new ResourceNotFoundException(message));
}
```

## GlobalExceptionHandler

See the `error-response-format` skill for the complete `@ControllerAdvice` implementation and `ErrorDto` structure.
