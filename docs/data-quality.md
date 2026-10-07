# Data quality

Checks live in `tests/data_quality.sql`. A check passes when failed rows are at or under 1% of the rows evaluated. The run below is the scale `0.05` load on 7 October 2026: 99,808 claims and 374,330 service lines.

| Check | Rows evaluated | Passed | Failed | Pass rate | Status |
|---|---:|---:|---:|---:|---|
| fact_claim valid service date, processed date, member, and provider keys | 99,808 | 99,808 | 0 | 100.00% | PASS |
| fact_claim total_paid within 5% of total_allowed | 99,808 | 99,808 | 0 | 100.00% | PASS |
| dim_member one current row per member | 25,000 | 25,000 | 0 | 100.00% | PASS |
| dim_provider one current row per provider | 750 | 750 | 0 | 100.00% | PASS |
| fact_claim_line claim_id exists on fact_claim | 374,330 | 374,330 | 0 | 100.00% | PASS |
| fact_claim_line procedure code exists on dim_procedure | 374,330 | 374,304 | 26 | 99.99% | PASS |
| fact_claim service date on or after provider network_effective_date | 99,808 | 99,800 | 8 | 99.99% | PASS |

The two failing counts are the defects the generator plants so the checks are observable.

- 26 lines carry procedure code `ZZZZZ`, which is not in `dim_procedure`. They load with `procedure_key = -1` and remain visible through `source_procedure_code`.
- 8 claims are on Northstar Family Medicine, whose `network_effective_date` is 2030-01-01, with a service date of 2024-06-01. They are inside the provider’s SCD version, so they belong on the fact, and the anachronism check flags them.

200 source claims never reached `fact_claim`: 100 with an unknown member and 100 with an unknown provider. They are in `audit.etl_dead_letter`. The key check above is over claims that did load, and every one of those resolves to a real date, member, and provider key.

Member and provider current-row counts are one open version per natural key, which matches the partial unique indexes and the SCD checks in the load procedures. Every line `claim_id` is on the header. No loaded claim pays more than allowed plus 5%.
