# Aita Gold Dimensions

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Successful job run ID: `961565381599131`
- Successful pipeline update ID: `ed904241-36ae-4fd2-ab91-15eaa1882df3`
- Result: `PASS`

## Implementation

- `dim_worker` publishes one current row per employee and adds the latest effective worker-history event without changing the employee grain.
- `dim_org` publishes one row per organization unit, exposes the source parent code as `business_line_id`, and resolves the organization manager name.
- `dim_job` publishes one row per job code with licensed and strategic flags, AI-derived GenAI exposure, required skills, and the retained planted exposure tier for audit comparison.
- `dim_date` builds a continuous daily calendar from the minimum and maximum conformed activity dates, rounds to full calendar years, and includes one future year.
- All materialized views publish directly to `${catalog}.${gold_schema}` and read parameterized `${catalog}.${silver_schema}` sources.

## Source Profiling

- `workers`, `org_units`, and `jobs_enriched` contain unique, non-null business keys.
- All 20,000 workers have exactly one current `worker_history` SCD Type 2 row, with no worker having multiple current rows.
- Current worker-history job, organization, and manager assignments match the current `workers` snapshot.
- Organization parent codes represent business-line identifiers rather than other organization-unit keys.

## Row and Grain Reconciliation

| Gold table | Total rows | Distinct key | Null keys | Expected rows | Difference | Result |
|---|---:|---:|---:|---:|---:|---|
| `dim_worker` | 20,000 | 20,000 `employee_id` | 0 | 20,000 | 0 | PASS |
| `dim_org` | 72 | 72 `org_unit_id` | 0 | 72 | 0 | PASS |
| `dim_job` | 60 | 60 `job_code` | 0 | 60 | 0 | PASS |
| `dim_date` | 6,939 | 6,939 `date_key` | 0 | 6,939 | 0 | PASS |
| **Total** | **27,071** |  | **0** | **27,071** | **0** | **PASS** |

The three business dimensions reconcile exactly to their silver sources. The date dimension spans `2009-01-01` through `2027-12-31`; its row count equals the inclusive date range and it has zero missing days.

## Join Integrity

| Check | Invalid rows | Result |
|---|---:|---|
| `dim_worker.job_code` missing from `dim_job` | 0 | PASS |
| `dim_worker.org_unit_id` missing from `dim_org` | 0 | PASS |
| `dim_worker.manager_id` missing from `dim_worker` | 0 | PASS |
| `dim_org.manager_id` missing from `dim_worker` | 0 | PASS |
| `dim_job.genai_exposure_tier` missing | 0 | PASS |
| `dim_job.required_skills` missing | 0 | PASS |
| Non-contiguous `dim_date` rows | 0 | PASS |

Five jobs have an AI-derived GenAI exposure tier that differs from the planted expected tier. Both values and an explicit `genai_tier_mismatch_flag` are retained rather than overwriting model output.

## Deployment

- `databricks bundle validate --strict -t dev --profile genie-workbench` completed successfully.
- The existing `../src/pipeline/**` library glob automatically included `src/pipeline/gold/dimensions.sql`; no resource-definition change was required.
- Job run `961565381599131` terminated with `SUCCESS`.
- Pipeline update `ed904241-36ae-4fd2-ab91-15eaa1882df3` completed successfully and returned the pipeline to `IDLE`.
