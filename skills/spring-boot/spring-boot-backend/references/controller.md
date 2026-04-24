# Controller Conventions

Class structure, CRUD skeleton, response conventions, and authentication resolution.

## BaseController

```java
@RequiredArgsConstructor
public abstract class BaseController {

    protected final UserService userService;

    protected UUID getCurrentUserId(UserDetails userDetails) {
        return userService.getCurrentUserId(userDetails.getUsername());
    }
}
```

Controllers that need authenticated user ID extend `BaseController`. Reference-data controllers (no auth context needed) use `@RequiredArgsConstructor` directly.

## Class-level annotations

```java
@RestController
@RequestMapping("/api/v1/customers")
@Validated
@Tag(name = "Customers", description = "Customer management")
@SecurityRequirement(name = "Bearer Authentication")
public class CustomerController extends BaseController {
```

| Annotation | Purpose |
|---|---|
| `@RestController` | Combines `@Controller` + `@ResponseBody` |
| `@RequestMapping("/api/v1/{resource}")` | Base path — plural noun, kebab-case |
| `@Validated` | Enables `@Valid` on `@ModelAttribute` parameters |
| `@Tag` | Swagger grouping |
| `@SecurityRequirement` | Swagger auth indicator |

## Constructor injection

Controllers extending `BaseController` — explicit constructor passing `UserService` to super:

```java
private final CustomerService customerService;

public CustomerController(UserService userService, CustomerService customerService) {
    super(userService);
    this.customerService = customerService;
}
```

Standalone controllers (no auth context) — `@RequiredArgsConstructor`:

```java
@RestController
@RequestMapping("/api/v1/currencies")
@RequiredArgsConstructor
public class CurrencyController {
    private final CurrencyService currencyService;
}
```

## CRUD controller skeleton

Complete controller with all standard endpoints. Method order: GET, POST, PUT, PATCH, DELETE.

```java
@RestController
@RequestMapping("/api/v1/customers")
@Validated
@Tag(name = "Customers", description = "Customer management")
@SecurityRequirement(name = "Bearer Authentication")
public class CustomerController extends BaseController {

    private final CustomerService customerService;

    public CustomerController(UserService userService, CustomerService customerService) {
        super(userService);
        this.customerService = customerService;
    }

    // --- GET (list) ---

    @GetMapping(produces = "application/vnd.api.customer.list+json")
    @Operation(summary = "Get customers as list")
    public ResponseEntity<PagedResponse<CustomerListItemDto>> getAsList(
            @AuthenticationPrincipal UserDetails userDetails,
            @Valid @ModelAttribute CustomerSearchParams params) {
        UUID userId = getCurrentUserId(userDetails);
        PagedResult<CustomerListItemDto> result = customerService.search(userId, params);
        return ResponseEntity.ok(PagedResponse.of(result));
    }

    // --- GET (lookup) ---

    @GetMapping(produces = "application/vnd.api.customer.lookup+json")
    @Operation(summary = "Get customers as lookup")
    public ResponseEntity<List<CustomerLookupDto>> getAsLookup(
            @AuthenticationPrincipal UserDetails userDetails,
            @Valid @ModelAttribute CustomerSearchParams params) {
        UUID userId = getCurrentUserId(userDetails);
        PagedResult<CustomerLookupDto> result = customerService.searchAsLookup(userId, params);
        return ResponseEntity.ok()
                .header("X-Total-Count", String.valueOf(result.total()))
                .body(result.content());
    }

    // --- GET (by ID) ---

    @GetMapping(value = "/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    @Operation(summary = "Get customer by ID")
    public ResponseEntity<CustomerDto> getById(
            @AuthenticationPrincipal UserDetails userDetails,
            @PathVariable UUID id) {
        UUID userId = getCurrentUserId(userDetails);
        return ResponseEntity.ok(customerService.getById(userId, id));
    }

    // --- POST ---

    @PostMapping
    @Operation(summary = "Create customer")
    public ResponseEntity<CustomerDto> create(
            @AuthenticationPrincipal UserDetails userDetails,
            @Valid @RequestBody CustomerCreateDto dto) {
        UUID userId = getCurrentUserId(userDetails);
        CustomerDto created = customerService.create(userId, dto);
        return ResponseEntity.status(HttpStatus.CREATED)
                .header("Location", "/api/v1/customers/" + created.getId())
                .body(created);
    }

    // --- PUT ---

    @PutMapping("/{id}")
    @Operation(summary = "Update customer")
    public ResponseEntity<CustomerDto> update(
            @AuthenticationPrincipal UserDetails userDetails,
            @PathVariable UUID id,
            @Valid @RequestBody CustomerUpdateDto dto) {
        UUID userId = getCurrentUserId(userDetails);
        return ResponseEntity.ok(customerService.update(userId, id, dto));
    }

    // --- PATCH ---

    @PatchMapping("/{id}")
    @Operation(summary = "Partial update customer")
    public ResponseEntity<CustomerDto> patch(
            @AuthenticationPrincipal UserDetails userDetails,
            @PathVariable UUID id,
            @Valid @RequestBody CustomerPatchDto dto) {
        UUID userId = getCurrentUserId(userDetails);
        return ResponseEntity.ok(customerService.patch(userId, id, dto));
    }

    // --- DELETE ---

    @DeleteMapping("/{id}")
    @Operation(summary = "Delete customer")
    public ResponseEntity<Void> delete(
            @AuthenticationPrincipal UserDetails userDetails,
            @PathVariable UUID id) {
        UUID userId = getCurrentUserId(userDetails);
        customerService.delete(userId, id);
        return ResponseEntity.noContent().build();
    }
}
```

