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

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW candidate_summary_ai_signals
AS
SELECT
  candidate_ai_source.candidate_summary,
  skills_result:response:candidate_skills::ARRAY<STRING> AS candidate_skills,
  skills_result:error_message::STRING AS candidate_skills_error
FROM (
  SELECT
    candidate_text.candidate_summary,
    ai_extract(
      candidate_text.candidate_summary,
      '{"candidate_skills":{"type":"array","items":{"type":"string"}}}',
      map(
        'version', '2.0',
        'instructions', 'Extract only skills, capabilities, domain knowledge, credentials, or training explicitly supported by the candidate summary. Return concise normalized skill phrases.'
      )
    ) AS skills_result
  FROM (
    SELECT trim(candidate_summary) AS candidate_summary
    FROM `${catalog}`.`${bronze_schema}`.`applications`
    WHERE candidate_summary IS NOT NULL
      AND trim(candidate_summary) <> ''
    GROUP BY trim(candidate_summary)
  ) AS candidate_text
) AS candidate_ai_source;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW offer_decline_ai_signals
AS
SELECT
  decline_ai_source.offer_decline_comment,
  decline_result:response[0]::STRING AS decline_reason,
  decline_result:error_message::STRING AS decline_reason_error
FROM (
  SELECT
    decline_text.offer_decline_comment,
    ai_classify(
      decline_text.offer_decline_comment,
      '{"compensation":"Base pay, bonus, benefits, equity, or total compensation concerns without a more explicit competing-offer decision","competing offer":"An explicitly competing offer or another employer selected for stronger pay, client book, speed, or other offer terms","location":"Commute, relocation, remote-work, or geographic concerns","process too slow":"Delays, excessive interview steps, or slow recruiting decisions","role fit":"Another role is described as a closer fit for current goals, responsibilities, level, career direction, or timing","other":"A decline reason that does not clearly match the other labels"}',
      map(
        'version', '2.0',
        'instructions', 'Choose the single most explicit primary reason. A closer fit for current goals is role fit. Use competing offer when the comment explicitly emphasizes a competing offer or its terms.'
      )
    ) AS decline_result
  FROM (
    SELECT trim(offer_decline_comment) AS offer_decline_comment
    FROM `${catalog}`.`${bronze_schema}`.`applications`
    WHERE offer_decline_comment IS NOT NULL
      AND trim(offer_decline_comment) <> ''
    GROUP BY trim(offer_decline_comment)
  ) AS decline_text
) AS decline_ai_source;

CREATE OR REFRESH STREAMING TABLE applications_enriched (
  CONSTRAINT requisition_exists EXPECT (requisition_exists)
)
AS
SELECT
  upper(trim(application.application_id)) AS application_id,
  upper(trim(application.candidate_id)) AS candidate_id,
  upper(trim(application.requisition_id)) AS requisition_id,
  CAST(application.application_date AS DATE) AS application_date,
  initcap(lower(trim(application.source))) AS source,
  nullif(upper(trim(application.internal_worker_id)), '') AS internal_worker_id,
  initcap(lower(trim(application.current_stage))) AS current_stage,
  initcap(lower(trim(application.offer_outcome))) AS offer_outcome,
  trim(application.candidate_summary) AS candidate_summary,
  trim(application.offer_decline_comment) AS offer_decline_comment,
  requisition.requisition_id IS NOT NULL AS requisition_exists,
  candidate_signals.candidate_skills,
  candidate_signals.candidate_skills_error,
  decline_signals.decline_reason,
  decline_signals.decline_reason_error,
  application._rescued_data,
  application._source_file,
  application._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`applications`) AS application
LEFT JOIN requisitions AS requisition
  ON upper(trim(application.requisition_id)) = requisition.requisition_id
LEFT JOIN candidate_summary_ai_signals AS candidate_signals
  ON trim(application.candidate_summary) = candidate_signals.candidate_summary
LEFT JOIN offer_decline_ai_signals AS decline_signals
  ON trim(application.offer_decline_comment) = decline_signals.offer_decline_comment;

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
