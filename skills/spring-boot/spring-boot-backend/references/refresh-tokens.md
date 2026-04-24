# Refresh Tokens

Spring Boot implementation of the `rest-api-design` skill refresh-token invariants — **rotation on every use**, **family revocation on reuse**, **scope-limited cookie**, **server-side revocation on logout**, **hashed storage**.

**Opt-in feature.** Enable when short-lived access tokens with periodic refresh are preferred to a longer-lived access token. Self-contained — table, entity, service, wiring can be added or removed without touching the rest of the stack. Pairs with `references/security-jwt.md` (builds on `TokenHashUtil`, `JwtService`, cookie helpers).

## Flow at a glance

```
Login        → access_token (/) + refresh_token (/api/v1/auth)
...access token expires...
POST /refresh → new access_token + rotated refresh_token
                (previous refresh marked revoked, linked via replaced_by)
Logout       → refresh_token revoked server-side; both cookies cleared
Reuse of
a revoked    → 401 + ALL user's refresh tokens revoked (family revocation)
refresh
```

## Database schema (Liquibase)

Local to this feature. Register in the project's changelog when enabling:

```sql
--liquibase formatted sql

--changeset author:refresh-tokens-0001-create
CREATE TABLE refresh_tokens (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID         NOT NULL,
    token_hash     VARCHAR(64)  NOT NULL,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at     TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at     TIMESTAMP WITH TIME ZONE,
    replaced_by_id UUID,
    CONSTRAINT fk_refresh_tokens_user        FOREIGN KEY (user_id)        REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT fk_refresh_tokens_replaced_by FOREIGN KEY (replaced_by_id) REFERENCES refresh_tokens (id),
    CONSTRAINT uk_refresh_tokens_token_hash  UNIQUE (token_hash)
);

CREATE INDEX idx_refresh_tokens_user_id    ON refresh_tokens (user_id);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens (expires_at);

--rollback DROP TABLE refresh_tokens;
```

- `token_hash` stores `Base64(SHA-256(plaintext))` — 44 chars with padding, never the plaintext.
- `replaced_by_id` is the forward link for rotation chains — each revoked token points at the token that superseded it. Used by the family-revocation logic.
- `user_id` cascades on user deletion — no orphan refresh tokens after account removal.
- `expires_at` is indexed for the scheduled cleanup.

## Entity

```java
@Entity
@Table(name = "refresh_tokens")
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshTokenEntity {

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id")
    @ToString.Exclude
    private UserEntity user;

    @Column(name = "token_hash", nullable = false, unique = true)
    private String tokenHash;

    @CreatedDate
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "replaced_by_id")
    @ToString.Exclude
    private RefreshTokenEntity replacedBy;

    public boolean isRevoked() {
        return revokedAt != null;
    }

    public boolean isExpired() {
        return Instant.now().isAfter(expiresAt);
    }
}
```

## Repository

```java
public interface RefreshTokenRepository extends JpaRepository<RefreshTokenEntity, UUID> {

    Optional<RefreshTokenEntity> findByTokenHash(String tokenHash);

    long deleteByExpiresAtBefore(Instant threshold);

    @Modifying
    @Query("UPDATE RefreshTokenEntity rt SET rt.revokedAt = :now " +
           "WHERE rt.user.id = :userId AND rt.revokedAt IS NULL")
    int revokeAllActiveForUser(@Param("userId") UUID userId, @Param("now") Instant now);
}
```

