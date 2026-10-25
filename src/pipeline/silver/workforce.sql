USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

CREATE TEMPORARY VIEW team_productivity_changes
AS
SELECT
  upper(trim(team_id)) AS team_id,
  CAST(month AS DATE) AS month,
  CAST(cases_handled AS BIGINT) AS cases_handled,
  CAST(avg_handle_time_minutes AS DECIMAL(10, 2)) AS avg_handle_time_minutes,
  CAST(csat_score AS DECIMAL(4, 2)) AS csat_score,
  CAST(overtime_hours AS DECIMAL(12, 2)) AS overtime_hours,
  CAST(quality_score AS DECIMAL(5, 2)) AS quality_score,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`team_productivity`);

CREATE OR REFRESH STREAMING TABLE team_productivity;

CREATE FLOW team_productivity_cdc AS AUTO CDC INTO team_productivity
FROM STREAM(team_productivity_changes)
KEYS (team_id, month)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE OR REFRESH STREAMING TABLE exit_interviews_enriched (
  CONSTRAINT exit_comment_not_empty EXPECT (
    exit_comment IS NOT NULL AND trim(exit_comment) <> ''
  )
)
AS
SELECT
  *,
  ai_classify(
    exit_comment,
    '["compensation","manager","schedule and workload","career growth","relocation","other"]',
    map('version', '2.0')
  ):response[0]::STRING AS exit_reason,
  ai_analyze_sentiment(exit_comment) AS exit_sentiment
FROM STREAM(`${catalog}`.`${bronze_schema}`.`exit_interviews`)
LIMIT 200;
