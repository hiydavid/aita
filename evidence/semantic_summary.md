# Semantic and Governance Evidence

Gold governance through orchestration (Phases 5–8), run on profile `genie-workbench`, bundle target `dev`, and serverless SQL warehouse `genie-workbench-test` (`813b0ad2f3036e46`). Every check below passed unless marked deferred.

## Runs

| Phase | Job run | Update |
|---|---|---|
| Gold governance | `74640997233422` | Pipeline `baf23f7b-cfd2-421f-b52a-6e1f089cb3fe` |
| Semantic helpers | | Pipeline `daa262c6-d33b-409c-9af0-5cd6a137059d` |
| Metric views | Pipeline job `910806891063837`; semantic job `1017977579100747` | Pipeline `50b9c66a-d2d6-458a-8664-4f5c731317b7` |
| Orchestration | `aita_pipeline` `1073150973022044`; semantic `269141171180276` | SDP `ca8c43ee-c9ac-4614-b342-a5ee56e78fb6`; Lakebase `e4c38851-fe0d-4004-972a-6f3a0df4d2d1` |

In semantic job `1017977579100747`, all eight publication tasks passed and the grants task failed; grant remediation is deferred (see Access).

## Gold Governance

- Comments: 13 Gold tables, 187 Gold columns, and 24 published Bronze and Silver tables, with zero missing; the private Silver AI lookup views also carry table comments.
- Compensation contract: Silver `annual_bonus` publishes as `bonus`, and `compa_ratio` is replaced by `pay_position_to_midpoint`. The legacy `annual_bonus`, `compa_ratio`, `range_penetration`, and `bonus_pct_of_base` columns are absent. 40,000 rows, 40,000 distinct `compensation_id` values, zero null band values.
- Regrettable exits: 890 of 1,161 exits have a latest `rating_numeric` of 4 or 5, with zero rows disagreeing with the rule.
- Mask: `genie_workbench_dev_catalog.aita_gold.mask_compensation` takes and returns `DECIMAL(18,4)` and returns values only to `aita_hr_admin` (`2120313189110874`). `DESCRIBE TABLE EXTENDED` shows it attached to `base_salary`, `bonus`, and `pay_position_to_midpoint`. No row filter is attached.

### Mask Comparison

The same query (`SELECT employee_id, compensation_year, base_salary, bonus, band_min, band_mid, band_max, pay_position_to_midpoint FROM genie_workbench_dev_catalog.aita_gold.fact_compensation ORDER BY employee_id, compensation_year LIMIT 5`) ran as `david.huang@databricks.com` before and after approved addition to `aita_hr_admin`.

| Caller | employee_id | Year | base_salary | bonus | band_mid | pay_position_to_midpoint |
|---|---|---:|---:|---:|---:|---:|
| Non-member | EMP000001 | 2025 | NULL | NULL | 52000.00 | NULL |
| Non-member | EMP000002 | 2025 | NULL | NULL | 52000.00 | NULL |
| HR admin | EMP000001 | 2025 | 54399.0700 | 5828.8600 | 52000.00 | 1.0461 |
| HR admin | EMP000002 | 2025 | 55895.4200 | 10788.3800 | 52000.00 | 1.0749 |

`band_min` (41600.00) and `band_max` (65000.00) were visible to both callers. Across all 40,000 rows, the non-member saw NULL in all three masked columns and populated band values. The member saw every column.

## Semantic Helpers

| Output | Rows | Grain |
|---|---:|---|
| `semantic_workforce_monthly` | 17,436 | organization unit × job code × month |
| `semantic_talent_snapshot` | 18,839 | active employee |
| `semantic_talent_skills` | 58,656 | active employee × normalized demonstrated skill |

All 13 checks in `src/semantic/validation.sql` returned zero violations. They cover:

- `dim_worker` grain and parity of `last_promotion_date` with Silver history (3,019 employees with a promotion)
- grain, row, movement-field, and regrettable-exit parity for the workforce helper (680 regrettable voluntary exits)
- talent-snapshot grain and active population
- latest performance and compensation selection
- stalled-high-performer parity with the watchlist (969 in both)
- grain and explode parity for the talent-skills helper

The snapshot uses Gold business date `2026-12-31`, and the watchlist is unchanged at 3,427 rows. `SHOW CREATE TABLE` confirms `semantic_talent_snapshot.pay_position_to_midpoint` keeps `mask_compensation`; the HR administrator saw 18,839 populated values.

## Metric Views

All eight views are registered as `METRIC_VIEW`: `mv_workforce`, `mv_attrition`, `mv_engagement`, `mv_productivity`, `mv_talent`, `mv_talent_skills`, `mv_requisitions`, and `mv_recruiting_funnel`.

The two `src/semantic/metric_validation_*.sql` files ran as statements `01f1d168-6c1a-1d67-a8f4-c7d3fbe2f373` and `01f1d168-5a69-1a21-885c-67d71bf87b73`: 12 direct-Gold parity checks, zero violations. They cover every required measure, plus:

- yearly semi-additive headcount and multi-month rates
- previous-wave engagement
- case-weighted productivity
- zero denominators and stage conversions
- historical internal-applicant job matching

As `aita_hr_admin`, `mv_talent` returned 18,839 active employees, 2,393 high performers, a 30.5802% below-midpoint share, and an average pay position of `1.04664904`.

`fact_application_funnel` gained the historical `internal_applicant_job_code`. Its raw `source` field was renamed `recruiting_source` because `source` is the reserved metric-view source alias; `source` remains a synonym.

## Access

- SQL warehouse `813b0ad2f3036e46` grants explicit `CAN USE` to `aita_users` (`2124487482070223`) and `aita_hr_admin`.
- `aita_users` contains only the project owner. No Aita app service principal exists yet.
- Unity Catalog grants are deferred. Both groups report `resourceType: WorkspaceGroup`, and Unity Catalog returns `PRINCIPAL_DOES_NOT_EXIST` for `aita_users`. The demo runs under the owner-only exception in `docs/semantics_spec.md`, with no per-user grant or mask bypass. `src/semantic/grants.sql` is ready to rerun once account-level groups exist.

## Orchestration and Lakebase

All five `aita_pipeline` tasks passed: `generate_data`, `gold_governance`, `sdp_pipeline`, `publish_semantics`, and `sync_lakebase`. The SDP task uses full refresh because the generator replaces complete landing snapshots; this stops repeated runs from appending duplicate files to Bronze, and the run restored the expected 404,028 Bronze rows. Shared grants stay in the separate `aita_apply_semantic_grants` job.

| Lakebase setting | Value |
|---|---|
| Project | `projects/aita-lakebase` (display name `aita_lakebase`, Postgres 17) |
| Branch and database | `production` / `databricks_postgres` |
| Source | `genie_workbench_dev_catalog.aita_gold.talent_watchlist` |
| Synced table | `genie_workbench_dev_catalog.aita_gold.talent_watchlist_serving` |
| Primary key | `employee_id` |
| Columns | `employee_id`, `business_line`, `risk_flags`, `reasons`, `signal_count`, `as_of_date` |
| Update behavior | Job-triggered full snapshot after each successful SDP refresh |

Snapshot mode is required because the source is a materialized view, and triggered incremental sync needs external change-data-feed metadata.

| Check | Source | Lakebase |
|---|---:|---:|
| Rows | 3,427 | 3,427 |
| Distinct employee keys | 3,427 | 3,427 |
| Null employee keys | 0 | 0 |
| Maximum as-of date | 2026-12-31 | 2026-12-31 |

After the final run, the synced table reported `SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE`.