## Service

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class RefreshTokenService {

    private static final Duration TTL = Duration.ofDays(30);

    private final RefreshTokenRepository repository;
    private final UserRepository userRepository;

    @Transactional
    public String issueFor(UUID userId) {
        String plaintext = TokenHashUtil.generateToken();
        RefreshTokenEntity entity = RefreshTokenEntity.builder()
            .id(UUID.randomUUID())
            .user(userRepository.getReferenceById(userId))
            .tokenHash(TokenHashUtil.hash(plaintext))
            .expiresAt(Instant.now().plus(TTL))
            .build();
        repository.save(entity);
        return plaintext;                // goes to the client (cookie)
    }

    /**
     * Validates a refresh token and rotates it:
     *  - Valid           → revoke, issue replacement, link via replacedBy, return new plaintext.
     *  - Revoked (reuse) → revoke the entire family and reject.
     *  - Expired / miss  → reject.
     */
    @Transactional
    public RotationResult rotate(String plaintext) {
        String hash = TokenHashUtil.hash(plaintext);
        RefreshTokenEntity existing = repository.findByTokenHash(hash)
            .orElseThrow(() -> new InvalidRefreshTokenException("Invalid refresh token"));

        if (existing.isRevoked()) {
            // REUSE ATTACK — someone is presenting a token that was already rotated.
            // Revoke every active refresh token for the user; force re-authentication.
            int revoked = repository.revokeAllActiveForUser(existing.getUser().getId(), Instant.now());
            log.warn("Refresh token reuse detected: userId={}, revoked={}",
                existing.getUser().getId(), revoked);
            throw new InvalidRefreshTokenException("Refresh token reuse detected");
        }
        if (existing.isExpired()) {
            throw new InvalidRefreshTokenException("Refresh token expired");
        }

        String newPlaintext = TokenHashUtil.generateToken();
        RefreshTokenEntity replacement = RefreshTokenEntity.builder()
            .id(UUID.randomUUID())
            .user(existing.getUser())
            .tokenHash(TokenHashUtil.hash(newPlaintext))
            .expiresAt(Instant.now().plus(TTL))
            .build();
        repository.save(replacement);

        existing.setRevokedAt(Instant.now());
        existing.setReplacedBy(replacement);

        return new RotationResult(existing.getUser().getId(), newPlaintext);
    }

    @Transactional
    public void revoke(String plaintext) {
        if (plaintext == null || plaintext.isBlank()) return;
        repository.findByTokenHash(TokenHashUtil.hash(plaintext))
            .filter(t -> !t.isRevoked())
            .ifPresent(t -> t.setRevokedAt(Instant.now()));
    }

    @Transactional
    public void revokeAllForUser(UUID userId) {
        int revoked = repository.revokeAllActiveForUser(userId, Instant.now());
        log.info("Revoked all refresh tokens for user: userId={}, count={}", userId, revoked);
    }

    @Scheduled(cron = "0 0 3 * * *")     // daily at 03:00
    @Transactional
    public void cleanupExpired() {
        long deleted = repository.deleteByExpiresAtBefore(Instant.now());
        if (deleted > 0) {
            log.info("Cleaned up expired refresh tokens: count={}", deleted);
        }
    }

    public record RotationResult(UUID userId, String refreshTokenPlaintext) {}
}
```

Requires `@EnableScheduling` somewhere in `@Configuration`.

## Controller integration

Login issues both cookies; `/refresh` rotates; logout revokes the server-side record and clears both cookies.

```java
@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final JwtService jwtService;
    private final RefreshTokenService refreshTokenService;
    private final UserRepository userRepository;
    private final LoginAttemptService loginAttemptService;
    private final JwtProperties jwtProperties;

    @PostMapping("/login")
    public ResponseEntity<Void> login(@Valid @RequestBody LoginDto dto, HttpServletRequest request) {
        // ... lockout + credentials + account state (see security-jwt.md AuthController) ...
        User user = /* verified + ACTIVE */;

        String accessToken  = jwtService.generateToken(user);
        String refreshToken = refreshTokenService.issueFor(user.getId());

        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, accessTokenCookie(accessToken).toString())
            .header(HttpHeaders.SET_COOKIE, refreshTokenCookie(refreshToken).toString())
            .build();
    }

    @PostMapping("/refresh")
    public ResponseEntity<Void> refresh(HttpServletRequest request) {
        String refreshToken = extractCookie(request, "refresh_token")
            .orElseThrow(() -> new InvalidRefreshTokenException("Refresh token missing"));

        RefreshTokenService.RotationResult rotated = refreshTokenService.rotate(refreshToken);

        User user = userRepository.findById(rotated.userId())
            .orElseThrow(() -> new InvalidRefreshTokenException("User no longer exists"));

        String newAccess = jwtService.generateToken(user);

        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, accessTokenCookie(newAccess).toString())
            .header(HttpHeaders.SET_COOKIE, refreshTokenCookie(rotated.refreshTokenPlaintext()).toString())
            .build();
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletRequest request) {
        extractCookie(request, "refresh_token").ifPresent(refreshTokenService::revoke);

        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, expiredAccessTokenCookie().toString())
            .header(HttpHeaders.SET_COOKIE, expiredRefreshTokenCookie().toString())
            .build();
    }
}
```

## Cookie scoping

Access and refresh cookies have **different paths** — refresh never travels on product endpoints.

```java
private ResponseCookie accessTokenCookie(String token) {
    return ResponseCookie.from("access_token", token)
        .httpOnly(true).secure(true).sameSite("Lax")
        .path("/")                                           // sent with every API request
        .maxAge(Duration.ofMillis(jwtProperties.getExpirationMs()))
        .build();
}

