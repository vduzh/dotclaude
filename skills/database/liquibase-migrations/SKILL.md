---
name: liquibase-migrations
description: Liquibase migration conventions — formatted SQL, SQL Style Guide, UUID/TIMESTAMPTZ types, naming, test data with contexts, never IF EXISTS
---

# Liquibase Migration Conventions

Apply these conventions when creating database migrations.

## File Format

Use **formatted SQL** (not XML) for better readability. Place in `db/changelog/changes/*.sql` or `db/changelog/migrations/*.sql`.

## Migration Template

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

## SQL Formatting Rules (SQL Style Guide)

- Opening parenthesis `(` on the same line as `CREATE TABLE`
- **4 spaces** indentation
- Column names, types, and constraints **aligned in columns**
- SQL keywords in **UPPERCASE** (`CREATE TABLE`, `NOT NULL`, `VARCHAR`)
- Object names in **lowercase with snake_case** (`customer_id`, `created_at`)
- Named constraints (`CONSTRAINT fk_...`, `CONSTRAINT uk_...`, `CONSTRAINT chk_...`)
- Indexes in **separate statements** after table creation

## Data Types

| Purpose | Type | Notes |
|---------|------|-------|
| Primary key | `UUID` | `DEFAULT gen_random_uuid()` for auto-generation |
| Timestamps | `TIMESTAMP WITH TIME ZONE` | **Never** plain `TIMESTAMP` — prevents timezone issues when server timezone changes |
| Enums | `VARCHAR(N)` + `CHECK` | Not PostgreSQL `ENUM` type — easier to migrate |
| Text | `VARCHAR(N)` | Always specify max length |

## Schema Management

- Schema managed by **Liquibase only** (NOT Hibernate `ddl-auto`)
- Set `spring.jpa.hibernate.ddl-auto: validate` (verify schema matches entities)
- Add changeset to `db.changelog-master.xml` (or `.yaml`)
- Always include `--rollback` statement

## Never Use IF EXISTS / IF NOT EXISTS

```sql
-- ❌ Bad — masks real problems
CREATE TABLE IF NOT EXISTS customers (...);

-- ✅ Good — Liquibase tracks executed changesets
CREATE TABLE customers (...);
```

Liquibase tracks executed changesets and prevents re-execution. `IF NOT EXISTS` / `IF EXISTS` guards mask real problems (manual schema changes, missing changelog records) instead of failing fast.

## Test Data

Create separate migration for test data with context:

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

- Insert minimum **3 test entities** per table
- Configure `liquibase.contexts` per profile: `dev` for `application-dev.yml`, `test` for `application-test.yml`
