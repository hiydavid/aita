# Aita Semantic Layer & Genie Agents Design

## Metric views, Genie Agents, and access for Aita (Oct 25, 2026)

### Purpose

This doc covers everything between the governed Gold tables in the Aita SDP design and the Aita app described by the App, Routing & Lakebase design:

- **Access:** who can read and query the semantic layer.
- **Semantic sources:** grain-safe helper views for definitions that span multiple Gold facts.
- **Metric views:** the single governed definition of every reusable measure.
- **Three domain Genie Agents:** Workforce & Attrition, Talent & Performance, and Recruiting.
- **Cross-domain consistency:** shared keys, dates, and population rules used by the future routing agent.
- **Creation and evaluation:** how the metric views and agents are deployed, benchmarked, and verified.

Its outputs feed the routing agent: agent descriptions become tool descriptions, and benchmark questions seed the routing evaluation set.

**Design principle:** calculations live in metric views, grain-changing logic lives in governed semantic helper views, behavior lives in agent configuration, and each agent remains narrow and domain-specific.

### Target environment

| Setting | Value |
|---|---|
| Catalog | `genie_workbench_dev_catalog` |
| Semantic schema | `aita_gold` |
| Source tables | Governed `aita_gold` dimensions, facts, and `talent_watchlist` |
| CLI profile | `genie-workbench` |
| Bundle target | `dev` |
| SQL warehouse | One serverless warehouse resolved before deployment and passed as `warehouse_id` |
| Build tool | Genie Code CLI, from the repo root |

### Access and grants

| Principal | Grants | Notes |
|---|---|---|
| `aita_users` | `USE CATALOG`; `USE SCHEMA` on `aita_gold`; `SELECT` on approved Gold tables, semantic helper views, and metric views; `CAN USE` on the SQL warehouse; `CAN RUN` on the three Genie Agents | Includes approved demo users and the app service principal; no access to `aita_bronze` or `aita_silver` |
| `aita_hr_admin` | Everything granted to `aita_users`; also sees unmasked compensation through `mask_compensation` | The group already exists; approved administrators must also receive the semantic-layer grants |
| Genie Agents | Query as the signed-in user | The user's Unity Catalog grants and compensation mask apply to every generated query |

- Unity Catalog grants are defined in `src/semantic/grants.sql`.
- SQL warehouse and Genie Agent permissions are workspace-object permissions and are applied by the semantic deployment tooling.
- The existing compensation mask remains authoritative: `base_salary`, `bonus`, and `pay_position_to_midpoint` are visible only to `aita_hr_admin`; band fields and `below_band_midpoint_flag` remain available to `aita_users`.
- No row filters are added in v1.

### Metric-view design rules

1. Every metric view has exactly one fact table, helper view, or metric view as its source.
2. A semantic helper view is used only when a measure must combine facts, select a latest record, change grain, or explode an array.
3. Joins declared inside a metric view are many-to-one dimension joins. Measures from a joined fact-like table are never exposed because they would fan out.
4. Ratios are composed from atomic measures with `MEASURE()` so they re-aggregate at query time.
5. Categorical answers such as "top exit reason" are produced by ranking a dimension with a count measure; they are not defined as measures.
6. Each dimension and measure has a business comment, display name, and genuine synonyms. Percentages and currency measures include formats where the deployed metric-view version supports them.
7. Metric-view composition is supported but is not used as a dimension mixin. Identical conformed dimension expressions are repeated across views and parity-tested.

### Conformed dimensions

The generated organization model is flat at `org_unit_id`; it does not contain separate branch and team hierarchy columns. The semantic layer therefore exposes the real shared organization keys below. User terms such as branch, team, contact center, and fraud operations map to `org_unit_name` and `org_type` through synonyms and entity matching.

| Dimension | Source | Availability |
|---|---|---|
| `business_line`, `region`, `org_unit_id`, `org_unit_name`, `org_type`, `location` | `dim_org` | Every view with an organization key |
| `job_family`, `job_level`, `licensed_role_flag`, `strategic_role_flag`, `genai_exposure_tier` | `dim_job` | Every view with a job key |
| `manager_id` | Source fact or current employee snapshot | Attrition, engagement, and talent only |
| `tenure_band` | Derived from tenure at the relevant event or snapshot date | Attrition and talent only |
| `month`, `quarter`, `year` | Relevant fact date joined to `dim_date` or identically derived | Every time-bearing view |

Historical views use attributes recorded on the fact. Current-state talent questions use the governed employee snapshot. Current `dim_worker` attributes are not joined onto historical facts when that would rewrite history.

### Semantic helper views

#### `semantic_workforce_monthly`

