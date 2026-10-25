# Aita Build Progress

Last updated: October 25, 2026

## Completed

### Bundle Setup

- Created `databricks.yml` with variables for the catalog, bronze, silver, and gold schemas, and landing path.
- Configured the `dev` target to use the `genie-workbench` profile.
- Created `resources/aita_pipeline.yml` with the serverless `aita_sdp` pipeline.
- Set the pipeline default schema to `aita_silver` and passed all bundle variables as pipeline configuration.
- Added the `aita_pipeline` Lakeflow Job, which currently runs the SDP pipeline task in STANDARD performance mode.
- Successfully validated the bundle configuration.

### Synthetic Data

- Created `src/generate/generate_data.py` using deterministic PySpark with seed `20261024`.
- The generator creates the `aita_bronze` schema and `landing` volume when needed.
- Generated approximately 20,000 workers over 24 months with the seven planted business patterns from the pipeline specification.
- Wrote all 12 datasets to `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing` using the specified CSV and JSON formats.
- Created `src/generate/pattern_checks.sql` to validate every planted pattern directly from the landing files.
- Ran the generator and SQL checks using the `genie-workbench` profile.

## Generated Data

| Dataset | Rows |
|---|---:|
| workers | 20,000 |
| job_history | 28,504 |
| org_units | 72 |
| jobs | 60 |
| engagement_surveys | 155,063 |
| exit_interviews | 1,161 |
| team_productivity | 1,728 |
| performance_reviews | 40,000 |
| compensation | 40,000 |
| requisitions | 2,400 |
| applications | 28,800 |
| application_events | 86,240 |

Total generated rows: 404,028.

## Pattern Results

| Pattern | Status | Key evidence |
|---|---|---|
| Contact-center attrition spike | PASS | 108 spike exits; 95.4% under three target managers |
| Stalled strategic high performers | PASS | 506 qualifying workers |
| Fraud-operations burnout | PASS | Engagement fell 1.537 points and overtime rose 2.456x |
| Standout managers | PASS | 3 qualifying managers |
| GenAI internal mobility | PASS | 738 qualifying internal applications |
| Licensed-role hiring friction | PASS | Licensed roles took 2.118x as long to fill |
| Contact-center backfills | PASS | 164 post-spike backfills versus 3 in the baseline period |

Detailed execution evidence is stored in `evidence/generation_summary.md`.

### Bronze Ingestion

- Created `src/pipeline/bronze/ingest.sql` with one Auto Loader streaming table per landing dataset.
- Parameterized the catalog, bronze schema, and landing paths through the SDP pipeline configuration.
- Added `_source_file`, `_ingested_at`, key-column schema hints, and `_rescued_data` support to every table.
- Added the bronze SQL library and pipeline root path to `resources/aita_pipeline.yml`.
- Deployed the bundle and completed job run `65455966715028` successfully.
- Reconciled all 12 bronze tables to the landing datasets with 404,028 matching rows.

Detailed bronze execution evidence is stored in `evidence/bronze_ingestion_summary.md`.

### Silver Exit Interview AI Sample

- Created `src/pipeline/silver/workforce.sql` with `exit_interviews_enriched` in the silver schema.
- Added `ai_classify` with the six requested exit-reason labels and `ai_analyze_sentiment`.
- Added the warn-only `exit_comment_not_empty` expectation.
- Limited the streaming-table sample to 200 rows for review and cost control.
- Deployed the bundle and completed job run `903360430328551` successfully.
- Verified 200 expectation passes, zero failures, and reviewed 20 AI outputs.

Detailed sample outputs are stored in `evidence/silver_exit_interviews_ai_sample.md`.

## Next Steps

1. Commit the current silver AI sample checkpoint under the project owner's account with a clear layer-specific message.
2. Implement the silver conformance, expectations, and AUTO CDC history without AI Functions.
3. Tune the exit-reason labels, remove the 200-row limit, perform a targeted full refresh or equivalent state reset, and reconcile all 1,161 exit interviews.
4. Add the remaining silver AI Function enrichments on controlled samples, review and tune their outputs, remove their limits, and fully refresh each production table.
5. Verify or create the `aita_silver` and `aita_gold` schemas before adding further silver and gold objects.
6. Implement the gold dimensions, facts, and `talent_watchlist` materialized view, then validate table grain and join fan-out.
7. Define the gold metric views once their specifications are available.
8. Extend `aita_pipeline` with the `generate_data`, `sync_lakebase`, and `evidence_report` tasks described in the environment specification.
9. Sync `talent_watchlist` to Lakebase after successful pipeline updates.
10. Complete evidence for bronze metadata and rescued-data quality, silver and gold row counts, expectations, AI samples, grain checks, and pipeline runs.
11. Verify the final pipeline graph, Catalog Explorer lineage, and representative raw, bronze, silver, and gold data previews.
12. Commit each remaining completed layer under the project owner's account with a clear message.
