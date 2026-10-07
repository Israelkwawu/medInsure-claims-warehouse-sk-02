# Performance

Plans below were captured with `EXPLAIN (ANALYZE, BUFFERS)` on the scale `0.05` warehouse: 99,808 claims in `fact_claim` and 374,330 rows in `fact_claim_line`. The script is `tests/explain.sql`. Query 1 and query 6 both aggregate a large share of the header fact, so a sequential scan is the plan PostgreSQL chooses at this size. The indexes below still exist for selective lookups and for the line-to-header join. Query 6’s monthly summary is what removes the fact scan.

## Index strategy

### fact_claim

| Index | Columns | Type | Query it supports |
|---|---|---|---|
| `fact_claim_pkey` | `claim_key` | B-tree, primary key | Surrogate lookup |
| `uq_fact_claim_claim_id` | `claim_id` | B-tree, unique | Line load and any drill-through on the degenerate claim id |
| `idx_fact_claim_member_key` | `member_key` | B-tree | Member-scoped claim history, cohort join |
| `idx_fact_claim_provider_key` | `provider_key` | B-tree | Required foreign-key index; provider denial and network queries |
| `idx_fact_claim_plan_key` | `plan_key` | B-tree | Utilization by plan |
| `idx_fact_claim_diagnosis_key` | `primary_diagnosis_key` | B-tree | Diagnosis-category spend |
| `idx_fact_claim_service_date_key` | `service_date_key` | B-tree | Service-month trends and year filters |
| `idx_fact_claim_processed_date_key` | `processed_date_key` | B-tree | Processed-month reporting |
| `idx_fact_claim_provider_service_paid` | `provider_key`, `service_date_key` INCLUDE (`total_paid`, `claim_status`) | B-tree, covering | Provider paid amount by service period (queries 1 and 8) without a heap fetch when the planner uses it |

### fact_claim_line

| Index | Columns | Type | Query it supports |
|---|---|---|---|
| `fact_claim_line_pkey` | `claim_line_key` | B-tree, primary key | Surrogate lookup |
| `uq_fact_claim_line_natural` | `claim_id`, `line_number` | B-tree, unique | Idempotent line reload; referential check on the degenerate claim id |
| `idx_fact_claim_line_claim_key` | `claim_key` | B-tree | Lines for one header |
| `idx_fact_claim_line_member_key` | `member_key` | B-tree | Line-level member history |
| `idx_fact_claim_line_provider_key` | `provider_key` | B-tree | Line-level provider history |
| `idx_fact_claim_line_procedure_key` | `procedure_key` | B-tree | Procedure mix |
| `idx_fact_claim_line_diagnosis_key` | `diagnosis_key` | B-tree | Line diagnosis mix |
| `idx_fact_claim_line_service_date_key` | `service_date_key` | B-tree | Line volume by service date |

Dimension indexes used by the load, not by the fact-table list above: `dim_member (member_id, effective_start, effective_end)`, the same shape on `dim_provider`, and a unique index on `dim_date.calendar_date`.

### Indexes not created

- No index on `fact_claim.claim_status` or `claim_type`. Each has a few values. The denial query groups a large share of the fact, so a secondary index would add write cost on every claim and still fall back to a bitmap or sequential scan.
- No index on `total_paid` alone. None of the eight queries filter a paid-amount range. The covering provider index already carries the measure.
- No second covering index on `processed_date_key`. Query 6 is served by `mv_monthly_claim_volume` instead of another fact index.
- No GIN or GiST index. The warehouse has no JSON or full-text predicate.
- No index on `dim_member` name columns. The analytic queries address members by surrogate and natural key.

## Query 1, base tables

Top 20 providers by paid amount in the latest service year, with `LAG` for the prior year. `warehouse.q01_top_providers_yoy`.

