# Aita Spark Declarative Pipeline Design

### Purpose

The pipeline turns 12 synthetic HR datasets into a governed Gold star schema. AI Functions structure six free-text fields, and Gold feeds three domain Genie Agents plus a Lakebase-synced talent watchlist.

### Fictional bank

- About 20,000 employees and 24 months of history, generated deterministically with fixed seeds.
- **Business lines:** Consumer Banking (branches, contact centers), Wealth Management (licensed advisors), Commercial Banking (relationship managers), Operations (including fraud ops), Technology, Corporate Functions.
- **Banking angle:** a `licensed_role_flag` on jobs (advisors, mortgage loan originators) drives the time-to-fill and hard-to-backfill story in Recruiting.

### Generated datasets

Written to the landing volume defined in `docs/environment.md`.

| Domain | Dataset | Grain | Format | Free text for AI Functions |
|---|---|---|---|---|
| Core | `workers` | employee | CSV | |
| Core | `job_history` | employee × event (hire, transfer, promotion, manager change, exit) | CSV | |
| Core | `org_units` | org unit (business line, region, branch, team) | CSV | |
| Core | `jobs` | job code (family, level, licensed and strategic flags) | JSON | `job_description` |
| Workforce & Attrition | `engagement_surveys` | employee × survey wave | JSON | `comment` |
| Workforce & Attrition | `exit_interviews` | departed employee | JSON | `exit_comment` |
| Workforce & Attrition | `team_productivity` | team × month (handle time, CSAT, overtime hours) | CSV | |
| Talent & Performance | `performance_reviews` | employee × year (rating, potential) | JSON | `manager_comment` |
| Talent & Performance | `compensation` | employee × year (base, bonus, band min, mid and max) | CSV | |
| Recruiting | `requisitions` | requisition (job, org, open and close dates, status, backfill or new) | CSV | |
| Recruiting | `applications` | candidate × requisition (source, internal worker_id if internal, stage, offer outcome) | JSON | `candidate_summary`, `offer_decline_comment` |
| Recruiting | `application_events` | application × stage change (applied, screen, interview, offer, hired, rejected, declined) | CSV | |

### Planted patterns (each one answers a target question)

- An attrition spike in two contact centers after a schedule change, concentrated under three managers. Exit comments mention schedules and workload.
- Under-recognized high performers in strategic AI and data roles: no promotion in 3+ years, and paid below band midpoint.
- A burnout pocket in fraud operations: overtime up, engagement down, negative comments.
- A group of standout managers: high engagement, low attrition, strong team productivity.
- GenAI-exposed operations roles, with internal candidates from those roles applying to open roles that need adjacent skills.
- Licensed advisor roles take about twice as long to fill. Their offer declines cluster on compensation and competing offers.
- Backfill requisitions in the two contact centers follow the attrition spike, which links attrition to recruiting cost.

### Layers

Catalog, schemas, and landing paths are defined in `docs/environment.md`; table names below omit the catalog prefix.

**Bronze (one streaming table per dataset)**

- `read_files` from the landing folder, adding `_source_file` and `_ingested_at` columns. Use schema hints for key columns and keep the rescued data column.
- No business logic, so bronze is a faithful copy of what landed.

**Silver (cleaned, conformed and enriched)**

| Table | Type | What it does | Expectations | AI Functions |
|---|---|---|---|---|
| `workers` | Streaming table | Types, trims, standardizes business line and location | Valid business line (drop); hire_date not null (fail) | |
| `worker_history` | Streaming table via AUTO CDC, SCD Type 2 | Effective-dated job, org and manager history from `job_history` | event_date on or after hire_date (warn) | |
| `org_units`, `compensation`, `team_productivity`, `requisitions`, `application_events` | Streaming tables | Typed and deduplicated | base within a sane range of the band (warn); close_date on or after open_date (warn) | |
| `jobs_enriched` | Streaming table | Job catalog plus AI tags | job_code unique (warn) | `ai_classify` → `genai_exposure_tier` (high, medium, low); `ai_extract` → `required_skills` |
| `exit_interviews_enriched` | Streaming table | Exit comments plus reason | Comment not empty (warn) | `ai_classify` → `exit_reason` (compensation, manager, schedule and workload, career growth, relocation, other); `ai_analyze_sentiment` |
| `engagement_enriched` | Streaming table | Survey scores plus comment signals | Score between 1 and 5 (drop) | `ai_analyze_sentiment`; `ai_classify` → `comment_theme` (burnout, workload, manager, recognition, positive, other) |
| `performance_enriched` | Streaming table | Ratings plus skills | Rating in the allowed set (drop) | `ai_extract` → `demonstrated_skills` |
| `applications_enriched` | Streaming table | Candidate funnel plus reasons | Requisition exists (warn) | `ai_extract` → `candidate_skills`; `ai_classify` → `decline_reason` (compensation, competing offer, location, process too slow, role fit, other) |

