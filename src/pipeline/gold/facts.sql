USE CATALOG `${catalog}`;

CREATE TEMPORARY VIEW worker_versions
AS
SELECT
  worker_id,
  event_type,
  job_code,
  org_unit_id,
  `__START_AT`.event_date AS valid_from,
  coalesce(`__END_AT`.event_date, DATE '9999-12-31') AS valid_to
FROM `${catalog}`.`${silver_schema}`.`worker_history`
WHERE `__END_AT` IS NULL
  OR `__END_AT`.event_date > `__START_AT`.event_date;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_headcount_monthly` (
  month_start DATE COMMENT 'First date of the reporting month.',
  month_end DATE COMMENT 'Last date of the reporting month used for end-of-month headcount.',
  org_unit_id STRING COMMENT 'Organization-unit identifier joining to dim_org.',
  job_code STRING COMMENT 'Job-code identifier joining to dim_job.',
  headcount_eom BIGINT COMMENT 'Distinct active employees at month end, measured in employees.',
  hire_count BIGINT COMMENT 'Hire events effective during the month, measured in events.',
  exit_count BIGINT COMMENT 'Voluntary and involuntary exit events during the month, measured in events.',
  voluntary_exit_count BIGINT COMMENT 'Exit events with termination_type equal to Voluntary during the month.',
  transfer_in_count BIGINT COMMENT 'Transfer events effective during the month, measured in events.',
  promotion_count BIGINT COMMENT 'Promotion events effective during the month, measured in events.',
  manager_change_count BIGINT COMMENT 'Manager-change events effective during the month, measured in events.'
)
CLUSTER BY (month_start, org_unit_id)
COMMENT 'One row per organization unit, job code, and month with end-of-month headcount and in-month workforce movements. Used for workforce trend analysis.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_attrition_event` (
  attrition_event_id STRING COMMENT 'Stable identifier for the worker-history exit event.',
  employee_id STRING COMMENT 'Departing employee identifier joining to dim_worker.',
  exit_date DATE COMMENT 'Effective date of the employment exit.',
  exit_month DATE COMMENT 'First date of the calendar month containing the exit.',
  org_unit_id STRING COMMENT 'Organization unit at exit, joining to dim_org.',
  job_code STRING COMMENT 'Job code at exit, joining to dim_job.',
  manager_id STRING COMMENT 'Manager employee identifier at exit.',
  termination_type STRING COMMENT 'Exit classification. Values: Voluntary, Involuntary.',
  is_voluntary BOOLEAN COMMENT 'True when termination_type is Voluntary; false otherwise.',
  event_reason STRING COMMENT 'Source worker-history explanation for the exit event.',
  tenure_days INT COMMENT 'Elapsed calendar days from hire_date through exit_date.',
  tenure_years DECIMAL(8, 2) COMMENT 'Elapsed tenure in years, calculated as tenure_days divided by 365.25.',
  licensed_role_flag BOOLEAN COMMENT 'True when the job held at exit requires a professional license; false otherwise.',
  strategic_role_flag BOOLEAN COMMENT 'True when the job held at exit is strategically designated; false otherwise.',
  exit_interview_id STRING COMMENT 'Exit-interview identifier; null when no interview matched.',
  interview_date DATE COMMENT 'Date the exit interview occurred.',
  exit_reason STRING COMMENT 'AI-classified from exit_comment using ai_classify. Values: compensation, manager, schedule and workload, career growth, relocation, other.',
  exit_sentiment STRING COMMENT 'AI-analyzed sentiment from exit_comment using ai_analyze_sentiment. Values: positive, neutral, negative.',
  would_rehire BOOLEAN COMMENT 'Exit-interview response indicating whether the employee is eligible for rehire.',
  regrettable_flag BOOLEAN COMMENT 'True when the exiting employee had rating_numeric 4 or 5 in the latest performance review; false when the latest rating was lower or absent.'
)
CLUSTER BY (exit_date, org_unit_id)
COMMENT 'One row per voluntary or involuntary exit with departure context, AI-classified exit signals, and a latest-review regrettable flag. Used for attrition analysis.'
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
  coalesce(talent.rating_numeric >= 4, false) AS regrettable_flag
