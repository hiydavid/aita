# Aita Environment

Context file for Genie Code CLI. Read this together with `docs/pipeline_spec.md` before generating or running anything.

## Target workspace

| Setting | Value |
|---|---|
| Databricks CLI profile | `genie-workbench` |
| Bundle target | `dev` |
| Catalog | `genie_workbench_dev_catalog` |
| Bronze schema | `aita_bronze` |
| Silver schema | `aita_silver` (pipeline default schema) |
| Gold schema | `aita_gold` (gold tables and metric views) |
| Landing volume | `genie_workbench_dev_catalog.aita_bronze.landing` |
| Landing path | `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/<dataset>/` |
| Pipeline compute | Serverless |

## Bundle variables (`databricks.yml`)

| Variable | Default |
|---|---|
| `catalog` | `genie_workbench_dev_catalog` |
| `bronze_schema` | `aita_bronze` |
| `silver_schema` | `aita_silver` |
| `gold_schema` | `aita_gold` |
| `landing_path` | `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing` |
| `warehouse_id` | `813b0ad2f3036e46` (`genie-workbench-test`, serverless) |
| `lakebase_project` | `aita-lakebase` |
| `lakebase_branch` | `projects/aita-lakebase/branches/production` |
| `lakebase_database` | `databricks_postgres` |
| `lakebase_synced_table` | `genie_workbench_dev_catalog.aita_gold.talent_watchlist_serving` |
| `lakebase_sync_pipeline_id` | `460f8caf-0187-4590-8ae3-38c306cff78c` |

Catalog, schema, and landing-path values are passed to the SDP pipeline as configuration parameters. Warehouse and Lakebase values configure downstream job tasks. Pipeline SQL must reference parameters rather than hardcoded catalog or schema names.

## Resources

| Resource | Name |
|---|---|
| SDP pipeline | `aita_sdp` |
| Lakeflow job | `aita_pipeline` (`generate_data` + `gold_governance` → `sdp_pipeline` → `publish_semantics` + `sync_lakebase`) |
| Semantic publication job | `aita_publish_semantics` |
| Deferred semantic grants job | `aita_apply_semantic_grants` |
| Lakebase project | `aita_lakebase` (`projects/aita-lakebase`) |
| Lakebase synced table | `aita_gold.talent_watchlist_serving` |

## Commands

- Check the profile: `databricks current-user me --profile genie-workbench`
- Validate: `databricks bundle validate -t dev --profile genie-workbench`
- Deploy: `databricks bundle deploy -t dev --profile genie-workbench`
- Run: `databricks bundle run aita_pipeline -t dev --profile genie-workbench`

## One-time setup (if not already present)

```sql
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_silver;
CREATE SCHEMA IF NOT EXISTS genie_workbench_dev_catalog.aita_gold;
CREATE VOLUME IF NOT EXISTS genie_workbench_dev_catalog.aita_bronze.landing;
```

Required privileges: USE CATALOG and CREATE SCHEMA on the catalog, and CREATE VOLUME on aita_bronze.

## Gold governance setup

- Create the workspace group `aita_hr_admin` and assign only approved HR compensation administrators.
- Run `src/setup/gold_governance.sql` before refreshing the pipeline so `aita_gold.mask_compensation` exists before governed Gold tables compile.
- Verify the same compensation query as both a group member and a non-member before publishing metric views, exposing data through Genie, or activating Lakebase sync.

## Semantic access setup

- Use the serverless `genie-workbench-test` SQL warehouse through the `warehouse_id` bundle variable.
- Provision `aita_users` and `aita_hr_admin` as account-level groups, assign them to the workspace, and add only approved users and service principals. Legacy `WorkspaceGroup` principals cannot receive Unity Catalog grants.
- Preserve `aita_hr_admin` membership separately; semantic grants apply to both groups, while only `aita_hr_admin` receives unmasked compensation.
- If account-level identity administration is unavailable, use the documented owner-only constrained demo: retain masks, rely only on the project owner's existing privileges, add no direct per-user Unity Catalog workaround, and defer multi-user, service-principal, and shared Genie Agent access.

## Rules for Genie Code
* Work one layer at a time, following docs/pipeline_spec.md.
* Use the exact table and column names from the spec.
* Run against profile genie-workbench only.
* Write run outputs (row counts, expectation results, sample AI Function outputs) as small markdown files in evidence/.
* Use synthetic data only.


**Notes:**
- I named the pipeline `aita_sdp` so it's distinct from the job `aita_pipeline`. Rename it if you'd like.
- I couldn't confirm the earlier save to your workspace folder. The sandbox was still starting when you cancelled, so `/Workspace/Users/david.huang@databricks.com/aita/pipeline_spec.md` may not exist yet. Copy `pipeline_spec.md` from my earlier message to be safe.
