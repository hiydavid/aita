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
| Phase 11: App specification | `docs/app_spec.md` defines routing, Chat/Watchlist/History behavior, Lakebase state, security boundaries, evaluation, and release gates |
| Phase 12: App foundation | AppKit `0.84.0` shell deployed as owner-only `aita-david-huang`; Haiku 5.5 streams tool calls, Genie is OBO, Lakebase is SP-only, and persistent user-scoped threads plus supplemental routing metadata are initialized |
| Phase 13: Routing and Chat | Code-defined Aita router deployed with three OBO Genie tools; 9/9 representative single-domain questions route to the exact Agent set, and Chat streams answers with Agent/SQL provenance and trust states |
| Phase 14: Watchlist and History | Synced-table filtering, pagination, freshness/parity states, Ask Aita, replay, continuation, deletion, 30-day retention, and user-scoped authorization are deployed and verified end to end |
| Phase 15: Evaluation and handoff | Owner-only release smoke, parity, security, state, deployment, and reviewer-budget checks pass; prior 9/9 routing evidence is retained without rerun |

## Planned: Submission Readiness

| Phase | Scope | Status |
|---|---|---|
| Phase 16: Industry framing | `README.md` only: banking problem statement, buyer KPIs, executive sponsor and domain owner, FSI Industry Outcome Map alignment (all figures labeled synthetic), and a concise Design decisions section carrying the rationale that leaves with the untracked specs | Not started |
| Phase 17: Lakebase review write-back | Append-only `aita_app.watchlist_review_events` (`employee_id`, `as_of_date`, `status`, `note` ≤ 500 chars, server-derived `reviewer`, `created_at`); current status from the latest event; `POST /api/watchlist/:employeeId/review` with enum, length, and current-watchlist validation; status badge, update control, filter, and reviewed count in Watchlist; per-request freshness/parity and bundle-variable synced-table name; validate, deploy to `dev` after approval, verify live; then `/simplify` | Not started |
| Phase 18: Raw execution evidence | New `evidence/run_log.md` (≤ 9,000 chars) of verbatim, timestamped, command-attributed output: fresh `aita_pipeline` run (after approval), event-log expectations, validation and pattern-check SQL, AI Function input/label samples, mask `DESCRIBE`, Genie `check-sql` and Agent-mode evals, router `appkit agent eval`, Lakebase parity and write-back requests, app state; trim both summary files below 9,000 chars and point them to the run log | Not started |
| Phase 19: Untrack, reviewer path, budget | Remove tracked references to `docs/` and `AGENTS.md`; back up, then `git rm --cached` and ignore `docs/`, `AGENTS.md`, `.isaac/`, and `.vscode/`; add a ~15-file Reviewer path to `README.md`; report tracked file and character counts and over-limit reviewer-path files; re-run `bundle validate` | Not started |

Open decisions: review statuses are a shared queue visible to all authorized app users (default); Lakebase is not registered in Unity Catalog for Genie (default); spec backup location is required before Phase 19. The project owner commits and makes the repository public.

## Deferred: Shared Semantic Access

Unity Catalog grants are not applied: `aita_users` and `aita_hr_admin` are legacy workspace-local groups, and no account administrator is available to provision account-level replacements. The demo runs under the owner-only constrained demo exception in `docs/semantics_spec.md` and must not be described as production-ready for shared access.

As a result, the demo cannot show different users receiving different outputs. Compensation-mask behavior is evidenced only by the project owner running the same query before and after joining the workspace-local `aita_hr_admin` group.

Account-level groups are out of scope for this demo. If they are provisioned later, replace both groups, preserve approved membership, run `aita_apply_semantic_grants`, and verify effective Unity Catalog access.

## Deferred: Production Benchmark Expansion

Each Agent remains at its 10 canonical Agent-mode benchmarks. The app's initial routing evaluation uses three representative questions per Agent; productionization still requires at least 30 valid items per Agent plus cross-domain and clarification coverage. The three owner-only Agents have completed the current 90% initial validation gate.

## Aita App Complete

The owner-only implementation and demo evaluation in `docs/app_spec.md` are complete. The initial routing result remains 9/9 canonical single-domain questions; it was not rerun for final handoff. Cross-domain and clarification coverage remains part of production benchmark expansion.

The Lakebase-synced watchlist and three domain Agents are live in the app. Shared-user release remains blocked until account-level groups satisfy semantic publication gate 3; only the owner-scoped development deployment may proceed under the constrained-demo exception.

## Handoff

All 15 build phases are complete for the owner-only demo. Shared access, per-Agent 30-benchmark expansion, and production routing remain deferred. The project owner handles commits.
