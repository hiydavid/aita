USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

CREATE TEMPORARY VIEW compensation_changes
AS
SELECT
  upper(trim(compensation_id)) AS compensation_id,
  upper(trim(worker_id)) AS worker_id,
  CAST(compensation_year AS INT) AS compensation_year,
  CAST(effective_date AS DATE) AS effective_date,
  upper(trim(job_code)) AS job_code,
  upper(trim(org_unit_id)) AS org_unit_id,
  CAST(base_salary AS DECIMAL(18, 2)) AS base_salary,
  CAST(annual_bonus AS DECIMAL(18, 2)) AS annual_bonus,
  CAST(band_min AS DECIMAL(18, 2)) AS band_min,
  CAST(band_mid AS DECIMAL(18, 2)) AS band_mid,
  CAST(band_max AS DECIMAL(18, 2)) AS band_max,
  upper(trim(currency)) AS currency,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`compensation`);

CREATE OR REFRESH STREAMING TABLE compensation (
  CONSTRAINT base_salary_within_band EXPECT (
    base_salary BETWEEN band_min AND band_max
  )
);

CREATE FLOW compensation_cdc AS AUTO CDC INTO compensation
FROM STREAM(compensation_changes)
KEYS (compensation_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;
