# Aita SDP Design

## Spark Declarative Pipelines design for Aita (Oct 24, 2026)

### Purpose

The pipeline turns 12 synthetic HR datasets for a fictional bank into a governed gold star schema. Along the way, AI Functions turn six free-text fields into structured signals, and the pipeline builds a rule-based talent watchlist. The gold layer feeds three Genie Agents (Workforce & Attrition, Talent & Performance, Recruiting) and the Lakebase-synced watchlist.

This doc is also the source for `docs/pipeline_spec.md`, the spec that Genie Code CLI builds from.

### Fictional bank

- Name TBD (different from the fee refund build's bank). About 20,000 employees and 24 months of history, generated once with fixed seeds.
- **Business lines:** Consumer Banking (branches, contact centers), Wealth Management (licensed advisors), Commercial Banking (relationship managers), Operations (including fraud ops), Technology, Corporate Functions.
- **Banking angle:** a `licensed_role_flag` on jobs (advisors, mortgage loan originators) drives the time-to-fill and hard-to-backfill story in Recruiting.

### Generated datasets

Written by the generator to `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/<dataset>/`.

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

That's 12 datasets, 6 of which carry free text.

### Planted patterns (each one answers a target question)

- An attrition spike in two contact centers after a schedule change, concentrated under three managers. Exit comments mention schedules and workload.
- Under-recognized high performers in strategic AI and data roles: no promotion in 3+ years, and paid below band midpoint.
- A burnout pocket in fraud operations: overtime up, engagement down, negative comments.
- A group of standout managers: high engagement, low attrition, strong team productivity.
- GenAI-exposed operations roles, with internal candidates from those roles applying to open roles that need adjacent skills.
- Licensed advisor roles take about twice as long to fill. Their offer declines cluster on compensation and competing offers.
- Backfill requisitions in the two contact centers follow the attrition spike, which links attrition to recruiting cost.

### Layers

**Catalog and schemas:** `genie_workbench_dev_catalog` with `aita_bronze` (plus the `landing` volume), `aita_silver` and `aita_gold`. Table names below are shown without the catalog prefix.

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

Metric views (defined in the main Aita doc) sit on top of gold.

### Talent watchlist (gold)

`aita_gold.talent_watchlist` is a rule-based flag with readable reasons, built from gold facts and AI-classified signals.

| Rule | Signals used |
|---|---|
| Stalled high performer | Top rating, no promotion in 3+ years, pay below band midpoint |
| Disengaging | Engagement down 2 survey waves in a row, or AI-classified burnout theme |
| Team at risk | Team voluntary attrition above threshold, with AI-classified "manager" or "schedule and workload" exit reasons |
| Hard-to-backfill risk | Licensed or strategic role where time to fill for the job family is above the bank's median, combined with any other flag |

Columns: employee_id, business_line, risk_flags, reasons, signal_count, as_of_date. It syncs to Lakebase after each pipeline run.

### Repo and source layout

| Path | Contents |
|---|---|
| `databricks.yml` | Bundle variables (catalog, schemas, landing_path); `dev` target using profile `genie-workbench` |
| `resources/aita_pipeline.yml` | SDP pipeline and `aita_pipeline` job definitions |
| `docs/pipeline_spec.md` | This doc |
| `docs/environment.md` | Profile, catalog, schemas and volume path (context for Genie Code CLI) |
| `src/generate/generate_data.py` | Seeded synthetic data generator |
| `src/generate/pattern_checks.sql` | SQL proving each planted pattern |
| `src/pipeline/bronze/ingest.sql` | Bronze streaming tables |
| `src/pipeline/silver/core.sql`, `workforce.sql`, `talent.sql`, `recruiting.sql` | Silver tables, expectations and AI Functions |
| `src/pipeline/gold/dimensions.sql`, `facts.sql`, `talent_watchlist.sql` | Gold star schema and watchlist |
| `evidence/` | Run summaries, expectation results, sample AI outputs |

Confirm the current AI Function signatures and the AUTO CDC syntax before finalizing the SQL.

### Building it with Genie Code CLI

**Setup (once)**
1. Clone the repo locally and run Genie Code CLI from the repo root, so every generated file lands in Git under my own commits.
2. Commit this doc as `docs/pipeline_spec.md`, plus `docs/environment.md` with the target environment table above.
3. Confirm the CLI profile works: `databricks current-user me --profile genie-workbench`.
4. First prompt: have Genie Code read both docs, then create `databricks.yml` (variables, `dev` target using profile `genie-workbench`) and `resources/aita_pipeline.yml` (serverless pipeline with default catalog and schema, configuration parameters, and the job).

**Layer-by-layer workflow**
1. **Generator.** Write `generate_data.py` and `pattern_checks.sql`. Create the schemas and volume if needed, run the generator, and run the pattern checks.
2. **Bronze.** Write `ingest.sql`, then deploy and run. Check that row counts match the landing files.
3. **Silver without AI.** Typing, deduplication, SCD Type 2 and expectations. Deploy, run, and review expectation metrics.
4. **Silver AI on a sample.** Add the AI Functions through bounded distinct-text lookup views. Inspect about 20 outputs per function, tune the labels, then materialize all distinct texts and join the cached signals back to the full streaming tables.
5. **Gold.** Dimensions, facts and the watchlist. Check grain and join fan-out.
6. **Evidence.** Query the pipeline event log for expectations and row counts, pull sample AI outputs, and write them as markdown into `evidence/`.

**Deploy and run (after each layer)**
- `databricks bundle validate -t dev --profile genie-workbench`
- `databricks bundle deploy -t dev --profile genie-workbench`
- `databricks bundle run aita_pipeline -t dev --profile genie-workbench`

Save the run output for each layer to `evidence/`.

**Working rules**
- One layer per prompt, using exact table and column names from the spec.
- Review every plan and diff before approving, so I can explain each choice in the roleplay. The grader flags purely vibe-coded builds.
- Commit after each layer under my own account, with clear messages.
- Use SQL for the pipeline, because it's easy for the grader to read. Use Python for the generator.
- Use the pipeline parameters for catalog and schema names, never hardcoded values.
- Check exact Genie Code CLI commands and flags in its own help; the public docs mainly cover Genie Code in the Pipelines Editor.

**What to show (demo and evidence)**
- The pipeline graph in the workspace UI: landing files → bronze → silver → gold, across the three schemas.
- Data previews: a raw file, a bronze row, an enriched silver row with the text and its AI label side by side, and a gold table.
- Expectation metrics per table.
- Lineage in Catalog Explorer, from the volume through to gold.

### Open questions

1. Fictional bank name.
2. Final label sets for each `ai_classify` call (tune after the sample run).
3. Current AI Function signatures and AUTO CDC syntax (check before writing the silver SQL).
4. Whether I can create schemas and volumes in `genie_workbench_dev_catalog`, or need them created up front.
5. Exact Genie Code CLI commands and flags.
