# Liquibase Migration Conventions

Formatted SQL changeset format, SQL Style Guide, rollback, test data with contexts.

For the `spring.jpa.hibernate.ddl-auto: validate` setting, see `references/jpa.md`.

## Migration template

```sql
--liquibase formatted sql

--changeset author:change-id
CREATE TABLE countries (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uk_countries_name UNIQUE (name)
);

CREATE INDEX idx_countries_name ON countries (name);

--rollback DROP TABLE countries;
```

## SQL formatting rules

- Opening `(` on the same line as `CREATE TABLE`.
- 4-space indentation.
- Column names, types, and constraints aligned in columns.
- SQL keywords in UPPERCASE (`CREATE TABLE`, `NOT NULL`, `VARCHAR`).
- Object names in lowercase with snake_case (`customer_id`, `created_at`).
- Named constraints: `CONSTRAINT fk_...`, `CONSTRAINT uk_...`, `CONSTRAINT chk_...`.
- Indexes in separate statements after table creation.
- Always include `--rollback` statement.

## Data types

| Purpose | Type | Notes |
|---------|------|-------|
| Primary key | `UUID` | `DEFAULT gen_random_uuid()` for auto-generation |
| Timestamps | `TIMESTAMP WITH TIME ZONE` | Never plain `TIMESTAMP` |
| Enums | `VARCHAR(N)` + `CHECK` | Not PostgreSQL `ENUM` — easier to migrate |
| Text | `VARCHAR(N)` | Always specify max length |
| Nullable column | Omit `NOT NULL` | `UNIQUE` on a nullable column is safe — PostgreSQL treats NULLs as distinct |

## Canonical schema — dictionaries + main entity + join table

Full sequence for the canonical `Customer` + `Country` + `PaymentMethod` domain. Register changesets in FK-dependency order — dictionaries first, main entity next, join table last:

```sql
--liquibase formatted sql

--changeset author:0001-create-countries
CREATE TABLE countries (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uk_countries_name UNIQUE (name)
);

--rollback DROP TABLE countries;

--changeset author:0002-create-payment-methods
CREATE TABLE payment_methods (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT uk_payment_methods_name UNIQUE (name)
);

--rollback DROP TABLE payment_methods;

--changeset author:0003-create-customers
CREATE TABLE customers (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(50)  NOT NULL,
    last_name  VARCHAR(50)  NOT NULL,
    email      VARCHAR(255),
    status     VARCHAR(20)  NOT NULL CHECK (status IN ('ACTIVE', 'INACTIVE')),
    country_id UUID         NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_customers_country FOREIGN KEY (country_id) REFERENCES countries (id),
    CONSTRAINT uk_customers_email UNIQUE (email)
);

CREATE INDEX idx_customers_country_id ON customers (country_id);
CREATE INDEX idx_customers_status     ON customers (status);

--rollback DROP TABLE customers;

--changeset author:0004-create-customer-payment-methods
CREATE TABLE customer_payment_methods (
    customer_id       UUID NOT NULL,
    payment_method_id UUID NOT NULL,
    PRIMARY KEY (customer_id, payment_method_id),
    CONSTRAINT fk_cpm_customer       FOREIGN KEY (customer_id)       REFERENCES customers (id)       ON DELETE CASCADE,
    CONSTRAINT fk_cpm_payment_method FOREIGN KEY (payment_method_id) REFERENCES payment_methods (id)
);

CREATE INDEX idx_cpm_payment_method ON customer_payment_methods (payment_method_id);

--rollback DROP TABLE customer_payment_methods;
```

- `email` is nullable (no `NOT NULL`) per the API contract. `UNIQUE` on a nullable column works correctly in PostgreSQL — NULLs are not equal to each other, so multiple `NULL` emails are allowed.
- `ON DELETE CASCADE` on `customer_id` removes join rows when a customer is deleted. FK to `payment_methods` has no cascade — deleting a dictionary entry while customers reference it raises `foreign_key_violation` → `409 CONFLICT` via `DataIntegrityViolationException`.
- M2M join tables use a composite primary key `(customer_id, payment_method_id)` — no synthetic UUID. The reverse index on `payment_method_id` speeds up "who uses this method?" lookups.

## Never use IF EXISTS / IF NOT EXISTS

Liquibase tracks executed changesets and prevents re-execution. Guards mask real problems instead of failing fast:

```sql
-- ❌ Bad
CREATE TABLE IF NOT EXISTS customers (...);

-- ✅ Good
CREATE TABLE customers (...);
```

## Test data with contexts

Seed dictionaries unconditionally — they are reference data needed in every environment. Seed sample `customers` + join rows only in `dev,test` contexts.

```sql
--changeset author:0100-seed-countries
INSERT INTO countries (id, name) VALUES
    ('660e8400-e29b-41d4-a716-446655440010', 'United States'),
    ('660e8400-e29b-41d4-a716-446655440011', 'Germany'),
    ('660e8400-e29b-41d4-a716-446655440012', 'United Kingdom');

--rollback DELETE FROM countries WHERE id IN ('660e8400-e29b-41d4-a716-446655440010', '660e8400-e29b-41d4-a716-446655440011', '660e8400-e29b-41d4-a716-446655440012');

--changeset author:0101-seed-payment-methods
INSERT INTO payment_methods (id, name) VALUES
    ('770e8400-e29b-41d4-a716-446655440020', 'Credit Card'),
    ('770e8400-e29b-41d4-a716-446655440021', 'Bank Transfer');

--rollback DELETE FROM payment_methods WHERE id IN ('770e8400-e29b-41d4-a716-446655440020', '770e8400-e29b-41d4-a716-446655440021');

--changeset author:0200-seed-customers context:dev,test
INSERT INTO customers (id, first_name, last_name, email, status, country_id) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'John', 'Doe',    'john@example.com', 'ACTIVE',   '660e8400-e29b-41d4-a716-446655440010'),
    ('550e8400-e29b-41d4-a716-446655440002', 'Jane', 'Smith',   NULL,              'ACTIVE',   '660e8400-e29b-41d4-a716-446655440011'),
    ('550e8400-e29b-41d4-a716-446655440003', 'Bob',  'Wilson', 'bob@example.com',  'INACTIVE', '660e8400-e29b-41d4-a716-446655440012');

INSERT INTO customer_payment_methods (customer_id, payment_method_id) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440020'),
    ('550e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440021'),
    ('550e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440020');

--rollback DELETE FROM customer_payment_methods WHERE customer_id IN ('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440003');
--rollback DELETE FROM customers WHERE id IN ('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440003');
```

- Seed at minimum 3 rows per main table — covers list-endpoint, filter, and at least one edge case. Here Jane has `email = NULL` to demonstrate the nullable column.
- Configure `liquibase.contexts` per profile: `dev` in `application-dev.yml`, `test` in `application-test.yml`.

## File location

Place migrations in `db/changelog/changes/*.sql` or `db/changelog/migrations/*.sql`. Register in `db.changelog-master.xml` (or `.yaml`).
