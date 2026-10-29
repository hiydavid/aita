#!/usr/bin/env bash
set -euo pipefail

# One-time setup for the dev environment. Run after talent_watchlist exists from
# an initial aita_sdp update, but before the first aita_pipeline job run.
# The source is a materialized view, so the synced table uses SNAPSHOT mode;
# incremental modes require change data feed from a source table.

PROFILE="genie-workbench"
PROJECT_ID="aita-lakebase"
PROJECT="projects/${PROJECT_ID}"
BRANCH="${PROJECT}/branches/production"
DATABASE_ID="databricks-postgres"
DATABASE_NAME="databricks_postgres"
DATABASE="${BRANCH}/databases/${DATABASE_ID}"
SOURCE_TABLE="genie_workbench_dev_catalog.aita_gold.talent_watchlist"
SYNCED_TABLE="genie_workbench_dev_catalog.aita_gold.talent_watchlist_serving"
CURRENT_SYNC_PIPELINE_ID="460f8caf-0187-4590-8ae3-38c306cff78c"

# Project creation also provisions the production branch, primary endpoint,
# and databricks_postgres database. Their matching creation timestamps on the
# live project confirm that they were created together.
databricks postgres create-project "${PROJECT_ID}" \
  --json '{
    "spec": {
      "display_name": "aita_lakebase",
      "pg_version": 17,
      "history_retention_duration": "604800s",
      "enable_pg_native_login": false,
      "default_endpoint_settings": {
        "autoscaling_limit_min_cu": 1,
        "autoscaling_limit_max_cu": 1,
        "suspend_timeout_duration": "86400s"
      }
    }
  }' \
  --profile "${PROFILE}"

databricks postgres get-branch "${BRANCH}" --profile "${PROFILE}"
databricks postgres get-database "${DATABASE}" --profile "${PROFILE}"

databricks postgres create-synced-table "${SYNCED_TABLE}" \
  --json "$(cat <<JSON
{
  "spec": {
    "source_table_full_name": "${SOURCE_TABLE}",
    "primary_key_columns": ["employee_id"],
    "scheduling_policy": "SNAPSHOT",
    "branch": "${BRANCH}",
    "postgres_database": "${DATABASE_NAME}",
    "create_database_objects_if_missing": true
  }
}
JSON
)" \
  --profile "${PROFILE}"

sync_pipeline_id="$(
  databricks postgres get-synced-table "synced_tables/${SYNCED_TABLE}" \
    --output json \
    --profile "${PROFILE}" |
    jq -r '.status.pipeline_id'
)"

printf 'Created sync pipeline: %s\n' "${sync_pipeline_id}"
if [[ "${sync_pipeline_id}" != "${CURRENT_SYNC_PIPELINE_ID}" ]]; then
  printf 'Set lakebase_sync_pipeline_id in databricks.yml to %s before deploying aita_pipeline.\n' \
    "${sync_pipeline_id}"
fi

# The app owns its writable objects and initializes them at startup. The thread,
# history, and watchlist stores create the aita_app schema plus threads,
# messages, turn_metadata, and watchlist_review_events; do not provision them here.
