# Aita Repository Guidance

## Priorities

Use this order when tradeoffs are necessary:

1. Correct, working behavior.
2. Security, privacy, and governance.
3. Maintainable, testable implementation.
4. Reviewer-size optimization.

Do not minify code, merge unrelated concerns, remove meaningful validation, or weaken governance solely to reduce submission size.

## Sources of Truth

- Read the environment, resource, and command sections of `README.md` before running Databricks commands.
- Use `docs/pipeline_spec.md` for pipeline datasets, layers, grains, business rules, and governance requirements.
- Use `docs/semantics_spec.md` for semantic helpers, metric definitions, Genie Agent behavior, access, and evaluation requirements.
- Use `docs/progress.md` to identify completed work and the next unfinished phase.
- Keep detailed product requirements in their specs rather than duplicating them in code comments or new planning documents.

## Scope and Style

- Build incrementally by phase and avoid unrelated changes.
- Prefer extending an appropriate existing file over adding a new file, but keep concerns separated when that improves correctness or maintainability.
- Avoid speculative abstractions, placeholder components, duplicate documentation, and verbose evidence narratives.
- Use exact table, column, metric, and resource names from the specs.
- Do not commit changes unless the user explicitly requests it; the project owner makes phase commits.

## Databricks Workflow

- Use the `genie-workbench` profile explicitly with every Databricks CLI command and the `dev` bundle target unless the user requests another environment.
- Use bundle variables for catalogs, schemas, landing paths, warehouse IDs, and other environment-specific values; do not hardcode them in pipeline, semantic, or Agent definitions.
- Keep pipelines and jobs serverless unless a documented platform limitation requires otherwise.
- Validate relevant SQL and bundle configuration before deployment, then run the narrowest useful verification before broader checks.

## Architecture Guardrails

- Use synthetic data only.
- Use SQL for pipeline transformations and Python for synthetic-data generation.
- Keep Bronze faithful to landed data; put typing, conformance, deduplication, expectations, and AI enrichment in Silver.
- Run repeated AI inference through private lookups over distinct normalized text, then join the cached results to published rows.
- Preserve declared grains and validate uniqueness, row counts, temporal joins, and join fan-out before publishing Gold or semantic outputs.
- Put reusable calculations in metric views, grain-changing logic in governed semantic helper views, and domain behavior in Agent configuration.
- Allow only many-to-one dimension joins inside metric views; never expose measures from joined fact-like sources that can fan out.
- Do not join current employee attributes onto historical facts when doing so would rewrite history.
- Preserve compensation masks and existing access boundaries. Do not add or remove row filters without explicit approval.
- Validate example and benchmark SQL with read-only execution before publishing it to a Genie Agent.
- Obtain explicit approval before creating or updating live Genie Agents.

## Reviewer Budget

The reviewer reads at most 30 files, 9,000 characters per file, and 90,000 characters total. Treat these as development guardrails and final-submission constraints, not as reasons to compromise working code or quality.

- Track the budget when adding files or substantial documentation and call out meaningful growth.
- Keep new documentation and evidence concise and non-duplicative.
- Do not split or combine files solely to game the limits.
- Complete a dedicated consolidation pass after the build is functionally complete.
- During final consolidation, preserve executable behavior, essential design rationale, validation results, and reviewer-readable entry points.

## Evidence

- Capture only evidence needed to prove behavior: run or update IDs, row counts, expectation results, representative AI outputs, grain checks, parity checks, and pass/fail conclusions.
- Prefer compact tables and summaries over command transcripts or repeated narrative.
- Record evidence in `evidence/pipeline_summary.md` (generation through Gold) or `evidence/semantic_summary.md` (governance, semantic layer, Agents, and orchestration). Add a section to the matching file rather than creating a new evidence file.
- Replace superseded results instead of appending history; keep a one-line note only when a resolved issue explains the current design.