AI Functions run in private silver materialized views over distinct normalized text values. The published silver streaming tables join those cached signals back to every source row, so repeated synthetic comments are inferred once while gold refreshes reuse the stored results.

**Gold (materialized views, star schema)**

| Table | Grain | Used by |
|---|---|---|
| `dim_worker` | employee (current) | All agents |
| `dim_org`, `dim_job`, `dim_date` | org unit, job code, day | All agents |
| `fact_headcount_monthly` | org × job × month | Workforce & Attrition |
| `fact_attrition_event` | exit, with AI exit reason and regrettable flag | Workforce & Attrition |
| `fact_engagement` | employee × wave, with sentiment and theme | Workforce & Attrition |
| `fact_productivity` | team × month | Workforce & Attrition |
| `fact_performance` | employee × year, with skills | Talent & Performance |
| `fact_compensation` | employee × year, pay position to midpoint (masked) | Talent & Performance |
| `fact_requisition` | requisition: time to fill, backfill flag, licensed flag | Recruiting |
| `fact_application_funnel` | application: stages reached, days per stage, decline reason, internal flag | Recruiting |
| `talent_watchlist` | flagged employee | Watchlist tab; Workforce & Attrition |

Metric views defined in `docs/semantics_spec.md` sit on top of Gold.

### Talent watchlist (gold)

`aita_gold.talent_watchlist` is a rule-based flag with readable reasons, built from gold facts and AI-classified signals.

| Rule | Signals used |
|---|---|
| Stalled high performer | Top rating, no promotion in 3+ years, pay below band midpoint |
| Disengaging | Engagement down 2 survey waves in a row, or AI-classified burnout theme |
| Team at risk | Team voluntary attrition above threshold, with AI-classified "manager" or "schedule and workload" exit reasons |
| Hard-to-backfill risk | Licensed or strategic role where time to fill for the job family is above the bank's median, combined with any other flag |

Columns: employee_id, business_line, risk_flags, reasons, signal_count, as_of_date. It syncs to Lakebase after each pipeline run.

### Gold governance

Governance intrinsic to Gold tables is versioned in pipeline SQL. Access grants and semantic validation are defined in `docs/semantics_spec.md`.

**Comments:** Every Gold table and column has a business-friendly comment in its `CREATE OR REFRESH` statement. Table comments state grain, row meaning, and use. Column comments state meaning, units, and allowed values; AI fields also identify source text and labels, while flags and derived measures state their rules. Bronze and Silver require short table comments only.

**Compensation column mask**
- Mask `base_salary`, `bonus`, and `pay_position_to_midpoint` on `aita_gold.fact_compensation`; Silver `annual_bonus` publishes as `bonus` and `compa_ratio` is replaced by `pay_position_to_midpoint`.
- `aita_gold.mask_compensation(value)` returns values only to `aita_hr_admin`; create the group and function before the first pipeline run.
- Attach and maintain the mask through `CREATE OR REFRESH MATERIALIZED VIEW`, not `ALTER TABLE`.
- Keep `band_min`, `band_mid`, and `band_max` unmasked so aggregate band-position questions remain available.

**Attrition:** `regrettable_flag` is true when the exiting employee's latest `rating_numeric` is 4 or 5; otherwise it is false.

**No row filters:** All users see all business lines in v1; business-line ABAC remains a production roadmap item.

Implementation workflow, environment settings, validation expectations, and contributor rules live in `AGENTS.md`, `docs/environment.md`, and `docs/progress.md`.
