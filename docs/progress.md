# Aita Build Progress

Last updated: October 27, 2026

## Completed

Run IDs, row counts, and check results are in `evidence/pipeline_summary.md` (generation through Gold) and `evidence/semantic_summary.md` (governance onward).

| Phase | Outcome |
|---|---|
| Bundle setup | `aita` bundle with the `dev` target, serverless `aita_sdp` pipeline, and `aita_pipeline` job |
| Synthetic data | 404,028 rows across 12 datasets from seed `20261024`; all seven planted patterns pass |
| Bronze and Phase 1 foundations | 12 Auto Loader streaming tables reconcile to landing with full provenance and zero rescued rows; `aita_gold` schema created |
| Phase 2: Silver core | Seven typed tables through keyed AUTO CDC, including SCD Type 2 `worker_history`; zero duplicate grains or expectation failures |
| Phase 3: Silver AI | Five enriched tables; cached AI lookups over distinct text cut a full refresh from about 383,492 AI calls to 152 |
| Phase 4: Gold | Four dimensions, eight facts, and a 3,427-row `talent_watchlist`; zero grain, fan-out, orphan-key, or temporal-join violations |
| Phase 5: Gold governance | Comments on all 13 Gold tables and 187 columns; `mask_compensation` on `base_salary`, `bonus`, and `pay_position_to_midpoint`; no row filters |
| Phase 6: Semantic prerequisites | `last_promotion_date` on `dim_worker` and three semantic helper views; all 13 grain and parity checks pass |
| Phase 7: Metric views | Eight metric views published by `publish_semantics`; all 12 direct-Gold parity checks pass; warehouse `CAN USE` applied |
| Phase 8: Orchestration and Lakebase | Five-task `aita_pipeline` run passes; 3,427 watchlist rows synced to Lakebase |

## Deferred: Shared Semantic Access

Unity Catalog grants are not applied: `aita_users` and `aita_hr_admin` are legacy workspace-local groups, and no account administrator is available to provision account-level replacements. The demo runs under the owner-only constrained demo exception in `docs/semantics_spec.md` and must not be described as production-ready for shared access.

As a result, the demo cannot show different users receiving different outputs. Compensation-mask behavior is evidenced only by the project owner running the same query before and after joining the workspace-local `aita_hr_admin` group.

Account-level groups are out of scope for this demo. If they are provisioned later, replace both groups, preserve approved membership, run `aita_apply_semantic_grants`, and verify effective Unity Catalog access.

## Next Steps

### Phase 9: Genie Agents

1. Commit parsed version-2 Agent configurations for Workforce & Attrition, Talent & Performance, and Recruiting under `src/genie/`.
2. Validate all example and benchmark SQL before live Agent creation or update.
3. Publish one Agent at a time for owner-only validation after explicit approval, starting with Workforce & Attrition; shared Agent access remains deferred.
4. Reach at least 90% on 10 canonical benchmarks per Agent and capture representative generated-SQL transcripts.
5. Expand each benchmark set to at least 30 valid items before productionizing the routing agent.

### Phase 10: Final Evidence and Handoff

1. After Agent evaluation, refresh the evidence summaries against the final orchestration run, including expectation, AI, semantic, metric, Agent, and Lakebase results.
2. Verify the final job and pipeline graphs, Catalog Explorer lineage, and representative raw, Bronze, Silver, Gold, semantic, and Lakebase previews.
3. Reconcile documentation with deployed resource IDs, the final orchestration DAG, and the deferred shared-access limitation.
4. Commit each completed batch under the project owner's account with a clear message.
