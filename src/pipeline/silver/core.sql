USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

CREATE TEMPORARY VIEW worker_changes
AS
SELECT
  upper(trim(worker_id)) AS worker_id,
  trim(first_name) AS first_name,
  trim(last_name) AS last_name,
  CAST(birth_date AS DATE) AS birth_date,
  trim(gender) AS gender,
  CAST(hire_date AS DATE) AS hire_date,
  CAST(termination_date AS DATE) AS termination_date,
  initcap(lower(trim(employment_status))) AS employment_status,
  upper(trim(job_code)) AS job_code,
  upper(trim(org_unit_id)) AS org_unit_id,
  upper(trim(manager_id)) AS manager_id,
  CASE lower(trim(business_line))
    WHEN 'consumer banking' THEN 'Consumer Banking'
    WHEN 'wealth management' THEN 'Wealth Management'
    WHEN 'commercial banking' THEN 'Commercial Banking'
    WHEN 'operations' THEN 'Operations'
    WHEN 'technology' THEN 'Technology'
    WHEN 'corporate functions' THEN 'Corporate Functions'
    ELSE trim(business_line)
  END AS business_line,
  initcap(lower(trim(location))) AS location,
  initcap(lower(trim(worker_type))) AS worker_type,
  lower(trim(email)) AS email,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`workers`);

CREATE OR REFRESH STREAMING TABLE workers (
  CONSTRAINT valid_business_line EXPECT (
    business_line IN (
      'Consumer Banking',
      'Wealth Management',
      'Commercial Banking',
      'Operations',
      'Technology',
      'Corporate Functions'
    )
  ) ON VIOLATION DROP ROW,
  CONSTRAINT hire_date_not_null EXPECT (hire_date IS NOT NULL) ON VIOLATION FAIL UPDATE
);

CREATE FLOW workers_cdc AS AUTO CDC INTO workers
FROM STREAM(worker_changes)
KEYS (worker_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE TEMPORARY VIEW worker_history_changes
AS
SELECT
  upper(trim(history.event_id)) AS event_id,
  upper(trim(history.worker_id)) AS worker_id,
  upper(trim(history.event_type)) AS event_type,
  CAST(history.event_date AS DATE) AS event_date,
  upper(trim(history.job_code)) AS job_code,
  upper(trim(history.previous_job_code)) AS previous_job_code,
  upper(trim(history.org_unit_id)) AS org_unit_id,
  upper(trim(history.previous_org_unit_id)) AS previous_org_unit_id,
  upper(trim(history.manager_id)) AS manager_id,
  upper(trim(history.previous_manager_id)) AS previous_manager_id,
  initcap(lower(trim(history.termination_type))) AS termination_type,
  trim(history.event_reason) AS event_reason,
  CAST(worker.hire_date AS DATE) AS hire_date,
  history._rescued_data,
  history._source_file,
  history._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`job_history`) AS history
INNER JOIN `${catalog}`.`${bronze_schema}`.`workers` AS worker
  ON upper(trim(history.worker_id)) = upper(trim(worker.worker_id));

CREATE OR REFRESH STREAMING TABLE worker_history (
  CONSTRAINT event_date_on_or_after_hire_date EXPECT (
    event_date >= hire_date
  )
);

CREATE FLOW worker_history_cdc AS AUTO CDC INTO worker_history
FROM STREAM(worker_history_changes)
KEYS (worker_id)
SEQUENCE BY STRUCT(event_date, event_id)
STORED AS SCD TYPE 2;

CREATE TEMPORARY VIEW org_unit_changes
AS
SELECT
  upper(trim(org_unit_id)) AS org_unit_id,
  trim(org_unit_name) AS org_unit_name,
  CASE lower(trim(business_line))
    WHEN 'consumer banking' THEN 'Consumer Banking'
    WHEN 'wealth management' THEN 'Wealth Management'
    WHEN 'commercial banking' THEN 'Commercial Banking'
    WHEN 'operations' THEN 'Operations'
    WHEN 'technology' THEN 'Technology'
    WHEN 'corporate functions' THEN 'Corporate Functions'
    ELSE trim(business_line)
  END AS business_line,
  trim(org_type) AS org_type,
  initcap(lower(trim(region))) AS region,
  initcap(lower(trim(location))) AS location,
  upper(trim(parent_org_unit_id)) AS parent_org_unit_id,
  upper(trim(manager_id)) AS manager_id,
  CAST(schedule_change_date AS DATE) AS schedule_change_date,
  CAST(standout_manager_flag AS BOOLEAN) AS standout_manager_flag,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`org_units`);

CREATE OR REFRESH STREAMING TABLE org_units;

CREATE FLOW org_units_cdc AS AUTO CDC INTO org_units
FROM STREAM(org_unit_changes)
KEYS (org_unit_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;
