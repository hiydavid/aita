USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

CREATE TEMPORARY VIEW requisition_changes
AS
SELECT
  upper(trim(requisition_id)) AS requisition_id,
  upper(trim(job_code)) AS job_code,
  upper(trim(org_unit_id)) AS org_unit_id,
  CASE lower(trim(business_line))
    WHEN 'consumer banking' THEN 'Consumer Banking'
    WHEN 'wealth management' THEN 'Wealth Management'
    WHEN 'commercial banking' THEN 'Commercial Banking'
    WHEN 'operations' THEN 'Operations'
    WHEN 'technology' THEN 'Technology'
    WHEN 'corporate functions' THEN 'Corporate Functions'
    ELSE trim(business_line)
  END AS business_line,
  CAST(open_date AS DATE) AS open_date,
  CAST(close_date AS DATE) AS close_date,
  initcap(lower(trim(status))) AS status,
  initcap(lower(trim(requisition_type))) AS requisition_type,
  CAST(licensed_role_flag AS BOOLEAN) AS licensed_role_flag,
  CAST(estimated_recruiting_cost AS DECIMAL(18, 2)) AS estimated_recruiting_cost,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`requisitions`);

CREATE OR REFRESH STREAMING TABLE requisitions (
  CONSTRAINT close_date_on_or_after_open_date EXPECT (
    close_date IS NULL OR close_date >= open_date
  )
);

CREATE FLOW requisitions_cdc AS AUTO CDC INTO requisitions
FROM STREAM(requisition_changes)
KEYS (requisition_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE TEMPORARY VIEW application_event_changes
AS
SELECT
  upper(trim(application_event_id)) AS application_event_id,
  upper(trim(application_id)) AS application_id,
  upper(trim(requisition_id)) AS requisition_id,
  initcap(lower(trim(stage))) AS stage,
  CAST(event_date AS DATE) AS event_date,
  initcap(lower(trim(stage_status))) AS stage_status,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`application_events`);

CREATE OR REFRESH STREAMING TABLE application_events;

CREATE FLOW application_events_cdc AS AUTO CDC INTO application_events
FROM STREAM(application_event_changes)
KEYS (application_event_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;