private ResponseCookie refreshTokenCookie(String token) {
    return ResponseCookie.from("refresh_token", token)
        .httpOnly(true).secure(true).sameSite("Lax")
        .path("/api/v1/auth")                                // scope-limited per contract
        .maxAge(Duration.ofDays(30))
        .build();
}

private ResponseCookie expiredAccessTokenCookie() {
    return ResponseCookie.from("access_token", "")
        .httpOnly(true).secure(true).sameSite("Lax")
        .path("/").maxAge(0).build();
}

private ResponseCookie expiredRefreshTokenCookie() {
    return ResponseCookie.from("refresh_token", "")
        .httpOnly(true).secure(true).sameSite("Lax")
        .path("/api/v1/auth").maxAge(0).build();
}
```

`Path=/api/v1/auth` means the browser sends `refresh_token` only on `/api/v1/auth/**` requests — never on `/api/v1/customers/*` or any product endpoint. Reduces exposure if a product endpoint leaks data via XSS or misconfigured logging.

## Reuse-detection semantics

The "reuse" path in `rotate()` is the security-critical branch. Normal clients follow one chain: `A rotated → B, B rotated → C, ...`. Only the most recent token is active; earlier ones are revoked.

If a client presents `A` after `A` was rotated, two possibilities:

1. The **attacker** has stolen `A` plaintext and is trying to use it. The user is on `B` or later.
2. The **user** replayed an old request (rare but possible — double-submitted `/refresh`).

The server cannot distinguish the two safely, so it treats the reuse as compromise: **revoke the entire user's refresh-token space** (every active row where `user_id = X AND revoked_at IS NULL`). Both attacker and legitimate user are forced to re-authenticate with password — the attack window closes.

This is strict but aligned with the contract. The alternative ("grace period for recently rotated tokens") opens a race window that attackers exploit.

## Exception + handler

```java
public class InvalidRefreshTokenException extends RuntimeException {
    public InvalidRefreshTokenException(String message) { super(message); }
}
```

Add to `GlobalExceptionHandler`:

```java
@ExceptionHandler(InvalidRefreshTokenException.class)
@ResponseStatus(HttpStatus.UNAUTHORIZED)
public ErrorDto handleInvalidRefreshToken(InvalidRefreshTokenException ex) {
    return ErrorDto.builder().code("UNAUTHORIZED").message("Invalid refresh token").build();
}
```

Uniform `401 UNAUTHORIZED` with generic message — anti-enumeration applies here too: the client gets the same response for "missing", "expired", "revoked/reuse", "no such user". The server logs distinguish them.

## Status code summary

| Code | Condition | `ErrorDto.code` |
|------|-----------|-----------------|
| `204 No Content` | Successful login / refresh / logout — tokens in cookies, no body | — |
| `401 Unauthorized` | Missing, invalid, expired, revoked, or reused refresh token | `UNAUTHORIZED` |

## Optional configuration

Refresh TTL lives in `application.yml` (shared with `JwtProperties.refresh-expiration-ms`):

```yaml
app:
  jwt:
    expiration-ms: 900000              # 15 min access token when refresh is used
    refresh-expiration-ms: 2592000000  # 30 days refresh token
```

With refresh in place, shorten the access-token lifetime — that's the whole point of the flow. 15 min is a reasonable default for web SPAs; CLI/mobile clients may pick longer.

## Making it optional

Source-level opt-in — the feature is a copyable unit:

- `refresh_tokens` table (migration in this file)
- `RefreshTokenEntity`, `RefreshTokenRepository`, `RefreshTokenService`
- `InvalidRefreshTokenException` + handler
- `POST /refresh` endpoint + login/logout cookie wiring

Omit all of it and the application uses a longer-lived access token without refresh — also contract-compliant.
