# SK-02 MedInsure Claims Data Warehouse

PostgreSQL dimensional warehouse for the MedInsure healthcare claims
capstone project in the SK-02 SQL and Data Modeling Specialist track.

## Project Structure

| Path                  | Purpose                                       |
| --------------------- | --------------------------------------------- |
| `docs/`               | Data model, ETL, and performance deliverables |
| `sql/01_database/`    | Database schemas and extensions               |
| `sql/02_staging/`     | Source-shaped staging tables and loads        |
| `sql/03_dimensions/`  | Dimension DDL                                 |
| `sql/04_facts/`       | Fact DDL                                      |
| `sql/05_etl/`         | Dimension and fact load procedures            |
| `sql/06_analytics/`   | Required analytical queries                   |
| `sql/07_performance/` | Indexes, plans, and materialized views        |
| `data/sample/`        | Small, versioned development fixtures         |
| `data/generated/`     | Large generated data; ignored by Git          |
| `scripts/`            | Data generation and database setup helpers    |
| `tests/`              | Warehouse and data-quality checks             |

## Prerequisites

- Docker Desktop with Compose, or PostgreSQL 15+ with `psql` on `PATH`
- PowerShell 5.1 or PowerShell 7+
- Git

## Quick Setup With Docker

```powershell
Copy-Item .env.example .env
docker compose up -d
./scripts/setup.ps1
```

The default connection is `localhost:5432`, database `medinsure`, user
`medinsure`, and password `medinsure_dev`. Change `.env` for local use; it is
ignored by Git.

Verify the bootstrap:

```powershell
docker compose exec -T postgres psql -U medinsure -d medinsure -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('source','staging','warehouse','audit') ORDER BY schema_name;"
```

Stop the database with `docker compose down`. Add `-v` only when the local
database volume should be deleted.

## Native PostgreSQL Setup

Set `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, and `PGPASSWORD`, create the
database, then run:

```powershell
./scripts/setup.ps1
```

The runner applies numbered `.sql` files from `sql/` in lexical order. This
keeps dependency order explicit as the remaining deliverables are added.

## Status

Project bootstrap is complete. The dimensional model, DDL, ETL, analytics,
performance, and data-quality deliverables are built incrementally under the
paths above.