```text
Limit  (cost=6683.33..6684.28 rows=20 width=390) (actual time=365.203..365.254 rows=20 loops=1)
  Buffers: shared hit=2022
  CTE with_lag
    ->  WindowAgg  (cost=6073.77..6276.54 rows=9012 width=106) (actual time=346.207..355.467 rows=5049 loops=1)
          Buffers: shared hit=2016
          ->  Sort  (cost=6073.77..6096.30 rows=9012 width=72) (actual time=346.189..347.246 rows=5049 loops=1)
                Sort Key: provider_year.provider_id, provider_year.year_number
                Sort Method: quicksort  Memory: 568kB
                Buffers: shared hit=2016
                ->  Subquery Scan on provider_year  (cost=5369.14..5481.79 rows=9012 width=72) (actual time=336.154..341.728 rows=5049 loops=1)
                      Buffers: shared hit=2013
                      ->  HashAggregate  (cost=5369.14..5481.79 rows=9012 width=72) (actual time=336.152..340.804 rows=5049 loops=1)
                            Group Key: cur.provider_id, cur.provider_name, cur.specialty, d.year_number
                            Batches: 1  Memory Usage: 2449kB
                            Buffers: shared hit=2013
                            ->  Hash Join  (cost=239.48..4455.04 rows=73128 width=46) (actual time=11.801..185.406 rows=99808 loops=1)
                                  Hash Cond: (f.service_date_key = d.date_key)
                                  Buffers: shared hit=2013
                                  ->  Hash Join  (cost=108.05..4131.45 rows=73128 width=52) (actual time=8.779..116.302 rows=99808 loops=1)
                                        Hash Cond: (f.provider_key = ver.provider_key)
                                        Buffers: shared hit=1972
                                        ->  Seq Scan on fact_claim f  (cost=0.00..2918.08 rows=99808 width=22) (actual time=0.011..22.305 rows=99808 loops=1)
                                              Buffers: shared hit=1920
                                        ->  Hash  (cost=97.75..97.75 rows=824 width=46) (actual time=8.725..8.729 rows=1125 loops=1)
                                              Buckets: 2048 (originally 1024)  Batches: 1 (originally 1)  Memory Usage: 103kB
                                              Buffers: shared hit=52
                                              ->  Hash Join  (cost=46.64..97.75 rows=824 width=46) (actual time=7.746..8.308 rows=1125 loops=1)
                                                    Hash Cond: (ver.provider_id = cur.provider_id)
                                                    Buffers: shared hit=52
                                                    ->  Seq Scan on dim_provider ver  (cost=0.00..37.25 rows=1125 width=16) (actual time=0.005..0.136 rows=1125 loops=1)
                                                          Buffers: shared hit=26
                                                    ->  Hash  (cost=37.25..37.25 rows=751 width=38) (actual time=7.714..7.716 rows=751 loops=1)
                                                          Buckets: 1024  Batches: 1  Memory Usage: 60kB
                                                          Buffers: shared hit=26
                                                          ->  Seq Scan on dim_provider cur  (cost=0.00..37.25 rows=751 width=38) (actual time=0.005..7.381 rows=751 loops=1)
                                                                Filter: is_current
                                                                Rows Removed by Filter: 374
                                                                Buffers: shared hit=26
                                  ->  Hash  (cost=81.19..81.19 rows=4019 width=10) (actual time=2.988..2.988 rows=4019 loops=1)
                                        Buckets: 4096  Batches: 1  Memory Usage: 221kB
                                        Buffers: shared hit=41
                                        ->  Seq Scan on dim_date d  (cost=0.00..81.19 rows=4019 width=10) (actual time=0.011..1.792 rows=4019 loops=1)
                                              Buffers: shared hit=41
  InitPlan 2 (returns $1)
    ->  Aggregate  (cost=202.77..202.78 rows=1 width=2) (actual time=17.508..17.509 rows=1 loops=1)
          ->  CTE Scan on with_lag with_lag_1  (cost=0.00..180.24 rows=9012 width=2) (actual time=0.001..16.473 rows=5049 loops=1)
  ->  WindowAgg  (cost=204.01..206.14 rows=45 width=390) (actual time=365.200..365.235 rows=20 loops=1)
        Buffers: shared hit=2022
        ->  Sort  (cost=204.01..204.12 rows=45 width=352) (actual time=365.162..365.165 rows=20 loops=1)
              Sort Key: with_lag.total_paid DESC, with_lag.provider_id
              Sort Method: quicksort  Memory: 89kB
              Buffers: shared hit=2022
              ->  CTE Scan on with_lag  (cost=0.00..202.77 rows=45 width=352) (actual time=363.729..364.589 rows=749 loops=1)
                    Filter: (year_number = $1)
                    Rows Removed by Filter: 4300
                    Buffers: shared hit=2016
Planning Time: 3.772 ms
Execution Time: 366.524 ms
```

The plan reads every claim, joins the provider version and the current provider row, joins the service date, and sums paid amount by provider and year. That produces 5,049 provider-year rows. A window then computes `LAG`, the latest year is filtered to 749 providers, and `Limit` keeps 20. The whole fact is in shared buffers (1,920 pages, all hits), so the sequential scan itself is about 22 ms. The most expensive node is the `HashAggregate` on provider and year: it finishes at 336 ms and is where the 99,808 claim rows become the yearly totals the window needs. The provider and date indexes are unused because the query has no selective predicate; hashing the small dimensions against one pass over the fact is cheaper than a nested loop. The top-20 limit cannot start until that aggregate exists, which is why it does not reduce the scan.

