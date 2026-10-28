USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`semantic_talent_snapshot` (
  employee_id STRING COMMENT 'Active employee identifier; one row per employee.',
  employee_name STRING COMMENT 'Current employee display name.',
  hire_date DATE COMMENT 'Date the employee first joined the bank.',
  last_promotion_date DATE COMMENT 'Most recent promotion date; null when never promoted.',
  months_since_promotion_or_hire INT COMMENT 'Whole months since the last promotion, or since hire when never promoted.',
  tenure_band STRING COMMENT 'Current tenure band. Values: Under 1 year, 1-2 years, 3-4 years, 5+ years.',
  as_of_date DATE COMMENT 'Latest Gold business date used for the current snapshot.',
  org_unit_id STRING COMMENT 'Current organization-unit identifier.',
  org_unit_name STRING COMMENT 'Current organization-unit name.',
  org_type STRING COMMENT 'Current organization-unit hierarchy type.',
  business_line STRING COMMENT 'Current business line.',
  region STRING COMMENT 'Current geographic region.',
  location STRING COMMENT 'Current work location.',
  job_code STRING COMMENT 'Current job-code identifier.',
  job_title STRING COMMENT 'Current job title.',
  job_family STRING COMMENT 'Current job family.',
  job_level STRING COMMENT 'Current career level.',
  manager_id STRING COMMENT 'Current manager employee identifier.',
  licensed_role_flag BOOLEAN COMMENT 'True when the current role requires a professional license.',
  strategic_role_flag BOOLEAN COMMENT 'True when the current role is strategically designated.',
  genai_exposure_tier STRING COMMENT 'AI-classified GenAI exposure of the current role. Values: high, medium, low.',
  review_id STRING COMMENT 'Latest performance-review identifier.',
  review_date DATE COMMENT 'Date of the latest performance review.',
  performance_rating STRING COMMENT 'Latest performance outcome.',
  rating_numeric INT COMMENT 'Latest numeric performance score.',
  potential_rating STRING COMMENT 'Latest assessed employee potential.',
  top_rating_flag BOOLEAN COMMENT 'True when the latest rating_numeric equals 5.',
  high_potential_flag BOOLEAN COMMENT 'True when the latest potential rating is High.',
  demonstrated_skills ARRAY<STRING> COMMENT 'AI-extracted skills from the latest performance review.',
  compensation_id STRING COMMENT 'Latest compensation-record identifier.',
  compensation_effective_date DATE COMMENT 'Effective date of the latest compensation record.',
  pay_position_to_midpoint DECIMAL(18, 4) COMMENT 'Base salary divided by band midpoint; visible only to aita_hr_admin members.' MASK `${catalog}`.`${gold_schema}`.`mask_compensation`,
  pay_position_band STRING COMMENT 'Non-sensitive latest pay-position category.',
  below_band_midpoint_flag BOOLEAN COMMENT 'True when latest base salary is below band midpoint.',
  watchlist_flag BOOLEAN COMMENT 'True when the employee is present on the governed talent watchlist.',
  risk_flags ARRAY<STRING> COMMENT 'Governed watchlist rule identifiers triggered for the employee.',
  risk_reasons ARRAY<STRING> COMMENT 'Business-readable governed watchlist explanations.',
  stalled_high_performer_flag BOOLEAN COMMENT 'True for latest rating 5, below midpoint, at least three years tenure, and no promotion in the last 36 months.'
)
CLUSTER BY (business_line, org_unit_id, job_code)
COMMENT 'One row per active employee at the latest Gold business date with latest talent, governed pay-position, role, organization, and watchlist context.'
AS
WITH snapshot_as_of AS (
  SELECT max(as_of_date) AS as_of_date
  FROM `${catalog}`.`${gold_schema}`.`talent_watchlist`
)
SELECT
  worker.employee_id,
  worker.employee_name,
  worker.hire_date,
  worker.last_promotion_date,
  CAST(floor(months_between(
    bounds.as_of_date,
    coalesce(worker.last_promotion_date, worker.hire_date)
  )) AS INT) AS months_since_promotion_or_hire,
  CASE
    WHEN datediff(bounds.as_of_date, worker.hire_date) < 365 THEN 'Under 1 year'
    WHEN datediff(bounds.as_of_date, worker.hire_date) < 1095 THEN '1-2 years'
    WHEN datediff(bounds.as_of_date, worker.hire_date) < 1826 THEN '3-4 years'
    ELSE '5+ years'
  END AS tenure_band,
  bounds.as_of_date,
  worker.org_unit_id,
  org.org_unit_name,
  org.org_type,
  org.business_line,
  org.region,
  org.location,
  worker.job_code,
  job.job_title,
  job.job_family,
  job.job_level,
  worker.manager_id,
  job.licensed_role_flag,
  job.strategic_role_flag,
  job.genai_exposure_tier,
  talent.review_id,
  talent.review_date,
  talent.performance_rating,
  talent.rating_numeric,
  talent.potential_rating,
  coalesce(talent.top_rating_flag, false) AS top_rating_flag,
  coalesce(talent.high_potential_flag, false) AS high_potential_flag,
  talent.demonstrated_skills,
  talent.compensation_id,
  talent.compensation_effective_date,
  talent.pay_position_to_midpoint,
  talent.pay_position_band,
  talent.below_band_midpoint_flag,
  watchlist.employee_id IS NOT NULL AS watchlist_flag,
  coalesce(watchlist.risk_flags, CAST(array() AS ARRAY<STRING>)) AS risk_flags,
  coalesce(watchlist.reasons, CAST(array() AS ARRAY<STRING>)) AS risk_reasons,
  coalesce(
    array_contains(watchlist.risk_flags, 'stalled_high_performer'),
    false
  ) AS stalled_high_performer_flag
FROM `${catalog}`.`${gold_schema}`.`dim_worker` AS worker
INNER JOIN `${catalog}`.`${gold_schema}`.`dim_org` AS org
  ON worker.org_unit_id = org.org_unit_id
INNER JOIN `${catalog}`.`${gold_schema}`.`dim_job` AS job
  ON worker.job_code = job.job_code
CROSS JOIN snapshot_as_of AS bounds
LEFT JOIN latest_talent AS talent
  ON worker.employee_id = talent.employee_id
LEFT JOIN `${catalog}`.`${gold_schema}`.`talent_watchlist` AS watchlist
  ON worker.employee_id = watchlist.employee_id
WHERE worker.employment_status = 'Active';
