# Semantic and Governance Evidence

Phases 5–8 ran with profile `genie-workbench`, target `dev`, and serverless warehouse `813b0ad2f3036e46`. Every check passed unless marked deferred.

## Runs

| Phase | Job run | Update |
|---|---|---|
| Gold governance | `74640997233422` | Pipeline `baf23f7b-cfd2-421f-b52a-6e1f089cb3fe` |
| Semantic helpers | | Pipeline `daa262c6-d33b-409c-9af0-5cd6a137059d` |
| Metric views | Semantic job `675414841768481` | Pipeline `50b9c66a-d2d6-458a-8664-4f5c731317b7` |
| Orchestration | `aita_pipeline` `1094796673508321`; publish task `739156609695933` | SDP `28751948-2568-4f31-b630-60b1dae1ba56`; Lakebase `93830fd4-6225-437d-b7d1-cc26dcb8303e` |

Semantic job `675414841768481` passed all eight parallel publication tasks; the deferred grant issue is unchanged (see Access).

## Gold Governance

- Comments: zero missing across 13 Gold tables, 187 Gold columns, 24 published Bronze/Silver tables, and private Silver AI lookup views.
- Compensation: 40,000 rows and distinct IDs, zero null bands; `bonus` and `pay_position_to_midpoint` replace the four legacy compensation columns named in the spec.
- Regrettable exits: 890 of 1,161 exits have a latest `rating_numeric` of 4 or 5, with zero rows disagreeing with the rule.
- Mask: `genie_workbench_dev_catalog.aita_gold.mask_compensation` takes and returns `DECIMAL(18,4)` and returns values only to `aita_hr_admin` (`2120313189110874`). `DESCRIBE TABLE EXTENDED` shows it attached to `base_salary`, `bonus`, and `pay_position_to_midpoint`. No row filter is attached.

### Mask Comparison

The same compensation query ran as `david.huang@databricks.com` before and after approved addition to `aita_hr_admin`. Across all 40,000 rows, the non-member saw NULL for `base_salary`, `bonus`, and `pay_position_to_midpoint` while band values remained populated; the member saw every value. Representative member values for `EMP000001` were `54399.0700`, `5828.8600`, and `1.0461`.

## Semantic Helpers

| Output | Rows | Grain |
|---|---:|---|
| `semantic_workforce_monthly` | 17,436 | organization unit × job code × month |
| `semantic_talent_snapshot` | 18,839 | active employee |
| `semantic_talent_skills` | 58,656 | active employee × normalized demonstrated skill |

All 13 checks in `src/semantic/validation.sql` returned zero violations, covering:

- `dim_worker` grain and parity of `last_promotion_date` with Silver history (3,019 employees with a promotion)
- grain, row, movement-field, and regrettable-exit parity for the workforce helper (680 regrettable voluntary exits)
- talent-snapshot grain and active population
- latest performance/compensation selection; independent 1095-day and 36-month stalled-high-performer recomputation (969 flagged); talent-skills grain/explode parity

The snapshot uses Gold business date `2026-12-31`, and the watchlist is unchanged at 3,427 rows. `SHOW CREATE TABLE` confirms `semantic_talent_snapshot.pay_position_to_midpoint` keeps `mask_compensation`; the HR administrator saw 18,839 populated values.

## Metric Views

All eight views are registered as `METRIC_VIEW`: `mv_workforce`, `mv_attrition`, `mv_engagement`, `mv_productivity`, `mv_talent`, `mv_talent_skills`, `mv_requisitions`, and `mv_recruiting_funnel`.

After job `675414841768481`, all outputs were `METRIC_VIEW` with populated YAML and byte-identical canonical DDL before/after publication. Twelve direct-Gold parity checks cover:

- yearly semi-additive headcount and multi-month rates
- previous-wave engagement
- case-weighted productivity
- zero denominators and stage conversions
- historical internal-applicant job matching

As `aita_hr_admin`, `mv_talent` returned 18,839 active employees, 2,393 high performers, a 30.5802% below-midpoint share, and an average pay position of `1.04664904`.

`fact_application_funnel` gained the historical `internal_applicant_job_code`. Its raw `source` field was renamed `recruiting_source` because `source` is the reserved metric-view source alias; `source` remains a synonym.

## Access

