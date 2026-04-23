# Exception Handling

Dedicated exception classes, `GlobalExceptionHandler`, `ErrorDto`, Exception-vs-Optional decision.

## Exception classes

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
            String raw = error instanceof FieldError fe ? fe.getField() : error.getObjectName();
            // class-level constraints bind to the simple class name (e.g. "customerPatchDto") —
            // strip "Dto" suffix so the key matches the @Schema(name = "CustomerPatch") contract
            String field = raw.endsWith("Dto") ? raw.substring(0, raw.length() - 3) : raw;
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

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    @ResponseStatus(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
    public ErrorDto handleUnsupportedMediaType(HttpMediaTypeNotSupportedException ex) {
        return ErrorDto.builder().code("UNSUPPORTED_MEDIA_TYPE").message("Unsupported Content-Type").build();
    }

    @ExceptionHandler(HttpMediaTypeNotAcceptableException.class)
    @ResponseStatus(HttpStatus.NOT_ACCEPTABLE)
    public ErrorDto handleNotAcceptable(HttpMediaTypeNotAcceptableException ex) {
        return ErrorDto.builder().code("NOT_ACCEPTABLE").message("Unsupported Accept header").build();
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ErrorDto handleGeneric(Exception ex) {
        log.error("Unexpected error", ex);
        return ErrorDto.builder().code("INTERNAL_ERROR").message("Internal server error").build();
    }
}
```

For security-specific exceptions (`AccessDeniedException`, `AuthenticationException`, `RateLimitExceededException`, etc.), see `references/security-oauth2.md` or `references/security-jjwt.md`.

## Exception vs Optional

| Scenario | Return type | Example |
|----------|-------------|---------|
| REST `GET /resource/{id}` | Throw exception | `findById(id)` |
| REST collection search | Empty list `[]` | `searchProfiles(params)` |
| Internal service logic | `Optional<T>` | `findByEmail(email)` |
| FK validation | `existsById()` | `repository.existsById(id)` |

```java
// Throw — for REST endpoints expecting a specific resource
public ProfileDto findById(UUID id) {
    return repository.findById(id)
        .map(mapper::toDto)
        .orElseThrow(() -> new ResourceNotFoundException("Profile not found: " + id));
}

// Optional — for internal logic where absence is valid
public Optional<UserDto> findByEmail(String email) {
    return repository.findByEmail(email).map(mapper::toDto);
}
```
