USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_headcount_monthly`
CLUSTER BY (month_start, org_unit_id)
COMMENT 'Month-end headcount and in-month workforce movements at organization, job, and month grain.'
AS
WITH month_bounds AS (
  SELECT
    min(month) AS minimum_month,
    max(month) AS maximum_month
  FROM `${catalog}`.`${silver_schema}`.`team_productivity`
),
months AS (
  SELECT
    month_start,
    last_day(month_start) AS month_end
  FROM month_bounds
  LATERAL VIEW explode(
    sequence(minimum_month, maximum_month, INTERVAL 1 MONTH)
  ) generated_months AS month_start
),
worker_versions AS (
  SELECT
    worker_id,
    event_type,
    job_code,
    org_unit_id,
    `__START_AT`.event_date AS valid_from,
    coalesce(`__END_AT`.event_date, DATE '9999-12-31') AS valid_to
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE `__END_AT` IS NULL
    OR `__END_AT`.event_date > `__START_AT`.event_date
),
month_end_headcount AS (
  SELECT
    month.month_start,
    month.month_end,
    history.org_unit_id,
    history.job_code,
    count(DISTINCT history.worker_id) AS headcount_eom
  FROM months AS month
  INNER JOIN worker_versions AS history
    ON history.valid_from <= month.month_end
    AND month.month_end < history.valid_to
  WHERE history.event_type <> 'EXIT'
  GROUP BY
    month.month_start,
    month.month_end,
    history.org_unit_id,
    history.job_code
),
monthly_movements AS (
  SELECT
    trunc(history.event_date, 'MONTH') AS month_start,
    history.org_unit_id,
    history.job_code,
    count_if(history.event_type = 'HIRE') AS hire_count,
    count_if(history.event_type = 'EXIT') AS exit_count,
    count_if(
      history.event_type = 'EXIT'
      AND history.termination_type = 'Voluntary'
    ) AS voluntary_exit_count,
    count_if(history.event_type = 'TRANSFER') AS transfer_in_count,
    count_if(history.event_type = 'PROMOTION') AS promotion_count,
    count_if(history.event_type = 'MANAGER_CHANGE') AS manager_change_count
  FROM `${catalog}`.`${silver_schema}`.`worker_history` AS history
  CROSS JOIN month_bounds AS bounds
  WHERE history.event_date BETWEEN bounds.minimum_month AND last_day(bounds.maximum_month)
  GROUP BY
    trunc(history.event_date, 'MONTH'),
    history.org_unit_id,
    history.job_code
)
SELECT
  coalesce(headcount.month_start, movement.month_start) AS month_start,
  coalesce(headcount.month_end, last_day(movement.month_start)) AS month_end,
  coalesce(headcount.org_unit_id, movement.org_unit_id) AS org_unit_id,
  coalesce(headcount.job_code, movement.job_code) AS job_code,
  coalesce(headcount.headcount_eom, 0) AS headcount_eom,
  coalesce(movement.hire_count, 0) AS hire_count,
  coalesce(movement.exit_count, 0) AS exit_count,
  coalesce(movement.voluntary_exit_count, 0) AS voluntary_exit_count,
  coalesce(movement.transfer_in_count, 0) AS transfer_in_count,
  coalesce(movement.promotion_count, 0) AS promotion_count,
  coalesce(movement.manager_change_count, 0) AS manager_change_count
FROM month_end_headcount AS headcount
FULL OUTER JOIN monthly_movements AS movement
  ON headcount.month_start = movement.month_start
  AND headcount.org_unit_id = movement.org_unit_id
  AND headcount.job_code = movement.job_code;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_attrition_event`
CLUSTER BY (exit_date, org_unit_id)
COMMENT 'Employee attrition events with departure context and AI-enriched exit-interview signals.'
AS
SELECT
  history.event_id AS attrition_event_id,
  history.worker_id AS employee_id,
  history.event_date AS exit_date,
  trunc(history.event_date, 'MONTH') AS exit_month,
  history.org_unit_id,
  history.job_code,
  history.manager_id,
  history.termination_type,
  history.termination_type = 'Voluntary' AS is_voluntary,
  history.event_reason,
  datediff(history.event_date, history.hire_date) AS tenure_days,
  CAST(
    round(datediff(history.event_date, history.hire_date) / 365.25, 2)
    AS DECIMAL(8, 2)
  ) AS tenure_years,
  job.licensed_role_flag,
  job.strategic_role_flag,
  interview.exit_interview_id,
  interview.interview_date,
  interview.exit_reason,
  interview.exit_sentiment,
  interview.would_rehire,
  history.termination_type = 'Voluntary'
    AND coalesce(interview.would_rehire, false) AS regrettable_flag
