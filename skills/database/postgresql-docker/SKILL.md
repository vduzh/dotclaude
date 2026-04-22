---
name: postgresql-docker
description: Local PostgreSQL via Docker Compose — container setup with .env config, init script for database/user creation, volume persistence, useful commands
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

## .env.example

Committed to git — documents required variables with safe defaults:

```env
POSTGRES_PORT=5433
POSTGRES_DB=app-db
```

Each developer copies to `.env` and adjusts if needed (e.g., port conflict).

## .gitignore

```
.env
```

## docker-compose.yml

```yaml
networks:
  app-network:
    name: app-network
    driver: bridge

services:
  postgresql:
    image: postgres:18
    container_name: ${POSTGRES_DB:-app-db}-postgresql
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
- **`pgdata` volume** — data persists across container restarts
- **Init script** — runs only on **first startup** (when volume is empty). To re-run: delete the volume
- **Named network** — allows other containers to connect by container name

## init-db.sql

Mounted to `/docker-entrypoint-initdb.d/` — PostgreSQL executes all `.sql` files on first init.

```sql
-- Create application user
CREATE USER "app-db" WITH PASSWORD 'app-db';

-- Create application database
CREATE DATABASE "app-db" OWNER "app-db";

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE "app-db" TO "app-db";

-- Grant schema privileges (PostgreSQL 15+ requires explicit schema grant)
\connect "app-db";
GRANT ALL ON SCHEMA public TO "app-db";
```

**Naming convention:** database name = username = password for local dev simplicity.

## Commands

```bash
# First time setup
cp .env.example .env     # then adjust if needed

# Start PostgreSQL (background)
docker compose up -d

# Check logs (verify init script ran)
docker logs app-db-postgresql

# Stop (data preserved in volume)
docker compose down

# Stop and DELETE all data (triggers init-db.sql re-run on next start)
docker compose down -v

# Connect via psql
docker exec -it app-db-postgresql psql -U app-db -d app-db

# Connect from host (if psql installed locally)
psql -h localhost -p ${POSTGRES_PORT:-5433} -U app-db -d app-db
```

## Resetting the Database

When you need a clean database (re-run init + Liquibase migrations):

```bash
docker compose down -v && docker compose up -d
```

Then restart the Spring Boot app — Liquibase will re-apply all migrations to the fresh database.

## Multiple Services (Shared Network)

When multiple microservices share the same PostgreSQL:

```yaml
# In microservice's docker-compose.yml
networks:
  app-network:
    external: true    # connect to existing network
```

Each service gets its own database via its own `init-db.sql`. PostgreSQL container is started once from the infrastructure project.
