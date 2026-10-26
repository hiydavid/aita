USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_worker`
COMMENT 'Current employee dimension with the latest effective job, organization, and manager assignment.'
AS
WITH current_worker_history AS (
  SELECT
    worker_id,
    event_type,
    event_date,
    termination_type
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE __END_AT IS NULL
)
SELECT
  worker.worker_id AS employee_id,
  worker.first_name,
  worker.last_name,
  concat_ws(' ', worker.first_name, worker.last_name) AS employee_name,
  worker.birth_date,
  worker.gender,
  worker.hire_date,
  worker.termination_date,
  worker.employment_status,
  worker.job_code,
  worker.org_unit_id,
  worker.manager_id,
  worker.worker_type,
  history.event_type AS latest_event_type,
  history.event_date AS latest_event_date,
  history.termination_type
FROM `${catalog}`.`${silver_schema}`.`workers` AS worker
LEFT JOIN current_worker_history AS history
  ON worker.worker_id = history.worker_id;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_org`
COMMENT 'Organization dimension at one row per organization unit.'
AS
SELECT
  org.org_unit_id,
  org.org_unit_name,
  org.business_line,
  org.org_type,
  org.region,
  org.location,
  org.parent_org_unit_id AS business_line_id,
  org.manager_id,
  concat_ws(' ', manager.first_name, manager.last_name) AS manager_name,
  org.schedule_change_date,
  org.standout_manager_flag
FROM `${catalog}`.`${silver_schema}`.`org_units` AS org
LEFT JOIN `${catalog}`.`${silver_schema}`.`workers` AS manager
  ON org.manager_id = manager.worker_id;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_job`
COMMENT 'Job dimension with governed role attributes and AI-derived exposure and skill signals.'
AS
SELECT
  job_code,
  job_title,
  job_family,
  job_level,
  business_line,
  licensed_role_flag,
  strategic_role_flag,
  job_description,
  expected_genai_exposure_tier,
  genai_exposure_tier,
  NOT (genai_exposure_tier <=> expected_genai_exposure_tier) AS genai_tier_mismatch_flag,
  required_skills
FROM `${catalog}`.`${silver_schema}`.`jobs_enriched`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_date`
COMMENT 'Calendar dimension spanning all conformed workforce, talent, and recruiting activity dates.'
AS
WITH activity_dates AS (
  SELECT hire_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`workers`
  UNION ALL
  SELECT termination_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`workers`
  UNION ALL
  SELECT event_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  UNION ALL
  SELECT month AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`team_productivity`
  UNION ALL
  SELECT exit_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`exit_interviews_enriched`
  UNION ALL
  SELECT interview_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`exit_interviews_enriched`
  UNION ALL
  SELECT survey_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`engagement_enriched`
  UNION ALL
  SELECT review_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`performance_enriched`
  UNION ALL
  SELECT effective_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`compensation`
  UNION ALL
  SELECT open_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`requisitions`
  UNION ALL
  SELECT close_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`requisitions`
  UNION ALL
  SELECT application_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`applications_enriched`
  UNION ALL
  SELECT event_date AS calendar_date
  FROM `${catalog}`.`${silver_schema}`.`application_events`
),
date_bounds AS (
  SELECT
    min(calendar_date) AS minimum_date,
    max(calendar_date) AS maximum_date
  FROM activity_dates
),
calendar_bounds AS (
  SELECT
    make_date(year(minimum_date), 1, 1) AS calendar_start_date,
    make_date(year(maximum_date) + 1, 12, 31) AS calendar_end_date
  FROM date_bounds
),
date_spine AS (
  SELECT explode(sequence(calendar_start_date, calendar_end_date, INTERVAL 1 DAY)) AS calendar_date
  FROM calendar_bounds
)
SELECT
  CAST(date_format(calendar_date, 'yyyyMMdd') AS INT) AS date_key,
  calendar_date,
  year(calendar_date) AS calendar_year,
  quarter(calendar_date) AS calendar_quarter,
  month(calendar_date) AS calendar_month,
  date_format(calendar_date, 'MMMM') AS calendar_month_name,
  weekofyear(calendar_date) AS calendar_week,
  dayofmonth(calendar_date) AS day_of_month,
  dayofweek(calendar_date) AS day_of_week,
  date_format(calendar_date, 'EEEE') AS day_of_week_name,
  trunc(calendar_date, 'MONTH') AS month_start_date,
  last_day(calendar_date) AS month_end_date,
  dayofweek(calendar_date) IN (1, 7) AS is_weekend
FROM date_spine;
