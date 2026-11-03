# Aita

FE Bar submission. Aita (AI Talent Advisor) unifies 12 synthetic HR datasets for a fictional bank through Lakeflow pipelines, AI Functions, metric views, Genie Agents, and a Lakebase-served talent watchlist.

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
- **Cost-aware AI:** distinct-text lookups suit this synthetic data (152 calls per refresh); real comments are mostly unique, so production would classify each new comment once as it streams in.
- **Attributable agents:** a code-defined router delegates to three narrow on-behalf-of-user Agents with SQL and source provenance.
- **Fit-for-purpose serving:** the lakehouse stays authoritative; Lakebase serves the watchlist and user-scoped threads.
- **No governance bypass:** masks stay active, signals require human review, and the app stays owner-only until account-level groups enable shared access.

## Repository Map

| Path | Contents |
|---|---|
| `databricks.yml`, `resources/` | Bundle variables, the `aita_sdp` pipeline, and jobs |
| `src/generate/` | Synthetic-data generator and pattern checks |
| `src/setup/gold_governance.sql` | Pre-pipeline compensation mask |
| `src/pipeline/` | Bronze, Silver, Gold, and semantic SDP SQL |
| `src/semantic/` | Metric views, grants, and validation SQL |
| `src/genie/` | Version-2 Agent configs, benchmark SQL, publication, and evaluation |
| `src/app/aita/` | AppKit app, Lakebase stores, and Chat/Watchlist/History shell |
| `evidence/` | Run summaries and raw execution output |

## Reviewer Path

Read these 15 files in order for the architecture, executable path, governance, and proof:
Budget: 102 tracked files (96 UTF-8 text, 6 images) and 443,234 text characters; this path is 15 files and 76,254 characters; files over 9,000 characters: 5.

1. `README.md`
2. `databricks.yml`
3. `resources/aita_pipeline.yml`
4. `resources/aita_app.app.yml`
5. `evidence/pipeline_summary.md`
6. `evidence/semantic_summary.md`
7. `evidence/run_log.md`
8. `src/pipeline/bronze/ingest.sql`
9. `src/pipeline/silver/core.sql`
10. `src/pipeline/semantic/talent_snapshot.sql`
11. `src/setup/gold_governance.sql`
12. `src/semantic/mv_workforce.sql`
13. `src/genie/agent_config.py`
14. `src/app/aita/server/agents/aita/agent.ts`
15. `src/app/aita/shared/routing.ts`

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

Bundle variables parameterize catalogs, schemas, landing paths, warehouse, and Lakebase settings.

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
| App orchestrator | `databricks-claude-haiku-5-5` |

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

Agents use metric views first; detail views support approved employee workflows. Benchmarks separate response rubrics from read-only SQL ground truth.

## One-Time Setup

Create these objects if missing:

```sql
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_silver;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_gold;
CREATE VOLUME IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze.landing;
```

Required privileges: `USE CATALOG` and `CREATE SCHEMA` on the catalog, and `CREATE VOLUME` on `aita_bronze`.

Before the first `aita_pipeline` run, follow `src/setup/lakebase_setup.sh` to provision Lakebase after the source materialized view exists.

## Governance and Access Setup

- Create the `aita_hr_admin` group and assign only approved HR compensation administrators.
- Run `src/setup/gold_governance.sql` before refreshing the pipeline so `aita_gold.mask_compensation` exists before governed Gold tables compile. The `aita_pipeline` job runs it as the `gold_governance` task.
- Verify the same compensation query as a group member and non-member before semantic publication, Genie access, or Lakebase sync.
- Provision `aita_users` and `aita_hr_admin` as account-level groups assigned to the workspace, and add only approved users and service principals. Legacy `WorkspaceGroup` principals cannot receive Unity Catalog grants.
- Semantic grants apply to both groups; only `aita_hr_admin` receives unmasked compensation.
- Without account-level identity administration, keep the app owner-only; do not claim shared access or production readiness.
