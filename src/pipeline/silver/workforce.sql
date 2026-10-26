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

CREATE OR REFRESH STREAMING TABLE team_productivity
COMMENT 'Typed monthly productivity, customer service, overtime, and quality measures at team grain.';

CREATE FLOW team_productivity_cdc AS AUTO CDC INTO team_productivity
FROM STREAM(team_productivity_changes)
KEYS (team_id, month)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW exit_comment_ai_signals
COMMENT 'Pipeline-private AI exit reasons and sentiment at one row per distinct normalized exit comment.'
AS
SELECT
  exit_ai_source.exit_comment,
  reason_result:response[0]::STRING AS exit_reason,
  reason_result:error_message::STRING AS exit_reason_error,
  ai_analyze_sentiment(exit_ai_source.exit_comment) AS exit_sentiment
FROM (
  SELECT
    exit_text.exit_comment,
    ai_classify(
      exit_text.exit_comment,
      '{"compensation":"Pay, salary, bonus, benefits, or compensation competitiveness","manager":"Manager coaching, support, leadership, priorities, communication, or flexibility","schedule and workload":"Shifts, schedules, hours, staffing, workload, capacity, or recovery time","career growth":"Promotion, advancement, development, broader responsibilities, or career path","relocation":"Moving or leaving the bank geographic operating area","other":"Personal priorities, retirement, another opportunity without a clearly stated listed reason, or any reason that does not fit the other labels"}',
      map(
        'version', '2.0',
        'instructions', 'Choose the single most explicit primary reason. Use other when the comment mentions only personal priorities or a different opportunity without explicitly naming compensation, management, schedule or workload, career growth, or relocation.'
      )
    ) AS reason_result
  FROM (
    SELECT trim(exit_comment) AS exit_comment
    FROM `${catalog}`.`${bronze_schema}`.`exit_interviews`
    WHERE exit_comment IS NOT NULL
      AND trim(exit_comment) <> ''
    GROUP BY trim(exit_comment)
  ) AS exit_text
) AS exit_ai_source;

CREATE OR REFRESH STREAMING TABLE exit_interviews_enriched (
  CONSTRAINT exit_comment_not_empty EXPECT (
    exit_comment IS NOT NULL AND trim(exit_comment) <> ''
  )
)
COMMENT 'Typed exit interviews enriched with AI-classified exit reason and AI-analyzed sentiment.'
AS
SELECT
  upper(trim(exit_interview.exit_interview_id)) AS exit_interview_id,
  upper(trim(exit_interview.worker_id)) AS worker_id,
  upper(trim(exit_interview.org_unit_id)) AS org_unit_id,
  upper(trim(exit_interview.manager_id)) AS manager_id,
  CAST(exit_interview.exit_date AS DATE) AS exit_date,
  CAST(exit_interview.interview_date AS DATE) AS interview_date,
  trim(exit_interview.stated_reason) AS stated_reason,
  trim(exit_interview.exit_comment) AS exit_comment,
  CAST(exit_interview.would_rehire AS BOOLEAN) AS would_rehire,
  signals.exit_reason,
  signals.exit_reason_error,
  signals.exit_sentiment,
  exit_interview._rescued_data,
  exit_interview._source_file,
  exit_interview._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`exit_interviews`) AS exit_interview
LEFT JOIN exit_comment_ai_signals AS signals
  ON trim(exit_interview.exit_comment) = signals.exit_comment;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW engagement_comment_ai_signals
COMMENT 'Pipeline-private AI sentiment and theme at one row per distinct normalized engagement comment.'
AS
SELECT
  engagement_ai_source.comment,
  ai_analyze_sentiment(engagement_ai_source.comment) AS comment_sentiment,
  theme_result:response[0]::STRING AS comment_theme,
  theme_result:error_message::STRING AS comment_theme_error
FROM (
  SELECT
    engagement_text.comment,
    ai_classify(
      engagement_text.comment,
      '{"burnout":"An explicit statement of burnout, emotional exhaustion, or chronic stress","workload":"Work volume, staffing, hours, schedules, priorities, capacity pressure, or insufficient recovery time between shifts without explicit burnout","manager":"Manager coaching, support, leadership, communication, flexibility, or obstacle removal","recognition":"Appreciation, rewards, visibility, praise, or lack of recognition","positive":"Overall support, pride, purpose, satisfaction, or healthy team morale without a stronger issue theme","other":"Feedback that does not clearly fit the other themes"}',
      map(
        'version', '2.0',
        'instructions', 'Choose the single most explicit primary theme. Use burnout only when burnout, emotional exhaustion, or chronic stress is directly stated. A difficult schedule or too little recovery time between shifts is workload unless burnout or exhaustion is explicit.'
      )
    ) AS theme_result
  FROM (
    SELECT trim(comment) AS comment
    FROM `${catalog}`.`${bronze_schema}`.`engagement_surveys`
    WHERE comment IS NOT NULL
      AND trim(comment) <> ''
    GROUP BY trim(comment)
  ) AS engagement_text
) AS engagement_ai_source;

CREATE OR REFRESH STREAMING TABLE engagement_enriched (
  CONSTRAINT engagement_score_between_1_and_5 EXPECT (
    engagement_score BETWEEN 1 AND 5
  ) ON VIOLATION DROP ROW
)
COMMENT 'Typed employee engagement responses enriched with AI-analyzed sentiment and AI-classified comment theme.'
AS
SELECT
  upper(trim(engagement.survey_response_id)) AS survey_response_id,
  upper(trim(engagement.worker_id)) AS worker_id,
  upper(trim(engagement.org_unit_id)) AS org_unit_id,
  upper(trim(engagement.manager_id)) AS manager_id,
  CAST(engagement.survey_date AS DATE) AS survey_date,
  trim(engagement.survey_wave) AS survey_wave,
  CAST(engagement.engagement_score AS DECIMAL(3, 2)) AS engagement_score,
  CAST(engagement.manager_score AS DECIMAL(3, 2)) AS manager_score,
  CAST(engagement.workload_score AS DECIMAL(3, 2)) AS workload_score,
  trim(engagement.comment) AS comment,
  signals.comment_sentiment,
  signals.comment_theme,
  signals.comment_theme_error,
  engagement._rescued_data,
  engagement._source_file,
  engagement._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`engagement_surveys`) AS engagement
LEFT JOIN engagement_comment_ai_signals AS signals
  ON trim(engagement.comment) = signals.comment;