FROM `${catalog}`.`${silver_schema}`.`worker_history` AS history
INNER JOIN `${catalog}`.`${silver_schema}`.`jobs_enriched` AS job
  ON history.job_code = job.job_code
LEFT JOIN `${catalog}`.`${silver_schema}`.`exit_interviews_enriched` AS interview
  ON history.worker_id = interview.worker_id
LEFT JOIN latest_talent AS talent
  ON history.worker_id = talent.employee_id
WHERE history.event_type = 'EXIT';

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_engagement` (
  survey_response_id STRING COMMENT 'Stable identifier for the employee survey response.',
  employee_id STRING COMMENT 'Surveyed employee identifier joining to dim_worker.',
  survey_wave STRING COMMENT 'Source survey-wave label.',
  survey_date DATE COMMENT 'Date the survey response was recorded.',
  wave_sequence INT COMMENT 'Chronological survey-wave sequence beginning at 1.',
  org_unit_id STRING COMMENT 'Organization unit reported on the survey response.',
  job_code STRING COMMENT 'Employee job code effective on survey_date.',
  manager_id STRING COMMENT 'Manager employee identifier reported on the survey response.',
  engagement_score DECIMAL(3, 2) COMMENT 'Overall engagement score. Units: points; allowed range: 1 through 5.',
  manager_score DECIMAL(3, 2) COMMENT 'Manager-support score. Units: points; allowed range: 1 through 5.',
  workload_score DECIMAL(3, 2) COMMENT 'Workload-sustainability score. Units: points; allowed range: 1 through 5.',
  comment_sentiment STRING COMMENT 'AI-analyzed sentiment from comment using ai_analyze_sentiment. Values: positive, neutral, negative.',
  comment_theme STRING COMMENT 'AI-classified from comment using ai_classify. Values: burnout, workload, manager, recognition, positive, other.',
  burnout_flag BOOLEAN COMMENT 'True when comment_theme equals burnout; false otherwise.'
)
CLUSTER BY (survey_date, org_unit_id)
COMMENT 'One row per employee survey response and wave with effective job assignment and AI-derived sentiment and theme. Used for engagement and burnout analysis.'
AS
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_productivity` (
  team_id STRING COMMENT 'Team organization-unit identifier joining to dim_org.',
  month_start DATE COMMENT 'First date of the productivity reporting month.',
  cases_handled BIGINT COMMENT 'Total cases completed by the team during the month, measured in cases.',
  avg_handle_time_minutes DECIMAL(10, 2) COMMENT 'Average minutes spent handling a case during the month.',
  csat_score DECIMAL(4, 2) COMMENT 'Average customer-satisfaction score. Units: points; allowed range: 1 through 5.',
  overtime_hours DECIMAL(12, 2) COMMENT 'Total team overtime during the month, measured in hours.',
  quality_score DECIMAL(5, 2) COMMENT 'Team quality score. Units: percentage points; allowed range: 0 through 100.'
)
CLUSTER BY (month_start, team_id)
COMMENT 'One row per team and month with productivity, service, overtime, and quality measures. Used for operational workforce analysis.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_performance` (
  review_id STRING COMMENT 'Stable identifier for the annual performance review.',
  employee_id STRING COMMENT 'Reviewed employee identifier joining to dim_worker.',
  review_year INT COMMENT 'Four-digit performance-review year.',
  review_date DATE COMMENT 'Date the performance review was recorded.',
  job_code STRING COMMENT 'Employee job code recorded on the review.',
  org_unit_id STRING COMMENT 'Employee organization unit recorded on the review.',
  manager_id STRING COMMENT 'Reviewing manager employee identifier.',
  performance_rating STRING COMMENT 'Performance outcome. Values: Exceeds Expectations, Meets Expectations, Partially Meets, Does Not Meet.',
  rating_numeric INT COMMENT 'Numeric performance score. Values: 5 Exceeds Expectations, 4 Meets Expectations, 3 Partially Meets, 2 Does Not Meet.',
  potential_rating STRING COMMENT 'Assessed employee potential. Values: High, Medium, Developing.',
  top_rating_flag BOOLEAN COMMENT 'True when rating_numeric equals 5; false otherwise.',
  high_potential_flag BOOLEAN COMMENT 'True when potential_rating equals High; false otherwise.',
  demonstrated_skills ARRAY<STRING> COMMENT 'AI-extracted from manager_comment using ai_extract; each element is a concrete demonstrated skill.'
)
CLUSTER BY (review_year, org_unit_id)
COMMENT 'One row per employee and review year with performance, potential, and AI-extracted demonstrated skills. Used for talent analysis.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_compensation` (
  compensation_id STRING COMMENT 'Stable identifier for the annual employee compensation record.',
  employee_id STRING COMMENT 'Employee identifier joining to dim_worker.',
  compensation_year INT COMMENT 'Four-digit compensation plan year.',
  effective_date DATE COMMENT 'Date the annual compensation record takes effect.',
  job_code STRING COMMENT 'Employee job code recorded on the compensation record.',
  org_unit_id STRING COMMENT 'Employee organization unit recorded on the compensation record.',
  base_salary DECIMAL(18, 4) COMMENT 'Annual base salary in the currency column; visible only to aita_hr_admin members.' MASK `${catalog}`.`${gold_schema}`.`mask_compensation`,
  bonus DECIMAL(18, 4) COMMENT 'Annual bonus sourced from annual_bonus, in the currency column; visible only to aita_hr_admin members.' MASK `${catalog}`.`${gold_schema}`.`mask_compensation`,
  band_min DECIMAL(18, 2) COMMENT 'Published minimum annual salary for the job pay band, in the currency column; unmasked policy data.',
  band_mid DECIMAL(18, 2) COMMENT 'Published midpoint annual salary for the job pay band, in the currency column; unmasked policy data.',
  band_max DECIMAL(18, 2) COMMENT 'Published maximum annual salary for the job pay band, in the currency column; unmasked policy data.',
  currency STRING COMMENT 'ISO currency code applying to salary, bonus, and pay-band amounts. Value: USD.',
  pay_position_to_midpoint DECIMAL(18, 4) COMMENT 'Base salary divided by band midpoint; 1.0 equals midpoint and the value is visible only to aita_hr_admin members.' MASK `${catalog}`.`${gold_schema}`.`mask_compensation`,
  pay_position_band STRING COMMENT 'Non-sensitive pay-position category. Values: Below 0.90, 0.90 to 1.10, Above 1.10.',
  below_band_midpoint_flag BOOLEAN COMMENT 'True when base salary is below band midpoint; false otherwise.'
)
CLUSTER BY (compensation_year, org_unit_id)
COMMENT 'One row per employee and compensation year with masked personal pay, visible pay-band policy fields, and pay-position indicators. Used for governed compensation analysis.'
AS
SELECT
  compensation_id,
  worker_id AS employee_id,
  compensation_year,
  effective_date,
  job_code,
  org_unit_id,
  CAST(base_salary AS DECIMAL(18, 4)) AS base_salary,
  CAST(annual_bonus AS DECIMAL(18, 4)) AS bonus,
  band_min,
  band_mid,
  band_max,
  currency,
  CAST(round(base_salary / band_mid, 4) AS DECIMAL(18, 4))
    AS pay_position_to_midpoint,
  CASE
    WHEN base_salary / band_mid < 0.90 THEN 'Below 0.90'
    WHEN base_salary / band_mid <= 1.10 THEN '0.90 to 1.10'
    ELSE 'Above 1.10'
  END AS pay_position_band,
  base_salary < band_mid AS below_band_midpoint_flag
