# Liquibase Migration Conventions

Formatted SQL changeset format, SQL Style Guide, rollback, test data with contexts.

For the `spring.jpa.hibernate.ddl-auto: validate` setting, see `references/jpa.md`.

## Migration template

```sql
--liquibase formatted sql

--changeset author:change-id
CREATE TABLE customers (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(255) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    status     VARCHAR(20)  NOT NULL CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_customers_coach FOREIGN KEY (coach_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_customers_email ON customers(email);

--rollback DROP TABLE customers;
```

## SQL formatting rules

- Opening `(` on the same line as `CREATE TABLE`
- 4-space indentation
- Column names, types, and constraints aligned in columns
- SQL keywords in UPPERCASE (`CREATE TABLE`, `NOT NULL`, `VARCHAR`)
- Object names in lowercase with snake_case (`customer_id`, `created_at`)
- Named constraints: `CONSTRAINT fk_...`, `CONSTRAINT uk_...`, `CONSTRAINT chk_...`
- Indexes in separate statements after table creation
- Always include `--rollback` statement

## Data types

| Purpose | Type | Notes |
|---------|------|-------|
| Primary key | `UUID` | `DEFAULT gen_random_uuid()` for auto-generation |
| Timestamps | `TIMESTAMP WITH TIME ZONE` | Never plain `TIMESTAMP` |
| Enums | `VARCHAR(N)` + `CHECK` | Not PostgreSQL `ENUM` — easier to migrate |
| Text | `VARCHAR(N)` | Always specify max length |

## Never use IF EXISTS / IF NOT EXISTS

Liquibase tracks executed changesets and prevents re-execution. Guards mask real problems instead of failing fast:

```sql
-- ❌ Bad
CREATE TABLE IF NOT EXISTS customers (...);

-- ✅ Good
CREATE TABLE customers (...);
```

## Test data with contexts

```sql
--liquibase formatted sql

--changeset author:test-data context:dev,test
INSERT INTO customers (id, name, email, status)
VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'John Doe', 'john@example.com', 'active'),
    ('550e8400-e29b-41d4-a716-446655440002', 'Jane Smith', 'jane@example.com', 'active'),
    ('550e8400-e29b-41d4-a716-446655440003', 'Bob Wilson', 'bob@example.com', 'inactive');

--rollback DELETE FROM customers WHERE id IN ('550e8400-...', '550e8400-...', '550e8400-...');
```

- Insert minimum 3 test entities per table
- Configure `liquibase.contexts` per profile: `dev` in `application-dev.yml`, `test` in `application-test.yml`

## File location

Place migrations in `db/changelog/changes/*.sql` or `db/changelog/migrations/*.sql`. Register in `db.changelog-master.xml` (or `.yaml`).