## Query 6, base tables

Monthly claim volume with a 3-month moving average. `warehouse.q06_monthly_volume`.

```text
Subquery Scan on q06_monthly_volume  (cost=4317.55..4321.54 rows=133 width=79) (actual time=226.713..226.881 rows=81 loops=1)
  Buffers: shared hit=1964
  ->  WindowAgg  (cost=4317.55..4320.21 rows=133 width=83) (actual time=226.712..226.864 rows=81 loops=1)
        Buffers: shared hit=1964
        ->  Sort  (cost=4317.55..4317.88 rows=133 width=51) (actual time=226.694..226.706 rows=81 loops=1)
              Sort Key: monthly.month_start
              Sort Method: quicksort  Memory: 30kB
              Buffers: shared hit=1964
              ->  Subquery Scan on monthly  (cost=4309.86..4312.85 rows=133 width=51) (actual time=226.589..226.647 rows=81 loops=1)
                    Buffers: shared hit=1961
                    ->  HashAggregate  (cost=4309.86..4311.52 rows=133 width=51) (actual time=226.588..226.633 rows=81 loops=1)
                          Group Key: d.year_month
                          Batches: 1  Memory Usage: 96kB
                          Buffers: shared hit=1961
                          ->  Hash Join  (cost=131.43..3311.78 rows=99808 width=17) (actual time=2.292..148.558 rows=99808 loops=1)
                                Hash Cond: (f.service_date_key = d.date_key)
                                Buffers: shared hit=1961
                                ->  Seq Scan on fact_claim f  (cost=0.00..2918.08 rows=99808 width=14) (actual time=0.005..33.443 rows=99808 loops=1)
                                      Buffers: shared hit=1920
                                ->  Hash  (cost=81.19..81.19 rows=4019 width=19) (actual time=2.274..2.275 rows=4019 loops=1)
                                      Buckets: 4096  Batches: 1  Memory Usage: 252kB
                                      Buffers: shared hit=41
                                      ->  Seq Scan on dim_date d  (cost=0.00..81.19 rows=4019 width=19) (actual time=0.004..1.006 rows=4019 loops=1)
                                            Buffers: shared hit=41
Planning Time: 0.534 ms
Execution Time: 226.992 ms
```

The fact is scanned once and hash-joined to `dim_date` so each claim picks up `year_month`. The most expensive node is that hash join: it runs to 149 ms and is the step that touches all 99,808 claims. The `HashAggregate` then collapses those rows to 81 months, and the window average over those 81 rows is noise (the sort uses 30 kB and adds well under a millisecond). Almost all of the 227 ms is the fact-to-calendar join, not the moving average.

## Query 6, materialized view

`warehouse.mv_monthly_claim_volume` stores the monthly aggregate. `warehouse.q06_monthly_volume_mv` applies the same 3-month window to that summary.

```text
Subquery Scan on q06_monthly_volume_mv  (cost=4.38..6.81 rows=81 width=56) (actual time=0.144..0.274 rows=81 loops=1)
  Buffers: shared hit=1
  ->  WindowAgg  (cost=4.38..6.00 rows=81 width=60) (actual time=0.143..0.259 rows=81 loops=1)
        Buffers: shared hit=1
        ->  Sort  (cost=4.38..4.58 rows=81 width=28) (actual time=0.129..0.138 rows=81 loops=1)
              Sort Key: mv_monthly_claim_volume.month_start
              Sort Method: quicksort  Memory: 30kB
              Buffers: shared hit=1
              ->  Seq Scan on mv_monthly_claim_volume  (cost=0.00..1.81 rows=81 width=28) (actual time=0.066..0.082 rows=81 loops=1)
                    Buffers: shared hit=1
Planning Time: 2.107 ms
Execution Time: 0.315 ms
```

The fact scan and the hash join are gone. The plan reads one buffer page of an 81-row summary, sorts it, and computes the window. Execution drops from 227 ms to 0.3 ms. The most expensive node is the small in-memory sort of those 81 months, which is the entire remaining query.

## Refresh schedule

Refresh `warehouse.mv_monthly_claim_volume` at the end of each successful `fact_claim` load. The pipeline already does this through `warehouse.refresh_monthly_claim_volume()`. A daily load, after the source day’s claims are closed, matches the processed-date watermark: the summary then contains every claim the warehouse accepted that day.

The summary is one row per service month, on the order of 100 rows, so a full `REFRESH MATERIALIZED VIEW` holds a lock for milliseconds. That is the right default. The unique index on `year_month` also allows `REFRESH MATERIALIZED VIEW CONCURRENTLY` once the view has been populated, which matters if analysts read the summary during the refresh. The first population cannot be concurrent.
