---
name: exception-handling
description: Exception handling in Spring Boot — dedicated exceptions, GlobalExceptionHandler with @ControllerAdvice, ErrorDto, Exception vs Optional pattern
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

## ErrorDto

```java
@Data
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(name = "Error")
public class ErrorDto {
    private String code;
    private String message;
    private Map<String, String> details;  // only for validation errors
}
```

## GlobalExceptionHandler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorDto handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> details = new LinkedHashMap<>();
        ex.getBindingResult().getAllErrors().forEach(error -> {
            String field = error instanceof FieldError fe ? fe.getField() : error.getObjectName();
            details.putIfAbsent(field, error.getDefaultMessage());
        });
        return ErrorDto.builder()
            .code("VALIDATION_ERROR")
            .message("Request validation failed")
            .details(details)
            .build();
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ErrorDto handleNotFound(ResourceNotFoundException ex) {
        return ErrorDto.builder().code("NOT_FOUND").message(ex.getMessage()).build();
    }

    @ExceptionHandler(ConflictException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ErrorDto handleConflict(ConflictException ex) {
        return ErrorDto.builder().code("CONFLICT").message(ex.getMessage()).build();
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ErrorDto handleDataIntegrity(DataIntegrityViolationException ex) {
        log.error("Data integrity violation", ex);
        return ErrorDto.builder().code("CONFLICT").message("Data integrity violation").build();
    }

    @ExceptionHandler(BadRequestException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorDto handleBadRequest(BadRequestException ex) {
        return ErrorDto.builder().code("BAD_REQUEST").message(ex.getMessage()).build();
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ErrorDto handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return ErrorDto.builder().code("BAD_REQUEST").message("Invalid parameter: " + ex.getName()).build();
    }

    @ExceptionHandler(AccessDeniedException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public ErrorDto handleAccessDenied(AccessDeniedException ex) {
        return ErrorDto.builder().code("FORBIDDEN").message("Access denied").build();
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ErrorDto handleGeneric(Exception ex) {
        log.error("Unexpected error", ex);
        return ErrorDto.builder().code("INTERNAL_ERROR").message("Internal server error").build();
    }
}
```

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

## Delete — Idempotent Pattern

```java
public void deleteXxx(UUID id) {
    repository.findById(id).ifPresent(entity -> {
        repository.delete(entity);
        log.info("Deleted xxx with ID: {}", id);
    });
}
```

With business rules:
```java
public void deletePaymentMethod(UUID coachId, UUID paymentMethodId) {
    paymentMethodRepository.findByIdAndCoachId(paymentMethodId, coachId)
        .ifPresent(paymentMethod -> {
            if (subscriptionRepository.existsByPaymentMethodId(paymentMethodId)) {
                throw new ConflictException("Cannot delete: assigned to subscriptions");
            }
            paymentMethodRepository.delete(paymentMethod);
        });
}
```

> Business checks are only performed if the resource is found.
