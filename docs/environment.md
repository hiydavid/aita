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

These are passed to the SDP pipeline as configuration parameters. Pipeline SQL must reference the parameters, never hardcoded catalog or schema names.

## Resources

| Resource | Name |
|---|---|
| SDP pipeline | `aita_sdp` |
| Lakeflow job | `aita_pipeline` (`generate_data` → `sdp_pipeline` → `sync_lakebase` → `evidence_report`) |

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

## Rules for Genie Code
* Work one layer at a time, following docs/pipeline_spec.md.
* Use the exact table and column names from the spec.
* Run against profile genie-workbench only.
* Write run outputs (row counts, expectation results, sample AI Function outputs) as small markdown files in evidence/.
* Use synthetic data only.


**Notes:**
- I named the pipeline `aita_sdp` so it's distinct from the job `aita_pipeline`. Rename it if you'd like.
- I couldn't confirm the earlier save to your workspace folder. The sandbox was still starting when you cancelled, so `/Workspace/Users/david.huang@databricks.com/aita/pipeline_spec.md` may not exist yet. Copy `pipeline_spec.md` from my earlier message to be safe.
