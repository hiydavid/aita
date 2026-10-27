# Aita

FE Bar project submission. Aita turns 12 synthetic HR datasets for a fictional bank into a governed Gold star schema with Lakeflow Spark Declarative Pipelines, AI Functions, Unity Catalog metric views, Genie Agents, and a Lakebase-synced talent watchlist.

## Repository Map

| Path | Contents |
|---|---|
| `databricks.yml`, `resources/` | Bundle variables, the `aita_sdp` pipeline, and jobs |
| `src/generate/` | Deterministic synthetic-data generator and planted-pattern checks |
| `src/setup/gold_governance.sql` | Compensation mask function created before the pipeline runs |
| `src/pipeline/` | SDP SQL for Bronze, Silver, Gold, and semantic helper views |
| `src/semantic/` | Metric views, Unity Catalog grants, and semantic validation SQL |
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
| Lakebase project | `aita_lakebase` (`projects/aita-lakebase`, Postgres 17) |
| Lakebase synced table | `aita_gold.talent_watchlist_serving` |

## Commands

- Check the profile: `databricks current-user me --profile genie-workbench`
- Validate: `databricks bundle validate -t dev --profile genie-workbench`
- Deploy: `databricks bundle deploy -t dev --profile genie-workbench`
- Run: `databricks bundle run aita_pipeline -t dev --profile genie-workbench`

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