- SQL warehouse `813b0ad2f3036e46` grants explicit `CAN USE` to `aita_users` (`2124487482070223`) and `aita_hr_admin`.
- `aita_users` contains only the project owner. The owner-only app service principal has Lakebase access but no Unity Catalog grants; Genie executes OBO.
- Unity Catalog grants are deferred. Both groups report `resourceType: WorkspaceGroup`, and Unity Catalog returns `PRINCIPAL_DOES_NOT_EXIST` for `aita_users`. The demo runs under the owner-only exception in `docs/semantics_spec.md`, with no per-user grant or mask bypass. `src/semantic/grants.sql` is ready to rerun once account-level groups exist.

## Orchestration and Lakebase

All five `aita_pipeline` tasks passed in run `1094796673508321`: `generate_data`, `gold_governance`, `sdp_pipeline`, `publish_semantics`, and `sync_lakebase`. Full refresh matches the generator's complete snapshots and restored 404,028 Bronze rows without duplicate appends. Shared grants remain in `aita_apply_semantic_grants`.

| Lakebase setting | Value |
|---|---|
| Project | `aita_lakebase` (`projects/aita-lakebase`, Postgres 17) |
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

After Lakebase update `b4c404cc-2ec0-4f38-87ff-32bc05afbdb6`, the synced table reported `SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE`.

## Genie Agent Authoring

Three parsed version-2 configurations are stored under `src/genie/` for Workforce & Attrition, Talent & Performance, and Recruiting. Their primary semantic sources are the eight published metric views; `talent_watchlist` and `semantic_talent_snapshot` are attached only for approved employee-detail workflows.

All six example queries and all 30 canonical benchmark queries passed read-only execution on warehouse `813b0ad2f3036e46`, with non-empty results. Agent-mode benchmark entries use response-quality rubrics and separate checked SQL as ground truth.

| Owner-only Agent | Space | Baseline | Final | Conservatively failed item |
|---|---|---:|---:|---|
| Workforce & Attrition | `01f1d2385a3b1154885702428ed398c9` | 8/10 | 9/10 | Incorrect Fraud Operations engagement indexes. |
| Talent & Performance | `01f1d23a36c11172bc0d26281179b07c` | 6/10 | 9/10 | Correct result routed to the detail view. |
| Recruiting | `01f1d23c9d7f181cbc32056b828897ad` | 7/10 | 9/10 | Full-year result described as year-to-date. |

Approved metadata repairs fixed the other baseline failures. All three Agents meet the 90% initial publication gate; shared access remains deferred.

## App Foundation and Routing

- AppKit `0.84.0` app `aita-david-huang` is `RUNNING` and `ACTIVE`; owner-only deployment `01f1d32fe1b61d9bbd7533cc29e0fb3a` succeeded.
- The router exposes exactly three OBO Genie tools. Its OAuth eval passed all 27 assertions: 9/9 canonical questions matched the exact unique Agent set.
- Chat exposes Agent SQL and identity, preserves per-Agent follow-up IDs, and shows streaming, partial/error, and AI-verification states.
- Watchlist reads passed live pagination and JSONB filters: 3,427 total, 2,199 disengaging, and 777 Consumer Banking rows. Startup parity remains 3,427 distinct keys, zero null keys, and `as_of_date` `2026-12-31`.
- History enforces server-derived ownership and 30-day purge-on-access. A temporary thread completed create, continue, four-message replay, delete, and post-delete 404; query and forwarded-header identity spoof attempts still returned only the owner's 46 threads.

## Final Handoff Check

On October 28, strict AppKit and bundle validation, app deployment, and live metadata reconciliation passed. The job, pipelines, Agents, warehouse, app resources, and DAG match source control and the IDs above. Counts remain 20,000 workers, 18,839 active talent rows, and 3,427 source/synced/app-served watchlist rows; the final SDP update still has zero expectation or AI-error failures.

Phase 15 retained the prior 9/9 routing result without rerun. Final read-only smoke confirmed all three SPA routes, owner-only ACLs, unauthenticated 401, three OBO Genie bindings, SP-only Lakebase, 3,427-row fresh parity, 46 owner threads with 30-day retention, identity-spoof isolation, and expected 400/404 validation responses. Shared release and production benchmark expansion remain deferred.
