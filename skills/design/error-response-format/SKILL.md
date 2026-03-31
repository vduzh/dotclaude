---
name: error-response-format
description: Standardized error response format — ErrorDto with code/message/details, field-level validation errors, consistent structure across all endpoints
---

# Error Response Format

Apply this format for all error responses in REST APIs.

## ErrorDto Structure

```java
@Data
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(name = "Error")
public class ErrorDto {
    @Schema(description = "Error code", example = "VALIDATION_ERROR")
    private String code;

    @Schema(description = "Error message", example = "Request validation failed")
    private String message;

    @Schema(description = "Field-level error details")
    private Map<String, String> details;
}
```

## Error Codes

| Code | HTTP Status | When |
|------|-------------|------|
| `VALIDATION_ERROR` | 400 | Bean Validation failures |
| `BAD_REQUEST` | 400 | Invalid input (type mismatch, bad UUID, etc.) |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Business conflict or DB constraint violation |
| `FORBIDDEN` | 403 | Access denied |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

## Validation Error Response

Validation errors include `details` — a map of field-level errors:

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Request validation failed",
  "details": {
    "firstName": "First name is required",
    "lastName": "Last name must be at most 50 characters"
  }
}
```

- Field-level errors (`@NotBlank`, `@Size`) are keyed by field name
- Class-level errors (`@NotEmptyPatch`) are keyed by object name
- First error per field wins (`putIfAbsent`) — avoids duplicate messages

## Non-Validation Error Response

`details` is `null` (omitted from JSON via `@JsonInclude(NON_NULL)`):

```json
{ "code": "NOT_FOUND", "message": "Profile not found with id: 550e8400-..." }
```

```json
{ "code": "CONFLICT", "message": "User with this email already exists" }
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
