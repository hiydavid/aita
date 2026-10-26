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
)
COMMENT 'Typed annual employee compensation and pay-band records at compensation-record grain.';

CREATE FLOW compensation_cdc AS AUTO CDC INTO compensation
FROM STREAM(compensation_changes)
KEYS (compensation_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW performance_comment_ai_signals
COMMENT 'Pipeline-private AI-extracted demonstrated skills at one row per distinct normalized manager comment.'
AS
SELECT
  performance_ai_source.manager_comment,
  skills_result:response:demonstrated_skills::ARRAY<STRING> AS demonstrated_skills,
  skills_result:error_message::STRING AS demonstrated_skills_error
FROM (
  SELECT
    performance_text.manager_comment,
    ai_extract(
      performance_text.manager_comment,
      '{"demonstrated_skills":{"type":"array","items":{"type":"string"}}}',
      map(
        'version', '2.0',
        'instructions', 'Extract only concrete skills and capabilities the review explicitly says the worker demonstrated. Exclude general performance levels, adjectives, future development areas, and skills the comment says still need improvement. Return concise normalized skill phrases and do not infer unsupported skills.'
      )
    ) AS skills_result
  FROM (
    SELECT trim(manager_comment) AS manager_comment
    FROM `${catalog}`.`${bronze_schema}`.`performance_reviews`
    WHERE manager_comment IS NOT NULL
      AND trim(manager_comment) <> ''
    GROUP BY trim(manager_comment)
  ) AS performance_text
) AS performance_ai_source;

CREATE OR REFRESH STREAMING TABLE performance_enriched (
  CONSTRAINT performance_rating_allowed EXPECT (
    performance_rating IN (
      'Exceeds Expectations',
      'Meets Expectations',
      'Partially Meets',
      'Does Not Meet'
    )
  ) ON VIOLATION DROP ROW
)
COMMENT 'Typed annual employee performance reviews enriched with AI-extracted demonstrated skills.'
AS
SELECT
  upper(trim(performance.review_id)) AS review_id,
  upper(trim(performance.worker_id)) AS worker_id,
  CAST(performance.review_year AS INT) AS review_year,
  CAST(performance.review_date AS DATE) AS review_date,
  upper(trim(performance.job_code)) AS job_code,
  upper(trim(performance.org_unit_id)) AS org_unit_id,
  upper(trim(performance.manager_id)) AS manager_id,
  trim(performance.performance_rating) AS performance_rating,
  CAST(performance.rating_numeric AS INT) AS rating_numeric,
  trim(performance.potential_rating) AS potential_rating,
  trim(performance.manager_comment) AS manager_comment,
  signals.demonstrated_skills,
  signals.demonstrated_skills_error,
  performance._rescued_data,
  performance._source_file,
  performance._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`performance_reviews`) AS performance
LEFT JOIN performance_comment_ai_signals AS signals
  ON trim(performance.manager_comment) = signals.manager_comment;
