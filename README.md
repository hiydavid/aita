# Aita

FE Bar submission. Aita unifies 12 synthetic HR datasets for a fictional bank through Lakeflow pipelines, AI Functions, metric views, Genie Agents, and a Lakebase-served talent watchlist.

## Banking Problem

Aita connects workforce, talent, and recruiting signals before they create service disruption or backfill costs. Governed analysis links attrition, engagement, talent, pay, skills, and hiring. Its rule-based watchlist prompts human review, never employment decisions.

**Synthetic-data disclosure:** The bank, people, dates, scenarios, and all business figures are synthetic. The benchmark covers 20,000 employees, 24 months, and 12 generated datasets; results demonstrate behavior, not real-world impact.

## Buyer Outcomes

- **Executive sponsor:** Chief Human Resources Officer (CHRO).
- **Domain owner:** Head of Workforce Strategy and People Analytics.

| FSI Industry Outcome Map alignment | Buyer KPIs | Synthetic evidence |
|---|---|---|
| Operational efficiency | Attrition, engagement, overtime, backfills, time to fill | 108 contact-center spike exits; fraud engagement down 1.537 points as overtime rose 2.456x |
| Customer experience | CSAT, handle time, quality, staffing stability | 3 standout managers pair high engagement and CSAT with less than half the bank attrition rate |
| Workforce transformation | Stalled talent, pay position, internal mobility | 969 stalled high performers; 738 internal applicants pursued adjacent technology work |
| Risk and responsible AI | Compensation access, metric parity, reviewability, AI traceability | 3 compensation measures stay masked; 3,427 watchlist rows retain reasons and human-review warnings |

## Design Decisions

- **Governed semantics:** calculations stay in metric views, grain changes in helper views, and historical attributes on facts.
- **Cost-aware AI:** private lookups cache distinct normalized text; the synthetic refresh uses 152 calls instead of about 383,492 per-row calls.
- **Attributable agents:** a code-defined router delegates to three narrow on-behalf-of-user Agents with SQL and source provenance.
- **Fit-for-purpose serving:** the lakehouse stays authoritative; Lakebase serves the watchlist and user-scoped threads.
- **No governance bypass:** masks stay active, signals require human review, and the app stays owner-only until account-level groups enable shared access.

## Repository Map

| Path | Contents |
|---|---|
| `databricks.yml`, `resources/` | Bundle variables, the `aita_sdp` pipeline, and jobs |
| `src/generate/` | Deterministic synthetic-data generator and planted-pattern checks |
| `src/setup/gold_governance.sql` | Compensation mask function created before the pipeline runs |
| `src/pipeline/` | SDP SQL for Bronze, Silver, Gold, and semantic helper views |
| `src/semantic/` | Metric views, Unity Catalog grants, and semantic validation SQL |
| `src/genie/` | Parsed version-2 Genie Agent configs, benchmark SQL, publication tooling, and Agent-mode evaluation |
| `src/app/aita/` | AppKit owner-only development app, Lakebase thread store, and Chat/Watchlist/History shell |
| `docs/pipeline_spec.md` | Pipeline datasets, layers, grains, business rules, and Gold governance |
| `docs/semantics_spec.md` | Semantic helpers, metric definitions, Genie Agents, access, and evaluation |
| `docs/progress.md` | Phase status and next steps |
| `evidence/` | Run evidence: `pipeline_summary.md` and `semantic_summary.md` |
| `AGENTS.md` | Contributor and coding-agent rules |

## Environment

| Setting | Value | Bundle variable |
|---|---|---|
| Databricks CLI profile | `genie-workbench` | |
| Bundle target | `dev` | |
| Catalog | `genie_workbench_dev_catalog` | `catalog` |
| Bronze schema | `aita_bronze` | `bronze_schema` |
| Silver schema | `aita_silver` (pipeline default schema) | `silver_schema` |
| Gold schema | `aita_gold` (Gold tables, semantic helpers, and metric views) | `gold_schema` |
| Landing path | `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/<dataset>/` | `landing_path` (volume root) |
| SQL warehouse | `813b0ad2f3036e46` (`genie-workbench-test`, serverless) | `warehouse_id` |
| Lakebase project ID | `aita-lakebase` | `lakebase_project` |
| Lakebase branch | `projects/aita-lakebase/branches/production` | `lakebase_branch` |
| Lakebase database | `databricks_postgres` | `lakebase_database` |
| Lakebase database resource | `projects/aita-lakebase/branches/production/databases/databricks-postgres` | `lakebase_database_resource` |
| Lakebase synced table | `genie_workbench_dev_catalog.aita_gold.talent_watchlist_serving` | `lakebase_synced_table` |
| Lakebase sync pipeline | `460f8caf-0187-4590-8ae3-38c306cff78c` | `lakebase_sync_pipeline_id` |
| Pipeline and job compute | Serverless | |

