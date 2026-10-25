USE CATALOG `${catalog}`;
USE SCHEMA `${bronze_schema}`;

CREATE OR REFRESH STREAMING TABLE workers
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/workers',
  format => 'csv',
  header => true,
  schemaHints => 'worker_id STRING, hire_date DATE, termination_date DATE, job_code STRING, org_unit_id STRING, manager_id STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE job_history
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/job_history',
  format => 'csv',
  header => true,
  schemaHints => 'event_id STRING, worker_id STRING, event_date DATE, job_code STRING, org_unit_id STRING, manager_id STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE org_units
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/org_units',
  format => 'csv',
  header => true,
  schemaHints => 'org_unit_id STRING, parent_org_unit_id STRING, manager_id STRING, schedule_change_date DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE jobs
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/jobs',
  format => 'json',
  schemaHints => 'job_code STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE engagement_surveys
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/engagement_surveys',
  format => 'json',
  schemaHints => 'survey_response_id STRING, worker_id STRING, org_unit_id STRING, manager_id STRING, survey_date DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE exit_interviews
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/exit_interviews',
  format => 'json',
  schemaHints => 'exit_interview_id STRING, worker_id STRING, org_unit_id STRING, manager_id STRING, exit_date DATE, interview_date DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE team_productivity
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/team_productivity',
  format => 'csv',
  header => true,
  schemaHints => 'team_id STRING, month DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE performance_reviews
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/performance_reviews',
  format => 'json',
  schemaHints => 'review_id STRING, worker_id STRING, review_year INT, review_date DATE, job_code STRING, org_unit_id STRING, manager_id STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE compensation
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/compensation',
  format => 'csv',
  header => true,
  schemaHints => 'compensation_id STRING, worker_id STRING, compensation_year INT, effective_date DATE, job_code STRING, org_unit_id STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE requisitions
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/requisitions',
  format => 'csv',
  header => true,
  schemaHints => 'requisition_id STRING, job_code STRING, org_unit_id STRING, open_date DATE, close_date DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE applications
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/applications',
  format => 'json',
  schemaHints => 'application_id STRING, candidate_id STRING, requisition_id STRING, application_date DATE, internal_worker_id STRING',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);

CREATE OR REFRESH STREAMING TABLE application_events
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/application_events',
  format => 'csv',
  header => true,
  schemaHints => 'application_event_id STRING, application_id STRING, requisition_id STRING, event_date DATE',
  schemaEvolutionMode => 'rescue',
  rescuedDataColumn => '_rescued_data'
);