- **Grain:** organization unit × job code × month.
- **Purpose:** preserve monthly headcount and movement measures while adding regrettable voluntary exits aggregated from `fact_attrition_event` at the identical grain.
- **Sources:** `fact_headcount_monthly` plus a pre-aggregated `fact_attrition_event` subquery.
- **Controls:** one output row per grain; no raw exit rows are joined to monthly headcount.

#### `semantic_talent_snapshot`

- **Grain:** one row per active employee as of the latest Gold business date.
- **Purpose:** support current talent questions without mixing annual performance and compensation rows at query time.
- **Sources:** `dim_worker`, the latest `fact_performance` row, the latest `fact_compensation` row, `dim_org`, `dim_job`, and `talent_watchlist`.
- **Gold prerequisite:** add `last_promotion_date` to `dim_worker`; derive `months_since_promotion_or_hire` from the last promotion date, or from `hire_date` when the employee has never been promoted.
- **Controls:** compensation columns retain their existing masks; the stalled-high-performer flag matches the published watchlist rule exactly.

#### `semantic_talent_skills`

- **Grain:** active employee × demonstrated skill from the employee's latest performance review.
- **Purpose:** make AI-extracted skills countable without using an array as a grouped dimension or duplicating employee-level talent measures.
- **Source:** `semantic_talent_snapshot` with `demonstrated_skills` exploded to one normalized skill per row.

### Metric views

#### Workforce & Attrition

| Metric view | Source | Measures |
|---|---|---|
| `mv_workforce` | `semantic_workforce_monthly` | Period-end headcount; average monthly headcount; hires; exits; voluntary exits; regrettable voluntary exits; voluntary attrition rate; regrettable attrition rate |
| `mv_attrition` | `fact_attrition_event` | Exits; voluntary exits; regrettable exits; regrettable voluntary exits |
| `mv_engagement` | `fact_engagement` | Engagement index; previous-wave engagement index; engagement change; negative comment share; burnout-or-workload signal rate |
| `mv_productivity` | `fact_productivity` | Cases handled; overtime hours; average overtime hours per team-month; case-weighted CSAT; case-weighted average handle time; case-weighted quality score |

Definitions:

- **Period-end headcount:** active employees at the latest selected month end; it is semi-additive over time.
- **Average monthly headcount:** sum of monthly end-of-month headcount divided by the distinct selected month count.
- **Voluntary attrition rate:** voluntary exits divided by average monthly headcount for the selected period.
- **Regrettable attrition rate:** voluntary exits with `regrettable_flag = true` divided by average monthly headcount for the selected period.
- **Engagement change:** current survey-wave engagement index minus the immediately previous survey-wave index using a metric-view window measure ordered by survey date.
- **Burnout-or-workload signal rate:** survey responses whose `comment_theme` is `burnout` or `workload` divided by survey responses with a classified theme.
- **Top exit reason:** query `mv_attrition` by `exit_reason`, order by exits descending, and return the leading category; `exit_reason` remains explicitly labeled as AI-classified.

Extra dimensions include `termination_type`, `exit_reason`, `exit_sentiment`, `survey_wave`, `comment_theme`, and `comment_sentiment` where supported by the source grain.

#### Talent & Performance

| Metric view | Source | Measures |
|---|---|---|
| `mv_talent` | `semantic_talent_snapshot` | Active employees; high performers; high-performer share; stalled high performers; below-midpoint employees; below-midpoint share; average months since promotion or hire; average pay position to midpoint |
| `mv_talent_skills` | `semantic_talent_skills` | Employees demonstrating the skill; high performers demonstrating the skill |

Definitions:

- **High performer:** an active employee whose latest review has `rating_numeric = 5`. This aligns with Gold `top_rating_flag`; the separate regrettable-exit rule remains ratings 4 or 5.
- **High-performer share:** high performers divided by active employees with a latest review.
- **Stalled high performer:** latest rating 5, below band midpoint, and no promotion in the last 36 months; employees never promoted use hire date as the career-movement baseline. This is identical to the `talent_watchlist` rule.
- **Below-midpoint share:** active employees whose latest compensation record has `below_band_midpoint_flag = true` divided by active employees with a latest compensation record.
- **Average pay position to midpoint:** average of the latest masked `pay_position_to_midpoint`; unauthorized users receive NULL rather than a leaked aggregate.
- **Average months since promotion or hire:** average months since the latest promotion, or since hire for employees never promoted.

Extra dimensions include `performance_rating`, `potential_rating`, `pay_position_band`, `demonstrated_skill`, and the conformed current organization and job dimensions.

#### Recruiting

| Metric view | Source | Measures |
|---|---|---|
| `mv_requisitions` | `fact_requisition` | Requisitions; open requisitions; filled requisitions; average time to fill; backfill requisitions; backfill share; estimated recruiting cost |
| `mv_recruiting_funnel` | `fact_application_funnel` | Applications; internal applications; internal applicant share; offers extended; accepted offers; declined offers; offer acceptance rate; offer decline rate; screen, interview, offer, and hire conversion rates |

