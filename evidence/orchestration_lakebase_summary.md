# Phase 8 Orchestration and Lakebase Sync

## Deployment

| Item | Result |
|---|---|
| Final orchestration run | `1073150973022044` — PASS |
| SDP update | `ca8c43ee-c9ac-4614-b342-a5ee56e78fb6` — COMPLETED |
| Semantic publication run | `269141171180276` — PASS |
| Lakebase update | `e4c38851-fe0d-4004-972a-6f3a0df4d2d1` — COMPLETED |
| Bundle validation | `dev` target with `genie-workbench` — PASS |

All five `aita_pipeline` tasks passed: `generate_data`, `gold_governance`, `sdp_pipeline`, `publish_semantics`, and `sync_lakebase`. The SDP task uses full refresh because the generator replaces complete landing snapshots; this prevents repeated orchestration runs from appending duplicate files to Bronze.

Shared Unity Catalog grants remain isolated in `aita_apply_semantic_grants` and are not required by the owner-only orchestration path.

## Lakebase Contract

| Setting | Value |
|---|---|
| Project | `projects/aita-lakebase` (`aita_lakebase`, Postgres 17) |
| Branch and database | `production` / `databricks_postgres` |
| Source | `genie_workbench_dev_catalog.aita_gold.talent_watchlist` |
| Synced table | `genie_workbench_dev_catalog.aita_gold.talent_watchlist_serving` |
| Postgres destination | `aita_gold.talent_watchlist_serving` |
| Primary key | `employee_id` |
| Update behavior | Job-triggered full snapshot after each successful SDP refresh |
| Approved columns | `employee_id`, `business_line`, `risk_flags`, `reasons`, `signal_count`, `as_of_date` |

Snapshot mode is required because the source is a materialized view and triggered incremental sync requires external CDF metadata. The small watchlist is refreshed in full after each pipeline run.

## Reconciliation

| Check | Source | Lakebase | Result |
|---|---:|---:|---|
| Rows | 3,427 | 3,427 | PASS |
| Distinct employee keys | 3,427 | 3,427 | PASS |
| Null employee keys | 0 | 0 | PASS |
| Maximum as-of date | 2026-12-31 | 2026-12-31 | PASS |

The full-refresh pipeline also restored the expected 404,028 Bronze rows. The synced table reported `SYNCED_TABLE_ONLINE_NO_PENDING_UPDATE` after the final run.
