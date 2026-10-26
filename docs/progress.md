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

### Phase 1: Checkpoint and Foundations

- Confirmed the silver exit-interview AI sample checkpoint is preserved in commit `fbda414`.
- Verified `genie_workbench_dev_catalog.aita_silver` and created the missing `genie_workbench_dev_catalog.aita_gold` schema.
- Validated all 12 bronze tables: 404,028 total rows, zero null `_source_file` values, zero null `_ingested_at` values, and zero non-null `_rescued_data` values.
- Reconciled every table count to the generated-data and bronze-ingestion evidence; no discrepancy required rescued-record investigation.

Detailed Phase 1 validation evidence is stored in `evidence/bronze_quality_summary.md`.

### Phase 2: Silver Core

- Implemented typed and conformed `workers`, `org_units`, `team_productivity`, `compensation`, `requisitions`, and `application_events` streaming tables.
- Added keyed AUTO CDC Type 1 flows for grain-level deduplication and AUTO CDC Type 2 `worker_history` sequenced by event date and event ID.
- Added the specified drop, fail, and warn expectations for workers, worker history, compensation, and requisitions.
- Deployed the serverless pipeline and completed job run `332861017181304` with pipeline update `936675c5-59cd-498d-869d-50d35bc342f0`.
- Reconciled 178,944 silver rows with zero duplicate grain rows, zero rescued rows, and zero expectation failures.

Detailed Phase 2 execution evidence is stored in `evidence/silver_core_summary.md`.

### Phase 3: Silver AI

- Implemented full-row `jobs_enriched`, `exit_interviews_enriched`, `engagement_enriched`, `performance_enriched`, and `applications_enriched` streaming tables.
- Added the specified AI classifications, sentiment analysis, and skill extraction fields with explicit per-row AI error columns and preserved source provenance.
- Reviewed bounded outputs, tuned job exposure, exit reason, engagement theme, and offer-decline labels, and corrected skill extraction to return plain string arrays.
- Replaced per-row inference with six private materialized views over distinct normalized text, reducing a full refresh from approximately 383,492 AI calls to 152 while preserving all 225,084 enriched rows.
- Completed cost-optimized pipeline update `dab347e2-e973-4b3c-9350-871b79a4014b` and final engagement refinement update `2cd52b9d-2486-4924-b7bd-15b8369f0ec8`.
- Reconciled all five enriched tables with zero duplicate grains, rescued rows, AI errors, missing required AI outputs, or expectation failures.

Detailed Phase 3 execution evidence is stored in `evidence/silver_ai_summary.md`.

### Phase 4: Gold Dimensions

- Implemented the `dim_worker`, `dim_org`, `dim_job`, and `dim_date` materialized views in the gold schema.
- Preserved one current row per employee, resolved organization manager names, retained auditable AI job-exposure comparisons, and generated a continuous full-year calendar through 2027.
- Deployed the serverless pipeline and completed job run `961565381599131` with pipeline update `ed904241-36ae-4fd2-ab91-15eaa1882df3`.
- Reconciled 27,071 gold dimension rows with zero duplicate keys, null keys, source-count differences, orphan dimension joins, or date gaps.

Detailed gold dimension execution evidence is stored in `evidence/gold_dimensions_summary.md`.

### Phase 4: Gold Facts

- Implemented all eight specified gold facts for monthly headcount, attrition, engagement, productivity, performance, compensation, requisitions, and application funnels.
- Added half-open SCD Type 2 temporal joins, source-driven headcount months, readable business flags, stage-duration measures, and an initial omission-based compensation privacy contract later superseded by Phase 5 masks.
- Deployed the serverless pipeline and completed job run `24365280429776` with pipeline update `9f70c7ed-566a-4fc9-8793-de4d05e54ec5`.
- Reconciled 286,588 gold fact rows with zero duplicate or null grains, source-count differences, join fan-out, orphan dimension keys, temporal misses, negative funnel durations, or exposed raw pay columns.

Detailed gold fact execution evidence is stored in `evidence/gold_facts_summary.md`.

### Phase 4: Gold Talent Watchlist

- Implemented the `talent_watchlist` materialized view at one row per current employee with at least one risk signal.
- Added stalled-high-performer, disengaging, team-at-risk, and combined hard-to-backfill rules with readable aligned reason text.
- Used deterministic as-of dates, trailing-12-month team attrition, a data-derived team-risk threshold, and the bank median job-family time to fill.
- Deployed the serverless pipeline and completed job run `618778647851719` with pipeline update `30cecb4b-3be0-4180-9d69-8c79bc38fe14`.
- Reconciled 3,427 watchlist rows with zero duplicate employees, null grain values, signal-count mismatches, reason-count mismatches, or hard-to-backfill rule mismatches.
- Captured all 504 active planted stalled employees, all 522 active employees in the fraud-operations burnout pocket, and both planted contact-center risk teams with no unexpected risk teams.

Detailed watchlist execution evidence is stored in `evidence/gold_talent_watchlist_summary.md`.

### Phase 5: Gold Governance

- Reconciled the governed Gold contract: silver `annual_bonus` publishes as `bonus`, `compa_ratio` is replaced by `pay_position_to_midpoint`, and `regrettable_flag` uses a latest-review `rating_numeric` of 4 or 5.
- Created the `aita_hr_admin` workspace group, added the approved HR administrator, and created `genie_workbench_dev_catalog.aita_gold.mask_compensation`.
- Added business-friendly comments to all 13 Gold tables and all 187 Gold columns, with zero missing comments; added short comments to all 24 published Bronze and Silver tables and to the pipeline-private Silver AI lookup views.
- Published `base_salary`, `bonus`, and `pay_position_to_midpoint` with pipeline-attached masks while leaving `band_min`, `band_mid`, and `band_max` visible; added no row filters.
- Deployed the serverless pipeline and completed job run `74640997233422` with pipeline update `baf23f7b-cfd2-421f-b52a-6e1f089cb3fe`.
- Verified the same compensation query as a non-HR user and an HR administrator: 40,000 masked rows for the non-member, 40,000 visible rows for the member, and zero missing band values in either case.
- Reconciled 40,000 distinct compensation records, 1,161 attrition events with zero regrettable-rule mismatches, and an unchanged 3,427-row talent watchlist.

Detailed governance evidence is stored in `evidence/gold_comments.md` and `evidence/mask_check.md`.

## Next Steps

### Phase 6: Orchestration, Semantic Serving, and Evidence

1. Extend `aita_pipeline` with the governance prerequisite, `generate_data`, `sync_lakebase`, and `evidence_report` tasks described by the environment and governance specifications.
2. Finalize and publish the gold metric views, define the `talent_watchlist` Lakebase mapping, and activate the governed sync.
3. Complete the remaining silver and gold run evidence, expectation results, AI samples, governance checks, and grain checks.
4. Verify the final pipeline graph, Catalog Explorer lineage, and representative raw, bronze, silver, and gold data previews.
5. Commit each remaining completed layer under the project owner's account with a clear message.
