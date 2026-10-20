# SK-02 MedInsure Claims Data Warehouse

PostgreSQL Kimball star schema for the MedInsure healthcare claims
capstone project in the SK-02 SQL and Data Modeling Specialist track.
`source`, `staging`, `warehouse`, and `audit` are the load path around
that star, not bronze, silver, and gold layers. The model is written up
in `docs/data-model.md`.

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

The runner applies numbered `.sql` files from `sql/` in lexical order.

## Load The Warehouse

`scripts/setup.ps1` applies every numbered SQL file under `sql/` in lexical
order. That creates schemas, tables, views, and load procedures. It does not
generate claims.

`scripts/run_pipeline.ps1` applies that DDL, generates source data, reloads the
warehouse, refreshes the monthly summary, and runs `tests/run_tests.ps1`.
That script fails if a quality check is under 99%, an integrity assertion
breaks, or an analytic view returns no rows. Re-run the tests alone, after a
load, with `./tests/run_tests.ps1`.

```powershell
./scripts/run_pipeline.ps1 -Scale 0.05
```

`-Scale 1` builds the full spec volumes: 500,000 members, 15,000 providers,
2,000,000 claims, and about 7,500,000 service lines. The default `0.05` keeps
the same shape and the full diagnosis and procedure catalogs, with 5% of the
member, provider, and claim volumes, so a local Docker database can finish
the load. Reference data (8 plans, 12,000 diagnosis codes, 8,500 procedure
codes) is always loaded in full.

The generator plants a small number of source defects on purpose: unknown
member ids, unknown provider ids, procedure code `ZZZZZ`, and eight claims
whose provider network date is in the future. The fact load dead-letters the
unknown keys. The data-quality script reports the rest.

Each run writes `logs/pipeline-YYYYMMDD-HHMMSS.log`, which Git ignores. The
terminal still shows the same `CREATE` and `NOTICE` text. The log adds a
timestamp on every line, the database host and port, and for each SQL step
the file or statement, the exit code, and how long it took. A failed step is
marked `ERROR`, including the PostgreSQL message and the PowerShell stack.

Running the pipeline again rebuilds that same population. It truncates the
source tables, calls `warehouse.reset_warehouse_data()` to clear the facts,
dimensions, dead-letter rows, and watermark, then loads from scratch.

To drop the database and start from an empty server:

```powershell
docker compose down -v
docker compose up -d
./scripts/run_pipeline.ps1 -Scale 0.05
```

`-v` deletes the Postgres volume. Leave the pipeline running until it prints
`Warehouse tests passed.`

If PowerShell refuses the script because it is not digitally signed, the
machine policy is `AllSigned`. Allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Open a new terminal afterward. A script downloaded from the internet still
has to be signed. For one run, without changing the policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_pipeline.ps1 -Scale 0.05
```

## Deliverables

| Spec | Where |
|---|---|
| Dimensional model | `docs/data-model.md` |
| ETL design | `docs/etl-design.md` |
| DDL | `sql/03_dimensions/`, `sql/04_facts/` |
| ETL, including SCD Type 2 | `sql/05_etl/` |
| Eight analytic queries | `sql/06_analytics/` |
| Indexes and monthly summary | `sql/07_performance/` |
| Performance write-up | `docs/performance.md` |
| Data-quality checks and results | `tests/data_quality.sql`, `docs/data-quality.md` |

## Status

The dimensional model, ETL design, DDL, analytics, performance write-up,
and data-quality report are in the paths above. `docs/performance.md` and
`docs/data-quality.md` record the scale `0.05` load. Rerun `tests/explain.sql`
and `tests/data_quality.sql` after a new load and refresh those two docs.
