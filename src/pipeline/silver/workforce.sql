USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

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