FROM `${catalog}`.`${silver_schema}`.`compensation`;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW latest_talent
COMMENT 'Pipeline-private latest performance and compensation records at one row per employee.'
AS
WITH latest_performance AS (
  SELECT *
  FROM `${catalog}`.`${gold_schema}`.`fact_performance`
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY review_date DESC, review_id DESC
  ) = 1
),
latest_compensation AS (
  SELECT *
  FROM `${catalog}`.`${gold_schema}`.`fact_compensation`
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY effective_date DESC, compensation_id DESC
  ) = 1
)
SELECT
  coalesce(performance.employee_id, compensation.employee_id) AS employee_id,
  performance.review_id,
  performance.review_date,
  performance.performance_rating,
  performance.rating_numeric,
  performance.potential_rating,
  performance.top_rating_flag,
  performance.high_potential_flag,
  performance.demonstrated_skills,
  compensation.compensation_id,
  compensation.effective_date AS compensation_effective_date,
  compensation.pay_position_to_midpoint,
  compensation.pay_position_band,
  compensation.below_band_midpoint_flag
FROM latest_performance AS performance
FULL OUTER JOIN latest_compensation AS compensation
  ON performance.employee_id = compensation.employee_id;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_requisition` (
  requisition_id STRING COMMENT 'Stable identifier for the job requisition.',
  job_code STRING COMMENT 'Requisition job code joining to dim_job.',
  org_unit_id STRING COMMENT 'Hiring organization unit joining to dim_org.',
  business_line STRING COMMENT 'Business line that owns the requisition.',
  open_date DATE COMMENT 'Date the requisition opened.',
  close_date DATE COMMENT 'Date the requisition closed; null while open.',
  hire_date DATE COMMENT 'Earliest Hired application-event date for the requisition; null when no hire occurred.',
  status STRING COMMENT 'Current requisition state. Values: Open, Filled, Cancelled.',
  requisition_type STRING COMMENT 'Hiring demand type. Values: Backfill, New Position.',
  backfill_flag BOOLEAN COMMENT 'True when requisition_type equals Backfill; false otherwise.',
  licensed_role_flag BOOLEAN COMMENT 'True when the requisition job requires a professional license; false otherwise.',
  filled_flag BOOLEAN COMMENT 'True when status equals Filled; false otherwise.',
  time_to_fill_days INT COMMENT 'Calendar days from open_date through close_date for filled requisitions; null otherwise.',
  days_open_to_hire INT COMMENT 'Calendar days from open_date through the earliest Hired event; null when no hire occurred.',
  application_count BIGINT COMMENT 'Applications submitted to the requisition, measured in applications.',
  internal_application_count BIGINT COMMENT 'Applications linked to an internal employee, measured in applications.',
  pending_offer_count BIGINT COMMENT 'Applications whose current stage is Offer, measured in applications.',
  declined_offer_count BIGINT COMMENT 'Applications whose current stage is Declined, measured in applications.',
  hired_application_count BIGINT COMMENT 'Applications whose current stage is Hired, measured in applications.',
  estimated_recruiting_cost DECIMAL(18, 2) COMMENT 'Estimated recruiting cost in US dollars.'
)
CLUSTER BY (open_date, job_code)
COMMENT 'One row per requisition with fill-cycle, applicant-volume, backfill, licensing, and cost measures. Used for recruiting analysis.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`fact_application_funnel` (
  application_id STRING COMMENT 'Stable identifier for the candidate application.',
  candidate_id STRING COMMENT 'Stable external or internal candidate identifier.',
  requisition_id STRING COMMENT 'Requisition identifier joining to fact_requisition.',
  application_date DATE COMMENT 'Date the application was submitted.',
  recruiting_source STRING COMMENT 'Recruiting source that produced the application.',
  internal_candidate_flag BOOLEAN COMMENT 'True when internal_employee_id is populated; false otherwise.',
  internal_employee_id STRING COMMENT 'Employee identifier for an internal candidate; null for external candidates.',
  internal_applicant_job_code STRING COMMENT 'Internal candidate job code effective on application_date; null for external candidates.',
  current_stage STRING COMMENT 'Latest application stage. Values include Applied, Screen, Interview, Offer, Hired, Rejected, Declined.',
  offer_outcome STRING COMMENT 'Offer result when an offer was made; null before an offer outcome.',
  applied_event_date DATE COMMENT 'Date of the Applied stage event.',
  screen_date DATE COMMENT 'Date of the Screen stage event; null when not reached.',
  interview_date DATE COMMENT 'Date of the Interview stage event; null when not reached.',
  offer_date DATE COMMENT 'Date of the Offer stage event; null when not reached.',
  outcome_date DATE COMMENT 'Date of the terminal Hired, Declined, or Rejected stage event; null while active.',
  outcome_stage STRING COMMENT 'Terminal application stage. Values: Hired, Declined, Rejected; null while active.',
  reached_screen_flag BOOLEAN COMMENT 'True when a Screen event exists; false otherwise.',
  reached_interview_flag BOOLEAN COMMENT 'True when an Interview event exists; false otherwise.',
  reached_offer_flag BOOLEAN COMMENT 'True when an Offer event exists; false otherwise.',
  hired_flag BOOLEAN COMMENT 'True when outcome_stage equals Hired; false otherwise.',
  declined_offer_flag BOOLEAN COMMENT 'True when outcome_stage equals Declined; false otherwise.',
  rejected_flag BOOLEAN COMMENT 'True when outcome_stage equals Rejected; false otherwise.',
  days_application_to_applied INT COMMENT 'Calendar days from application_date to the Applied event.',
  days_applied_to_screen INT COMMENT 'Calendar days from Applied to Screen; null when Screen was not reached.',
  days_screen_to_interview INT COMMENT 'Calendar days from Screen to Interview; null when either stage was not reached.',
  days_interview_to_offer INT COMMENT 'Calendar days from Interview to Offer; null when either stage was not reached.',
  days_last_stage_to_outcome INT COMMENT 'Calendar days from the latest preceding stage to the terminal outcome; null while active.',
  days_in_funnel INT COMMENT 'Calendar days from Applied through the latest reached stage or outcome.',
  decline_reason STRING COMMENT 'AI-classified from offer_decline_comment using ai_classify. Values: compensation, competing offer, location, process too slow, role fit, other.',
  candidate_skills ARRAY<STRING> COMMENT 'AI-extracted from candidate_summary using ai_extract; each element is a concise candidate skill.'
)
CLUSTER BY (application_date, requisition_id)
COMMENT 'One row per application with stage milestones, elapsed times, internal-candidate status, and AI-derived skills and decline reason. Used for funnel analysis.'
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
    ) AS outcome_stage,
    coalesce(offer_date, interview_date, screen_date, applied_event_date)
      AS latest_reached_date
  FROM `${catalog}`.`${silver_schema}`.`application_events`
  GROUP BY application_id
)
SELECT
  application.application_id,
  application.candidate_id,
  application.requisition_id,
  application.application_date,
  application.source AS recruiting_source,
  application.internal_worker_id IS NOT NULL AS internal_candidate_flag,
  application.internal_worker_id AS internal_employee_id,
  internal_history.job_code AS internal_applicant_job_code,
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
    stage.latest_reached_date
  ) AS days_last_stage_to_outcome,
  datediff(
    coalesce(stage.outcome_date, stage.latest_reached_date),
    stage.applied_event_date
  ) AS days_in_funnel,
  application.decline_reason,
  application.candidate_skills
FROM `${catalog}`.`${silver_schema}`.`applications_enriched` AS application
INNER JOIN stage_events AS stage
  ON application.application_id = stage.application_id
LEFT JOIN worker_versions AS internal_history
  ON application.internal_worker_id = internal_history.worker_id
  AND application.application_date >= internal_history.valid_from
  AND application.application_date < internal_history.valid_to;