FROM `${catalog}`.`${silver_schema}`.`worker_history` AS history
INNER JOIN `${catalog}`.`${silver_schema}`.`jobs_enriched` AS job
  ON history.job_code = job.job_code
LEFT JOIN `${catalog}`.`${silver_schema}`.`exit_interviews_enriched` AS interview
  ON history.worker_id = interview.worker_id
WHERE history.event_type = 'EXIT';

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_engagement`
CLUSTER BY (survey_date, org_unit_id)
COMMENT 'Employee survey responses with effective job assignment and AI-derived sentiment and theme.'
AS
WITH worker_versions AS (
  SELECT
    worker_id,
    job_code,
    `__START_AT`.event_date AS valid_from,
    coalesce(`__END_AT`.event_date, DATE '9999-12-31') AS valid_to
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE `__END_AT` IS NULL
    OR `__END_AT`.event_date > `__START_AT`.event_date
)
SELECT
  engagement.survey_response_id,
  engagement.worker_id AS employee_id,
  engagement.survey_wave,
  engagement.survey_date,
  dense_rank() OVER (ORDER BY engagement.survey_date) AS wave_sequence,
  engagement.org_unit_id,
  history.job_code,
  engagement.manager_id,
  engagement.engagement_score,
  engagement.manager_score,
  engagement.workload_score,
  engagement.comment_sentiment,
  engagement.comment_theme,
  engagement.comment_theme = 'burnout' AS burnout_flag
FROM `${catalog}`.`${silver_schema}`.`engagement_enriched` AS engagement
LEFT JOIN worker_versions AS history
  ON engagement.worker_id = history.worker_id
  AND engagement.survey_date >= history.valid_from
  AND engagement.survey_date < history.valid_to;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_productivity`
CLUSTER BY (month_start, team_id)
COMMENT 'Monthly team productivity, service, overtime, and quality measures.'
AS
SELECT
  team_id,
  month AS month_start,
  cases_handled,
  avg_handle_time_minutes,
  csat_score,
  overtime_hours,
  quality_score
FROM `${catalog}`.`${silver_schema}`.`team_productivity`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_performance`
CLUSTER BY (review_year, org_unit_id)
COMMENT 'Annual employee performance outcomes with AI-extracted demonstrated skills.'
AS
SELECT
  review_id,
  worker_id AS employee_id,
  review_year,
  review_date,
  job_code,
  org_unit_id,
  manager_id,
  performance_rating,
  rating_numeric,
  potential_rating,
  rating_numeric = 5 AS top_rating_flag,
  potential_rating = 'High' AS high_potential_flag,
  demonstrated_skills
FROM `${catalog}`.`${silver_schema}`.`performance_enriched`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_compensation`
CLUSTER BY (compensation_year, org_unit_id)
COMMENT 'Masked annual employee pay-position measures without recoverable salary or pay-band amounts.'
AS
SELECT
  compensation_id,
  worker_id AS employee_id,
  compensation_year,
  effective_date,
  job_code,
  org_unit_id,
  CAST(round(base_salary / band_mid, 4) AS DECIMAL(8, 4)) AS compa_ratio,
  CAST(
    round(
      (base_salary - band_min) / nullif(band_max - band_min, 0),
      4
    ) AS DECIMAL(8, 4)
  ) AS range_penetration,
  CASE
    WHEN base_salary / band_mid < 0.90 THEN 'Below 0.90'
    WHEN base_salary / band_mid <= 1.10 THEN '0.90 to 1.10'
    ELSE 'Above 1.10'
  END AS pay_position_band,
  base_salary < band_mid AS below_band_midpoint_flag,
  CAST(round(annual_bonus / nullif(base_salary, 0), 4) AS DECIMAL(8, 4)) AS bonus_pct_of_base
