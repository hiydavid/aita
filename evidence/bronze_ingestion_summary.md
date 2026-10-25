# Aita Bronze Ingestion

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Job run ID: `65455966715028`
- Pipeline update ID: `256ca01f-05d2-4300-9eb3-c709c9317656`
- Result: `SUCCESS`

## Dataset Counts

| Dataset | Landing rows | Bronze rows | Status |
|---|---:|---:|---|
| workers | 20,000 | 20,000 | MATCH |
| job_history | 28,504 | 28,504 | MATCH |
| org_units | 72 | 72 | MATCH |
| jobs | 60 | 60 | MATCH |
| engagement_surveys | 155,063 | 155,063 | MATCH |
| exit_interviews | 1,161 | 1,161 | MATCH |
| team_productivity | 1,728 | 1,728 | MATCH |
| performance_reviews | 40,000 | 40,000 | MATCH |
| compensation | 40,000 | 40,000 | MATCH |
| requisitions | 2,400 | 2,400 | MATCH |
| applications | 28,800 | 28,800 | MATCH |
| application_events | 86,240 | 86,240 | MATCH |
| **Total** | **404,028** | **404,028** | **MATCH** |

Each bronze table is an Auto Loader streaming table in `genie_workbench_dev_catalog.aita_bronze`. The definitions use pipeline parameters for the catalog, schema, and landing path, add `_source_file` and `_ingested_at`, apply key-column schema hints, and retain malformed or unexpected fields in `_rescued_data`.