`mv_recruiting_funnel` joins `fact_requisition` only as a many-to-one source of requisition, organization, and job dimensions. It does not expose requisition-level measures from the joined table.

Definitions:

- **Open requisitions:** requisitions whose current `status` is `Open`.
- **Average time to fill:** average `time_to_fill_days` for filled requisitions only.
- **Backfill share:** backfill requisitions divided by all requisitions.
- **Offers extended:** applications with `reached_offer_flag = true`.
- **Accepted offers:** applications with `offer_outcome = 'Accepted'`.
- **Declined offers:** applications with `declined_offer_flag = true`.
- **Offer acceptance/decline rate:** accepted or declined offers divided by offers extended.
- **Stage conversions:** separate measures for Applied→Screen, Screen→Interview, Interview→Offer, and Offer→Hire. A generic `stage` dimension is not published because the Gold funnel is one row per application rather than one row per application stage.

Extra dimensions include `requisition_type`, `status`, `source`, `current_stage`, `decline_reason`, `internal_candidate_flag`, and the requested-role and internal-applicant job dimensions.

#### Watchlist

`talent_watchlist` is attached directly to the Workforce & Attrition Agent because its primary questions are list-style ("who" and "why"). It is not exposed as a metric view. The watchlist is a prompt for human review, not an employment decision.

### Genie Agents

Each Agent has a narrow description, approved data sources, structured column configuration, concise behavior instructions, checked example SQL, synonyms, sample questions, and an initial set of 10 canonical benchmarks.

#### 1. Workforce & Attrition

- **Description:** "Headcount, hires, exits, voluntary and regrettable attrition, AI-classified exit reasons, engagement, burnout signals, contact-center productivity, and the talent watchlist of flagged employees. Not for pay, promotions, or recruiting."
- **Assets:** `mv_workforce`, `mv_attrition`, `mv_engagement`, `mv_productivity`, `talent_watchlist`, `dim_worker`, and `dim_org`.
- **Instructions:**
    - Use metric-view measures for every rate; never recompute attrition from raw tables.
    - "Attrition" means voluntary attrition unless the user says otherwise.
    - When asked why, rank the AI-classified exit reasons or comment themes and state that they are AI-classified.
    - For watchlist questions, list employees with their flags and reasons and state that the watchlist is a prompt to investigate, not a decision.
- **Synonyms:** turnover = attrition; leavers = exits; flight risk = watchlist; team/branch/contact center = organization unit.
- **Canonical benchmarks:**
    1. How has voluntary attrition tracked YTD versus the last two years, by business line?
    2. Which contact centers have the highest voluntary attrition this year?
    3. What are the top exit reasons in Consumer Banking contact centers?
    4. Which managers' teams account for most exits in those centers?
    5. Where is the burnout-or-workload signal rate highest?
    6. Who are the standout managers by engagement and low attrition?
    7. Who is on the watchlist in Consumer Banking, and why?
    8. How did engagement and overtime change in Fraud Operations over the last year?
    9. Which job families have the highest regrettable attrition rate?
    10. What were headcount, hires, and exits in the latest month by region?

#### 2. Talent & Performance

- **Description:** "Current performance, potential, promotions, high performers, governed pay position against band midpoint, AI-extracted skills, and GenAI exposure of roles. Not for attrition counts or recruiting."
- **Assets:** `mv_talent`, `mv_talent_skills`, `semantic_talent_snapshot`, `dim_job`, `dim_worker`, and `dim_org`.
- **Instructions:**
    - "High performer" means `rating_numeric = 5` on the latest review.
    - Compensation values may be masked. If average pay position is NULL, state that the user is not authorized to see it and offer the unmasked below-midpoint share.
    - GenAI exposure tiers and demonstrated skills are AI-derived; say so when presenting them.
- **Synonyms:** comp = compensation; top talent = high performers; AI exposure = GenAI exposure; team/branch = organization unit.
- **Canonical benchmarks:**
    1. Which senior high performers have not been promoted in three or more years?
    2. What share of high performers in strategic roles are paid below midpoint?
    3. Which job families have the highest GenAI exposure, and how many active employees are in them?
    4. What AI-extracted skills show up most often for high performers in Technology?
    5. What is the latest high-performer share by business line?
    6. Which job families have the highest below-midpoint share?
    7. What is the average time since promotion or hire for strategic roles?
    8. Which high performers are also on the talent watchlist?
    9. How does high-potential share vary by job level?
    10. Which demonstrated skills are most common in high-GenAI-exposure roles?

#### 3. Recruiting

