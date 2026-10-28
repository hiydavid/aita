# Aita Build Progress

Last updated: October 28, 2026

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
| Phase 9: Genie Agents | Three owner-only, metric-view-first Agents are live; their 30 Agent-mode benchmarks and six examples have 36 passing SQL checks, and each Agent meets the 90% initial gate |
| Phase 10: Pipeline and semantic handoff | Live DAGs, lineage, layer previews, deployed IDs, expectation results, AI outputs, Agent sources, and Lakebase status reconciled with source and evidence |
| Phase 11: App specification | `docs/app_spec.md` defines routing, Chat/Watchlist/History behavior, Lakebase state, security boundaries, evaluation, and release gates; implementation has not started |
| Phase 12: App foundation | AppKit `0.84.0` shell deployed as owner-only `aita-david-huang`; Haiku 5.5 streams tool calls, Genie is OBO, Lakebase is SP-only, and persistent user-scoped threads plus supplemental routing metadata are initialized |

## Deferred: Shared Semantic Access

Unity Catalog grants are not applied: `aita_users` and `aita_hr_admin` are legacy workspace-local groups, and no account administrator is available to provision account-level replacements. The demo runs under the owner-only constrained demo exception in `docs/semantics_spec.md` and must not be described as production-ready for shared access.

As a result, the demo cannot show different users receiving different outputs. Compensation-mask behavior is evidenced only by the project owner running the same query before and after joining the workspace-local `aita_hr_admin` group.

Account-level groups are out of scope for this demo. If they are provisioned later, replace both groups, preserve approved membership, run `aita_apply_semantic_grants`, and verify effective Unity Catalog access.

## Deferred: Production Benchmark Expansion

Each Agent remains at its 10 canonical Agent-mode benchmarks. The app's initial routing evaluation can reuse the 30 existing questions across the three Agents, but productionization still requires at least 30 valid items per Agent. The three owner-only Agents have completed the current 90% initial validation gate.

## Next Phases: Aita App

The implementation contract is in `docs/app_spec.md`. The owner-only app foundation is live; routing, Watchlist/History behavior, and evaluation remain.

| Phase | Scope |
|---|---|
| Phase 13: Routing and Chat | Implement domain routing, multi-Agent synthesis, follow-up context, SQL provenance, streaming, and trust states |
| Phase 14: Watchlist and History | Implement synced-table reads, metadata capture, replay, deletion, filtering, pagination, and required UI states; verify user isolation and retention end to end |
| Phase 15: Evaluation and handoff | Run routing, SQL, parity, security, and state checks; deploy; and record compact evidence |

The initial routing evaluation must cover all 30 canonical single-domain questions, the three semantic cross-domain examples, and at least two ambiguous questions, with at least 90% exact-match routing accuracy.

The existing Lakebase-synced watchlist and three domain Agents are wired to the app. Shared-user release remains blocked until account-level groups satisfy semantic publication gate 3; only the owner-scoped development deployment may proceed under the constrained-demo exception.

## Handoff

The pipeline, semantic layer, domain Agents, Lakebase serving path, and app foundation are complete. Aita app phases 13 through 15 remain. Shared access, per-Agent 30-benchmark expansion, and production routing remain deferred. The project owner handles commits.