Catalog, schema, and landing-path values are passed to the SDP pipeline as configuration parameters. Warehouse and Lakebase values configure downstream job tasks. Pipeline SQL must reference parameters rather than hardcoded catalog or schema names.

## Resources

| Resource | Name |
|---|---|
| SDP pipeline | `aita_sdp` |
| Lakeflow job | `aita_pipeline` (`generate_data` + `gold_governance` → `sdp_pipeline` → `publish_semantics` + `sync_lakebase`) |
| Semantic publication job | `aita_publish_semantics` |
| Deferred semantic grants job | `aita_apply_semantic_grants` |
| Workforce & Attrition Agent | `01f1d2385a3b1154885702428ed398c9` |
| Talent & Performance Agent | `01f1d23a36c11172bc0d26281179b07c` |
| Recruiting Agent | `01f1d23c9d7f181cbc32056b828897ad` |
| Aita development app | `aita-david-huang` (`e4878bfe-f34e-403f-bc96-fdeb5048f3e8`, owner-only) |
| App orchestrator model | `databricks-claude-haiku-5-5` |
| Lakebase project | `aita_lakebase` (`projects/aita-lakebase`, Postgres 17) |
| Lakebase synced table | `aita_gold.talent_watchlist_serving` |

## Commands

- Check the profile: `databricks current-user me --profile genie-workbench`
- Validate: `databricks bundle validate -t dev --profile genie-workbench`
- Deploy: `databricks bundle deploy -t dev --profile genie-workbench`
- Deploy and start the app: `databricks bundle run aita_app -t dev --profile genie-workbench`
- Run: `databricks bundle run aita_pipeline -t dev --profile genie-workbench`

## Genie Agent Development

- Validate all local configs and benchmark mappings: `python3 src/genie/manage_agents.py validate`
- Read-only test all examples and benchmark SQL: `python3 src/genie/manage_agents.py check-sql --profile genie-workbench --warehouse-id 813b0ad2f3036e46 --catalog genie_workbench_dev_catalog --gold-schema aita_gold --output /tmp/aita_genie_sql_results.json`
- Render deployable configs: `python3 src/genie/manage_agents.py render --catalog genie_workbench_dev_catalog --gold-schema aita_gold --output /tmp/aita_genie`
- Publish only after configuration review and explicit approval: `python3 src/genie/manage_agents.py publish workforce_attrition --profile genie-workbench --warehouse-id 813b0ad2f3036e46 --catalog genie_workbench_dev_catalog --gold-schema aita_gold --parent-path /Workspace/Users/<user>/aita/genie --approve-live`
- Capture Agent-mode SQL and responses: `python3 src/genie/evaluate_agent.py workforce_attrition --space-id <space-id> --profile genie-workbench --output /tmp/aita_workforce_agent_eval.json`

The three Agents use the published metric views as their primary semantic sources. Detail views are attached only for approved employee-level workflows. Agent-mode benchmarks carry response-quality rubrics; separately versioned benchmark SQL supplies read-only ground truth.

## One-Time Setup

Create these objects if they are not already present:

```sql
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_silver;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_gold;
CREATE VOLUME IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze.landing;
```

Required privileges: `USE CATALOG` and `CREATE SCHEMA` on the catalog, and `CREATE VOLUME` on `aita_bronze`.

## Governance and Access Setup

- Create the `aita_hr_admin` group and assign only approved HR compensation administrators.
- Run `src/setup/gold_governance.sql` before refreshing the pipeline so `aita_gold.mask_compensation` exists before governed Gold tables compile. The `aita_pipeline` job runs it as the `gold_governance` task.
- Verify the same compensation query as both a group member and a non-member before publishing metric views, exposing data through Genie, or activating Lakebase sync.
- Provision `aita_users` and `aita_hr_admin` as account-level groups assigned to the workspace, and add only approved users and service principals. Legacy `WorkspaceGroup` principals cannot receive Unity Catalog grants.
- Semantic grants apply to both groups; only `aita_hr_admin` receives unmasked compensation.
- If account-level identity administration is unavailable, follow the owner-only constrained demo exception in `docs/semantics_spec.md`.
