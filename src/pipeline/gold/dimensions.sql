USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_worker` (
  employee_id STRING COMMENT 'Stable employee identifier; one value per worker.',
  first_name STRING COMMENT 'Employee given name.',
  last_name STRING COMMENT 'Employee family name.',
  employee_name STRING COMMENT 'Employee display name formed from first and last name.',
  birth_date DATE COMMENT 'Employee date of birth.',
  gender STRING COMMENT 'Self-described gender. Values: Female, Male, Non-binary, Prefer not to say.',
  hire_date DATE COMMENT 'Date the employee first joined the bank.',
  termination_date DATE COMMENT 'Date employment ended; null for active employees.',
  employment_status STRING COMMENT 'Current employment state. Values: Active, Terminated.',
  job_code STRING COMMENT 'Current job code joining to dim_job.',
  org_unit_id STRING COMMENT 'Current organization unit joining to dim_org.',
  manager_id STRING COMMENT 'Current manager employee identifier joining to dim_worker.',
  worker_type STRING COMMENT 'Employment arrangement. Values: Full Time, Part Time.',
  latest_event_type STRING COMMENT 'Most recent worker-history event. Values: HIRE, TRANSFER, PROMOTION, MANAGER_CHANGE, EXIT.',
  latest_event_date DATE COMMENT 'Effective date of the most recent worker-history event.',
  last_promotion_date DATE COMMENT 'Most recent promotion effective date across worker history; null when the employee has never been promoted.',
  termination_type STRING COMMENT 'Departure classification for terminated employees. Values: Voluntary, Involuntary; null for active employees.'
)
COMMENT 'One row per employee with the current job, organization, manager, and employment state. Used as the workforce dimension across Gold facts.'
AS
WITH current_worker_history AS (
  SELECT
    worker_id,
    event_type,
    event_date,
    termination_type
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE __END_AT IS NULL
),
promotion_history AS (
  SELECT
    worker_id,
    max(event_date) AS last_promotion_date
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE event_type = 'PROMOTION'
  GROUP BY worker_id
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
  promotion.last_promotion_date,
  history.termination_type
FROM `${catalog}`.`${silver_schema}`.`workers` AS worker
LEFT JOIN current_worker_history AS history
  ON worker.worker_id = history.worker_id
LEFT JOIN promotion_history AS promotion
  ON worker.worker_id = promotion.worker_id;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_org` (
  org_unit_id STRING COMMENT 'Stable organization-unit identifier.',
  org_unit_name STRING COMMENT 'Business-friendly organization-unit name.',
  business_line STRING COMMENT 'Top-level bank business line. Values: Consumer Banking, Wealth Management, Commercial Banking, Operations, Technology, Corporate Functions.',
  org_type STRING COMMENT 'Organization hierarchy type, such as business line, region, branch, or team.',
  region STRING COMMENT 'Geographic region assigned to the organization unit.',
  location STRING COMMENT 'Primary work location for the organization unit.',
  business_line_id STRING COMMENT 'Parent organization identifier representing the business line.',
  manager_id STRING COMMENT 'Employee identifier for the organization-unit manager.',
  manager_name STRING COMMENT 'Display name of the organization-unit manager.',
  schedule_change_date DATE COMMENT 'Date a planted operating-schedule change took effect; null when none occurred.',
  standout_manager_flag BOOLEAN COMMENT 'True for planted standout-manager teams; false otherwise.'
)
COMMENT 'One row per organization unit with hierarchy, geography, manager, and planted-pattern context. Used to slice workforce facts.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_job` (
  job_code STRING COMMENT 'Stable job-code identifier.',
  job_title STRING COMMENT 'Business-friendly job title.',
  job_family STRING COMMENT 'Job family used for recruiting and talent comparisons.',
  job_level STRING COMMENT 'Career level assigned to the job.',
  business_line STRING COMMENT 'Business line that owns the job.',
  licensed_role_flag BOOLEAN COMMENT 'True when the role requires a professional license; false otherwise.',
  strategic_role_flag BOOLEAN COMMENT 'True when the role is designated strategically important; false otherwise.',
  job_description STRING COMMENT 'Source job-description text used for AI enrichment.',
  expected_genai_exposure_tier STRING COMMENT 'Generator-planted GenAI exposure label. Values: high, medium, low.',
  genai_exposure_tier STRING COMMENT 'AI-classified from job_description using ai_classify. Values: high, medium, low.',
  genai_tier_mismatch_flag BOOLEAN COMMENT 'True when the AI-classified exposure tier differs from the planted expected tier; false otherwise.',
  required_skills ARRAY<STRING> COMMENT 'AI-extracted from job_description using ai_extract; each element is a concise required skill.'
)
COMMENT 'One row per job code with role attributes and AI-derived GenAI exposure and required skills. Used across talent and recruiting analysis.'
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

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`dim_date` (
  date_key INT COMMENT 'Calendar key in yyyyMMdd numeric format.',
  calendar_date DATE COMMENT 'Calendar date represented by the row.',
  calendar_year INT COMMENT 'Four-digit calendar year.',
  calendar_quarter INT COMMENT 'Calendar quarter number. Values: 1 through 4.',
  calendar_month INT COMMENT 'Calendar month number. Values: 1 through 12.',
  calendar_month_name STRING COMMENT 'Full English calendar month name.',
  calendar_week INT COMMENT 'Week-of-year number.',
  day_of_month INT COMMENT 'Day number within the month. Values: 1 through 31.',
  day_of_week INT COMMENT 'Spark day-of-week number. Values: 1 for Sunday through 7 for Saturday.',
  day_of_week_name STRING COMMENT 'Full English day-of-week name.',
  month_start_date DATE COMMENT 'First calendar date of the month.',
  month_end_date DATE COMMENT 'Last calendar date of the month.',
  is_weekend BOOLEAN COMMENT 'True for Saturday or Sunday; false otherwise.'
)
COMMENT 'One row per calendar day spanning all conformed workforce, talent, and recruiting activity. Used for consistent time analysis.'
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
