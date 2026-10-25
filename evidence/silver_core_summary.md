# Aita Silver Core

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Successful job run ID: `332861017181304`
- Successful pipeline update ID: `936675c5-59cd-498d-869d-50d35bc342f0`
- Result: `SUCCESS`

## Implementation

- `workers`, `org_units`, `team_productivity`, `compensation`, `requisitions`, and `application_events` use keyed AUTO CDC Type 1 flows for typed conformance and grain-level deduplication.
- `worker_history` uses AUTO CDC Type 2 keyed by `worker_id` and sequenced by `STRUCT(event_date, event_id)`.
- Worker business lines and locations are canonicalized, identifiers are trimmed and normalized, and numeric measures use explicit types.
- All seven tables retain `_rescued_data`, `_source_file`, and `_ingested_at` for traceability.

## Row and Grain Reconciliation

| Silver table | Total rows | Distinct grain | Duplicate grain rows | Rescued rows | Result |
|---|---:|---:|---:|---:|---|
| `workers` | 20,000 | 20,000 `worker_id` | 0 | 0 | PASS |
| `worker_history` | 28,504 | 28,504 `event_id` | 0 | 0 | PASS |
| `org_units` | 72 | 72 `org_unit_id` | 0 | 0 | PASS |
| `team_productivity` | 1,728 | 1,728 `team_id`, `month` | 0 | 0 | PASS |
| `compensation` | 40,000 | 40,000 `compensation_id` | 0 | 0 | PASS |
| `requisitions` | 2,400 | 2,400 `requisition_id` | 0 | 0 | PASS |
| `application_events` | 86,240 | 86,240 `application_event_id` | 0 | 0 | PASS |
| **Total** | **178,944** |  | **0** | **0** | **PASS** |

The SCD Type 2 history contains 20,000 distinct workers and exactly 20,000 current rows where `__END_AT IS NULL`. No history event predates its worker's hire date.

## Expectation Results

| Table | Expectation | Action | Passed | Failed |
|---|---|---|---:|---:|
| `workers` | `valid_business_line` | Drop row | 20,000 | 0 |
| `workers` | `hire_date_not_null` | Fail update | 20,000 | 0 |
| `worker_history` | `event_date_on_or_after_hire_date` | Warn | 20,000 | 0 |
| `compensation` | `base_salary_within_band` | Warn | 40,000 | 0 |
| `requisitions` | `close_date_on_or_after_open_date` | Warn | 2,400 | 0 |

The pipeline reports the `worker_history` expectation on the 20,000 current target rows. A separate validation across all 28,504 historical versions found zero events before hire date.

## Resolved Run Failure

Initial job run `162906550700389` failed because streaming `SELECT DISTINCT` requires a watermark in append mode. The implementation was corrected to use keyed AUTO CDC Type 1 flows for streaming-safe deduplication; no source or rescued records were removed. The subsequent job and pipeline update completed successfully.
