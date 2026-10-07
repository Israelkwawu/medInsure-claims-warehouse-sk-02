# ETL design

The load is a set of PostgreSQL procedures in `sql/05_etl/`. `warehouse.run_etl()` calls them in dependency order. `scripts/run_pipeline.ps1` generates source data, truncates the warehouse, runs that procedure, and refreshes the monthly summary.

```text
seed unknown rows
dim_date, dim_plan, dim_diagnosis, dim_procedure
dim_member, dim_provider
fact_claim
fact_claim_line
refresh mv_monthly_claim_volume
```

Source data is built by `source.generate_synthetic_data(p_scale)` in `sql/02_staging/03_generate_synthetic_data.sql`. Scale `1` is the spec volume. Scale `0.05` is the local load: 25,000 members, 750 providers, 100,008 claims, 375,030 lines. Diagnosis and procedure catalogs stay at full size at every scale.

## Calendar and Type 1 dimensions

`load_dim_date` inserts 2020-01-01 through 2030-12-31 with `generate_series`. The Not Applicable row has a null `calendar_date`, so it stays in place.

`load_dim_plan`, `load_dim_diagnosis`, and `load_dim_procedure` are `INSERT ... ON CONFLICT DO UPDATE` on the natural key. A corrected description or category overwrites the existing surrogate. The `-1` rows are not in the source, so the upsert does not touch them.

## SCD Type 2

`staging.member_history` and `staging.provider_history` number each natural key’s history by `effective_start`. Version 1 is inserted as the current open row (`effective_end = 9999-12-31`, `is_current = true`).

Each later version uses the two-step close-then-insert pattern.

1. Close the current row when a tracked attribute `IS DISTINCT FROM` the new value. `effective_end` becomes the new `effective_start` minus one day, and `is_current` becomes false.
2. Insert the new current row when that natural key no longer has an open version.

Member attributes compared: `plan_id`, `state`, `zip_code`. Provider attributes compared: `network_status`, `specialty`. `IS DISTINCT FROM` treats a change to or from null as a change. If the current row already matches, the close does not fire and the insert finds an open row, so a second run is a no-op.

After the loop, the procedure raises if any natural key has more than one `is_current` row, or if two versions of the same key overlap. `tests/assert_integrity.sql` checks the same conditions. A partial unique index on `(member_id) WHERE is_current` and the provider equivalent enforce the rule in the table.

## fact_claim

The high-water mark is `processed_date`, stored in `audit.etl_watermark`. The next run reads `processed_date >= watermark` so a claim that lands late on the boundary date is still seen. `claim_id` is unique, so a claim already on the fact is skipped. Claim ids still sitting in `audit.etl_dead_letter` are retried even when their processed date is older than the watermark.

For each candidate claim the load left-joins:

- `dim_member` on `member_id` and the service date inside the version range
- `dim_provider` on `provider_id` and the same date test
- `dim_date` twice, for service date and processed date
- `dim_diagnosis` on the diagnosis code

The `-1` placeholder rows are excluded from the member and provider joins, so they cannot absorb a real claim. A missing member, provider, or date is a reject reason. Those rows go to `audit.etl_dead_letter` and the rest of the batch inserts. A missing diagnosis code becomes `diagnosis_key = -1` and the claim still loads.

`plan_key` is taken from the matched member version. `member_responsibility` is allowed minus paid for a paid claim, and zero when the claim is denied.

On the scale `0.05` load this inserted 99,808 claims and rejected 200 (unknown member or unknown provider).

## fact_claim_line

This runs only after the header load. `claim_key`, `member_key`, and `provider_key` come from `fact_claim` matched on the degenerate `claim_id`. Lines whose header was dead-lettered have nothing to join and stay out of the fact. An unknown procedure or diagnosis code uses key `-1`. The source procedure code is kept on the line for the orphan check.

The same load inserted 374,330 lines. The 700 lines that belonged to the 200 rejected claims were not loaded.

## Defects the generator leaves in the source

These are deliberate, so the dead-letter path and the quality report have something to count.

| Defect | Where |
|---|---|
| Unknown member | `claim_id % 1000 = 0` |
| Unknown provider | `claim_id % 1000 = 1` |
| Procedure code `ZZZZZ` | line 1 of `claim_id % 4000 = 2` |
| Network date `2030-01-01` | eight claims on the last provider, Northstar Family Medicine |

The first two are dead-lettered. The procedure code and the future network date load, and the quality checks report them.
