# Aita Bronze Quality Summary

- Validation date: 2026-10-25
- Databricks profile: `genie-workbench`
- Catalog: `genie_workbench_dev_catalog`
- Bronze schema: `aita_bronze`
- Result: `PASS`

## Foundation Schemas

| Schema | Result |
|---|---|
| `genie_workbench_dev_catalog.aita_silver` | Verified existing |
| `genie_workbench_dev_catalog.aita_gold` | Created and verified |

## Bronze Quality Results

| Dataset | Total rows | Null `_source_file` | Null `_ingested_at` | Non-null `_rescued_data` | Result |
|---|---:|---:|---:|---:|---|
| `workers` | 20,000 | 0 | 0 | 0 | PASS |
| `job_history` | 28,504 | 0 | 0 | 0 | PASS |
| `org_units` | 72 | 0 | 0 | 0 | PASS |
| `jobs` | 60 | 0 | 0 | 0 | PASS |
| `engagement_surveys` | 155,063 | 0 | 0 | 0 | PASS |
| `exit_interviews` | 1,161 | 0 | 0 | 0 | PASS |
| `team_productivity` | 1,728 | 0 | 0 | 0 | PASS |
| `performance_reviews` | 40,000 | 0 | 0 | 0 | PASS |
| `compensation` | 40,000 | 0 | 0 | 0 | PASS |
| `requisitions` | 2,400 | 0 | 0 | 0 | PASS |
| `applications` | 28,800 | 0 | 0 | 0 | PASS |
| `application_events` | 86,240 | 0 | 0 | 0 | PASS |
| **Total** | **404,028** | **0** | **0** | **0** | **PASS** |

## Reconciliation and Investigation

- Every table count matches the generated-data and bronze-ingestion evidence.
- All rows contain both provenance fields, `_source_file` and `_ingested_at`.
- No table currently contains a non-null `_rescued_data` value, so there is no rescued-record discrepancy requiring row-level investigation.
- The validation counted all rows and separately counted non-null `_rescued_data`; it did not filter, hide, mutate, or discard rescued records.