FROM `${catalog}`.`${silver_schema}`.`compensation`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_requisition`
CLUSTER BY (open_date, job_code)
COMMENT 'Recruiting requisitions with fill-cycle, applicant-volume, backfill, license, and cost measures.'
AS
WITH hire_events AS (
  SELECT
    requisition_id,
    min(event_date) AS hire_date
  FROM `${catalog}`.`${silver_schema}`.`application_events`
  WHERE stage = 'Hired'
  GROUP BY requisition_id
),
application_summary AS (
  SELECT
    requisition_id,
    count(*) AS application_count,
    count_if(internal_worker_id IS NOT NULL) AS internal_application_count,
    count_if(current_stage = 'Offer') AS pending_offer_count,
    count_if(current_stage = 'Declined') AS declined_offer_count,
    count_if(current_stage = 'Hired') AS hired_application_count
  FROM `${catalog}`.`${silver_schema}`.`applications_enriched`
  GROUP BY requisition_id
)
SELECT
  requisition.requisition_id,
  requisition.job_code,
  requisition.org_unit_id,
  requisition.business_line,
  requisition.open_date,
  requisition.close_date,
  hire.hire_date,
  requisition.status,
  requisition.requisition_type,
  requisition.requisition_type = 'Backfill' AS backfill_flag,
  requisition.licensed_role_flag,
  requisition.status = 'Filled' AS filled_flag,
  CASE
    WHEN requisition.status = 'Filled'
      THEN datediff(requisition.close_date, requisition.open_date)
  END AS time_to_fill_days,
  datediff(hire.hire_date, requisition.open_date) AS days_open_to_hire,
  applications.application_count,
  applications.internal_application_count,
  applications.pending_offer_count,
  applications.declined_offer_count,
  applications.hired_application_count,
  requisition.estimated_recruiting_cost
FROM `${catalog}`.`${silver_schema}`.`requisitions` AS requisition
LEFT JOIN hire_events AS hire
  ON requisition.requisition_id = hire.requisition_id
LEFT JOIN application_summary AS applications
  ON requisition.requisition_id = applications.requisition_id;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_application_funnel`
CLUSTER BY (application_date, requisition_id)
COMMENT 'Application lifecycle snapshot with stage milestones, elapsed times, internal status, and AI-derived decline reason.'
AS
WITH stage_events AS (
  SELECT
    application_id,
    max(CASE WHEN stage = 'Applied' THEN event_date END) AS applied_event_date,
    max(CASE WHEN stage = 'Screen' THEN event_date END) AS screen_date,
    max(CASE WHEN stage = 'Interview' THEN event_date END) AS interview_date,
    max(CASE WHEN stage = 'Offer' THEN event_date END) AS offer_date,
    max(
      CASE WHEN stage IN ('Hired', 'Declined', 'Rejected') THEN event_date END
    ) AS outcome_date,
    max(
      CASE WHEN stage IN ('Hired', 'Declined', 'Rejected') THEN stage END
    ) AS outcome_stage
  FROM `${catalog}`.`${silver_schema}`.`application_events`
  GROUP BY application_id
)
SELECT
  application.application_id,
  application.candidate_id,
  application.requisition_id,
  application.application_date,
  application.source,
  application.internal_worker_id IS NOT NULL AS internal_candidate_flag,
  application.internal_worker_id AS internal_employee_id,
  application.current_stage,
  application.offer_outcome,
  stage.applied_event_date,
  stage.screen_date,
  stage.interview_date,
  stage.offer_date,
  stage.outcome_date,
  stage.outcome_stage,
  stage.screen_date IS NOT NULL AS reached_screen_flag,
  stage.interview_date IS NOT NULL AS reached_interview_flag,
  stage.offer_date IS NOT NULL AS reached_offer_flag,
  stage.outcome_stage = 'Hired' AS hired_flag,
  stage.outcome_stage = 'Declined' AS declined_offer_flag,
  stage.outcome_stage = 'Rejected' AS rejected_flag,
  datediff(stage.applied_event_date, application.application_date) AS days_application_to_applied,
  datediff(stage.screen_date, stage.applied_event_date) AS days_applied_to_screen,
  datediff(stage.interview_date, stage.screen_date) AS days_screen_to_interview,
  datediff(stage.offer_date, stage.interview_date) AS days_interview_to_offer,
  datediff(
    stage.outcome_date,
    coalesce(
      stage.offer_date,
      stage.interview_date,
      stage.screen_date,
      stage.applied_event_date
    )
  ) AS days_last_stage_to_outcome,
  datediff(
    coalesce(
      stage.outcome_date,
      stage.offer_date,
      stage.interview_date,
      stage.screen_date,
      stage.applied_event_date
    ),
    stage.applied_event_date
  ) AS days_in_funnel,
  application.decline_reason,
  application.candidate_skills
FROM `${catalog}`.`${silver_schema}`.`applications_enriched` AS application
INNER JOIN stage_events AS stage
  ON application.application_id = stage.application_id;