## ResponseEntity conventions

| Endpoint | Status | Body | Headers |
|----------|--------|------|---------|
| GET (list) | 200 OK | `PagedResponse<ListItemDto>` | — |
| GET (lookup) | 200 OK | `List<LookupDto>` | `X-Total-Count` |
| GET by ID | 200 OK | DTO | — |
| POST | 201 Created | Created DTO | `Location: /api/v1/{resource}/{id}` |
| PUT | 200 OK | Updated DTO | — |
| PATCH | 200 OK | Updated DTO | — |
| DELETE | 204 No Content | — | — |

Always return `ResponseEntity<T>`, never raw DTO.

## Authentication resolution

Resolve `userId` at the controller level via `@AuthenticationPrincipal`:

```java
@GetMapping("/{id}")
public ResponseEntity<CustomerDto> getById(
        @AuthenticationPrincipal UserDetails userDetails,
        @PathVariable UUID id) {
    UUID userId = getCurrentUserId(userDetails);
    return ResponseEntity.ok(customerService.getById(userId, id));
}
```

Services never access `SecurityContext` — they receive `userId` as a parameter.

## Request binding

| Source | Annotation | Validation | Example |
|--------|-----------|------------|---------|
| JSON body | `@RequestBody` | `@Valid` | `@Valid @RequestBody CustomerCreateDto dto` |
| Path segment | `@PathVariable` | Type-safe (`UUID`) | `@PathVariable UUID id` |
| Query params (object) | `@ModelAttribute` | `@Valid` | `@Valid @ModelAttribute CustomerSearchParams params` |
| Single query param | `@RequestParam` | `@NotBlank`, etc. | `@RequestParam String email` |

`@Valid` on `@ModelAttribute` requires `@Validated` on the controller class.

## /me vs /{id} path conflict

When a controller has both `/me` (current user) and `/{id}` (by ID) endpoints, do NOT add `produces` to `/me` — otherwise Spring cannot distinguish the literal path `/me` from the path variable pattern `/{id}`:

```java
// ✅ /me without produces — takes priority over /{id}
@GetMapping("/me")
public ResponseEntity<CustomerDto> getMe(...) { ... }

// /{id} with produces — no conflict
@GetMapping(value = "/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
public ResponseEntity<CustomerDto> getById(...) { ... }
```
