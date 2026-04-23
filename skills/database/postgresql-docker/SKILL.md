---
name: postgresql-docker
description: >
  Set up and manage a local PostgreSQL instance via Docker Compose for development.
  Use this skill when spinning up a fresh database, onboarding a new developer,
  or resetting the local environment before running migrations.
disable-model-invocation: true
argument-hint: "[db-name] (e.g. app-db)"
---

# PostgreSQL via Docker Compose

Apply these patterns when setting up a local PostgreSQL database for development.

## Files

```
project/
├── docker-compose.yml
├── init-db.sql
├── .env                  # actual values (git-ignored)
└── .env.example          # template (committed to git)
```

## Upsert Algorithm

Before creating or modifying any file, check current state:

**`docker-compose.yml`**
- Not exists → create with PostgreSQL service, `app-network`, and `pgdata` volume
- Exists, PostgreSQL service for `{db-name}` already present → stop, nothing to do
- Exists, PostgreSQL absent → add service block, add volume entry, add `app-network` to `networks:` if missing

**`init-db.sql`**
- Not exists → create
- Exists → skip (may contain custom scripts)

**`.env.example`**
- Not exists → create
- Exists, `POSTGRES_PORT` already present → skip
- Exists, absent → append missing variables

**`.gitignore`**
- Not exists → create with `.env`
- Exists, `.env` already listed → skip
- Exists, absent → append `.env`

## docker-compose.yml

```yaml
networks:
  app-network:
    driver: bridge

services:
  postgresql:
    image: postgres:18
    container_name: ${POSTGRES_DB:-{db-name}}-postgresql
    restart: always
    ports:
      - "${POSTGRES_PORT:-5433}:5432"
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_HOST_AUTH_METHOD: trust
    volumes:
      - pgdata:/var/lib/postgresql
      - ./init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    networks:
      - app-network

volumes:
  pgdata:
```

**Key points:**
- **`${POSTGRES_PORT:-5433}`** — configurable port with fallback, avoids conflicts between projects
- **`POSTGRES_HOST_AUTH_METHOD: trust`** — no password for local dev (never in prod)
- **`pgdata` volume** — mounted at `/var/lib/postgresql` (not `/data`): postgres:18+ stores data in a version-specific subdirectory inside, enabling `pg_upgrade --link` across upgrades
- **Network name** — no explicit `name:` so Docker Compose auto-prefixes with project directory, preventing conflicts between independent projects
- **Init script** — runs only on **first startup** (when volume is empty). To re-run: delete the volume

## init-db.sql

Mounted to `/docker-entrypoint-initdb.d/` — PostgreSQL executes all `.sql` files on first init.

```sql
CREATE USER "{db-name}" WITH PASSWORD '{db-name}';
CREATE DATABASE "{db-name}" OWNER "{db-name}";
GRANT ALL PRIVILEGES ON DATABASE "{db-name}" TO "{db-name}";
\connect "{db-name}";
GRANT ALL ON SCHEMA public TO "{db-name}";
```

**Naming convention:** database name = username = password for local dev simplicity.

## .env.example

```env
POSTGRES_PORT=5433
POSTGRES_DB={db-name}
```

## .gitignore

```
.env
```

## Commands

```bash
# First time setup
cp .env.example .env     # then adjust if needed

# Start PostgreSQL (background)
docker compose up -d

# Check logs (verify init script ran)
docker logs {db-name}-postgresql

# Stop (data preserved in volume)
docker compose down

# Stop and DELETE all data (triggers init-db.sql re-run on next start)
docker compose down -v

# Connect via psql
docker exec -it {db-name}-postgresql psql -U {db-name} -d {db-name}

# Connect from host (if psql installed locally)
psql -h localhost -p ${POSTGRES_PORT:-5433} -U {db-name} -d {db-name}
```

## Resetting the Database

When you need a clean database (re-run init + migrations):

```bash
docker compose down -v && docker compose up -d
```
