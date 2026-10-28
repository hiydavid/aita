# Aita App and Routing Design

### Purpose

This document defines the Aita app's routing, experience, application state, resource boundaries, and acceptance gates.

- Pipeline datasets, the Gold watchlist, and its business rules are defined in `docs/pipeline_spec.md`.
- Agent descriptions, governed metrics, cross-domain keys, access, and benchmark requirements are defined in `docs/semantics_spec.md`.
- Deployed names, IDs, bundle variables, commands, and current status are defined in `README.md` and `docs/progress.md`.

The AppKit app has Chat, Watchlist, and History views and uses Lakebase for low-latency watchlist reads and persistent state.

### Runtime architecture

1. The signed-in user asks Aita a question.
2. An AppKit routing agent selects the fewest relevant domain Genie Agents and calls them on behalf of the user.
3. The router combines their returned results under the cross-domain rules in `docs/semantics_spec.md`; it does not invent measures or unsupported joins.
4. The response shows which Agents answered, their generated SQL, execution identity, status, and AI disclaimer.
5. Conversation state is stored in Lakebase under the app service principal and scoped to the signed-in user.
6. The Watchlist view reads the existing Lakebase synced table under the app service principal.

Genie calls use on-behalf-of-user authorization with the canonical `genie` API scope so Unity Catalog grants and the compensation mask apply. Lakebase remains service-principal-only. Server routes derive identity from trusted Databricks forwarding headers and never accept client-supplied identity for authorization.

The three live Agents are currently owner-only. A shared or production app release is blocked until publication gate 3 in `docs/semantics_spec.md` passes; an owner-only development deployment must retain the constrained-demo disclosures in that spec.

### Routing contract

The router exposes one tool per domain Agent: `workforce_attrition`, `talent_performance`, and `recruiting`. Their descriptions must come from the Agent definitions in `docs/semantics_spec.md` rather than being copied here.

1. Use exactly one Agent for a single-domain question and the fewest Agents needed for a cross-domain question.
2. Follow the shared keys, time definitions, populations, and cross-domain examples in `docs/semantics_spec.md`.
3. Ask one clarifying question before calling an Agent when the domain or requested population is materially ambiguous.
4. State which Agent or Agents answered and keep each Agent's evidence distinguishable.
5. Use only returned data. If no Agent can answer, say so.
6. Explain masked compensation as an authorization outcome and offer an approved unmasked alternative when available.
7. Label AI-classified or AI-extracted fields as such.
8. Treat the watchlist as a prompt for human review, never an employment decision.
9. Prefer a concise headline, a small table when useful, and one or two bounded insights.

For follow-ups, reuse each still-relevant Agent's prior Genie conversation ID. Preserve separate IDs for multi-Agent turns.

### Lakebase

#### Synced watchlist

The app reads the existing synced serving asset identified by the bundle variable `lakebase_synced_table` and documented in `README.md`. Its source, grain, columns, primary key, and business rules remain owned by `docs/pipeline_spec.md`.

- Read only; never write to the synced table.
- Use the existing job-triggered full snapshot after the SDP refresh. The source is a materialized view, so incremental change-data-feed sync is not assumed.
- Query the relation exposed by the Lakebase binding; do not derive a Postgres name by appending `_synced`.
- Grant the app service principal only the Lakebase access needed to read the synced relation.
- Reconcile row count, distinct `employee_id`, null keys, and maximum `as_of_date` after a refresh.

#### Conversation state

Use AppKit's Lakebase-backed thread store as the canonical conversation store in a dedicated app-owned schema such as `aita_app`. It runs as the app service principal. The persistence contract is:

| Entity | Required data |
|---|---|
| Conversation | UUID, owning user identity, title, created timestamp, updated timestamp |
| Turn | UUID, conversation UUID, ordered turn index, role, content, routed Agents, per-Agent Genie conversation IDs, per-Agent generated SQL, latency, created timestamp |

Every list, read, continue, and delete operation must authorize against the server-derived user identity. Retain conversations for at most 30 days, support user-initiated deletion, and do not store access tokens or unnecessary raw tool payloads.

Confirm the scaffolded thread store exposes the required History and per-Agent metadata. If metadata fields are insufficient, add only a supplemental table keyed by thread and turn; do not duplicate message history in custom conversation tables. The app service principal creates and owns the schema after the first deployment; a user-run setup job must not create it.

### Experience design

The app is a desktop-first analytic application for business-line and HR leaders. Use AppKit components and semantic tokens, and confirm exact APIs against the scaffolded AppKit documentation before implementation.

| View | Content | Component direction |
|---|---|---|
| Chat | Question input, streamed answer, routed-Agent badges, generated SQL per Agent, starter questions | `Tabs`, `Badge`, `Card`, `Table`, and the scaffolded `useAgentChat` flow |
| Watchlist | Paginated flagged employees, reasons, as-of date, business-line and flag filters, “Ask Aita” action | `Table`, `Select`, `Badge`, and `Button`; server-side filtering and pagination |
| History | Current user's conversations, timestamps, replay, continue, and delete actions | `Card` or `Table`, with server-authorized Lakebase routes |

All views must implement loading (`Skeleton`), empty (`Empty`), error (`Alert` or inline message), and partial/stale states. The Watchlist view shows freshness and the human-review warning. Chat shows the signed-in identity, truthful OBO execution disclosure, live streaming/error state, inspectable generated SQL, and an “AI-generated — verify” note with every answer.

Starter questions should be sourced from the canonical Agent benchmarks and the cross-domain examples in `docs/semantics_spec.md`; do not maintain a second question list here.

### App resources and orchestration

Derive exact feature and resource keys from `databricks apps manifest` for the installed AppKit version. The intended capabilities are:

- AppKit `agents`, Genie, and Lakebase plugins.
- Three Genie Agent resources configured for OBO execution.
- The existing Lakebase project, branch, and database configured for service-principal access.
- A streaming serving endpoint for the Aita orchestrator model; the downstream Genie Agents retain their own model behavior.
- An app bundle resource in the existing `dev` target.

The app does not need its own SQL warehouse resource unless it directly runs analytics queries; the domain Genie Agents already own the warehouse query path. The existing `aita_pipeline.sync_lakebase` task remains the watchlist refresh mechanism. No new `aita_setup` job is required.

### Evaluation and acceptance

Seed routing evaluation from all 30 canonical single-domain benchmarks in `docs/semantics_spec.md`, then add the three cross-domain examples and at least two ambiguous questions that should clarify before routing. Each item records the expected Agent set and expected behavior.

Release gates:

1. At least 90% exact-match routing accuracy, with clarification accuracy reported separately.
2. Cross-domain answers checked against read-only ground-truth SQL without mixing incompatible grains or populations.
3. OBO verified from configuration and runtime identity; compensation behavior remains governed by the existing mask.
4. Conversation ownership isolation verified for every History route, with no client-controlled identity.
5. Synced-watchlist parity verified for row count, key uniqueness, null keys, and freshness.
6. Loading, empty, error, partial/stale, ambiguous, and unauthorized states exercised.
7. Shared-user release withheld until the semantic shared-access gate passes.

Record compact app, routing, Lakebase, and deployment results in `evidence/semantic_summary.md`; do not create separate routing, transcript, excerpt, or deployment evidence files.

### Remaining implementation checks

1. Select the exact streaming orchestrator model after checking workspace availability, latency, and tool-calling behavior.
2. Confirm the scaffolded Lakebase thread store's metadata surface and add only the supplemental routing metadata it cannot represent.