- **Description:** "Requisitions, candidate funnel, time to fill, offer acceptance and declines with AI-classified decline reasons, backfill versus new hiring, and internal mobility applicants. Not for current-employee attrition."
- **Assets:** `mv_requisitions`, `mv_recruiting_funnel`, `dim_job`, `dim_org`, and `dim_worker`.
- **Instructions:**
    - Time to fill includes filled requisitions only and is measured in calendar days.
    - "Licensed roles" uses `licensed_role_flag`.
    - When asked why offers are declined, rank the AI-classified decline reasons and state that they are AI-classified.
- **Synonyms:** reqs = requisitions; TTF = time to fill; backfills = backfill requisitions; team/branch = organization unit.
- **Canonical benchmarks:**
    1. What is the average time to fill for licensed advisor roles versus all other roles?
    2. Why are candidates declining offers for licensed roles?
    3. How many backfill requisitions were opened in the two contact centers this year?
    4. Which open roles have internal applicants from GenAI-exposed job families?
    5. What are offer acceptance and decline rates by recruiting source?
    6. How do stage conversion rates differ for licensed and non-licensed roles?
    7. Which business lines have the most open requisitions?
    8. What are backfill share and average time to fill by job family?
    9. Which organization units have the highest internal applicant share?
    10. What are the top AI-classified decline reasons in Wealth Management?

### Cross-domain consistency

The future routing agent answers cross-domain questions by calling multiple domain Agents and joining results at approved keys.

- **Shared keys:** `business_line`, `region`, `org_unit_id`, `org_unit_name`, `org_type`, `job_family`, and calendar month where supported by the source grain.
- **Time:** calendar month, quarter, and year; YTD always means calendar YTD.
- **Population:** each measure states its population explicitly. Workforce headcount is active at month end; attrition is exit events; engagement is survey responses; talent is active employees at the snapshot date; recruiting is requisitions or applications.
- **No invented hierarchy:** branch and team language maps to the flat organization-unit model rather than to nonexistent columns.
- **Cross-domain examples:**
    - "How many backfill requisitions did the contact-center attrition create, and how long are they taking to fill?"
    - "Which flagged employees in GenAI-exposed roles have applied internally?"
    - "Are stalled high performers more likely to be on the watchlist?"

### Creation and deployment

1. Add the targeted Gold prerequisite and build the three semantic helper views.
2. Create and SQL-test all eight metric views before exposing them to an Agent.
3. Resolve the serverless SQL warehouse and apply Unity Catalog and workspace-object grants.
4. Commit each Agent as a parsed version-2 `serialized_space` JSON document under `src/genie/`.
5. Create or update one Agent at a time through an idempotent deployment script, starting with Workforce & Attrition. Live Agent creation or update requires explicit approval.
6. Validate every example and benchmark SQL with read-only execution before loading it into an Agent.
7. Run the canonical benchmarks, fix calculation failures in the semantic layer and behavior failures in Agent configuration, then rerun.

The initial publication gate is at least 90% passing across 10 canonical benchmarks per Agent. Before the routing agent is productionized, expand each set to at least 30 valid items using additional phrasings and edge cases.

### Evaluation and evidence

| Evidence file | Contents |
|---|---|
| `evidence/metric_view_checks.md` | Every key measure queried through its metric view and reconciled to direct Gold SQL, including zero-denominator and multi-month cases |
| `evidence/semantic_grain_checks.md` | Helper-view uniqueness, row counts, join fan-out checks, latest-record checks, and compensation-mask propagation |
| `evidence/genie_benchmarks.md` | Per Agent: question, expected answer, Agent answer, pass/fail result, and overall pass rate |
| `evidence/genie_transcripts.md` | Two or three representative conversations per Agent, including generated SQL |
| `evidence/mask_check.md` | Existing HR-admin and non-HR compensation verification from Gold governance |

### Repo layout additions

| Path | Contents |
|---|---|
| `docs/semantics_spec.md` | This document |
| `src/semantic/base_views.sql` | Grain-safe semantic helper views |
| `src/semantic/metric_views.sql` | All metric-view definitions |
| `src/semantic/grants.sql` | Unity Catalog grants for the semantic layer |
| `src/genie/workforce_attrition.json` | Workforce & Attrition Agent configuration and benchmarks |
| `src/genie/talent_performance.json` | Talent & Performance Agent configuration and benchmarks |
| `src/genie/recruiting.json` | Recruiting Agent configuration and benchmarks |
| `src/genie/create_agents.py` | Idempotent Agent create/update and workspace-permission tooling |

### Remaining decisions before live publication

1. Resolve the serverless SQL warehouse ID and add it as a bundle variable; do not hardcode it in SQL or Agent configuration.
2. Confirm the approved members of `aita_users`, including the app service principal.
3. Confirm the Lakebase destination and primary-key mapping for `talent_watchlist` in the App, Routing & Lakebase design.
4. Validate the exact deployed metric-view YAML syntax for window measures and semantic formats in this workspace before publishing all eight views.
