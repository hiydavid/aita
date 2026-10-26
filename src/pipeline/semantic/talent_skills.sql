USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`semantic_talent_skills` (
  employee_id STRING COMMENT 'Active employee identifier.',
  demonstrated_skill STRING COMMENT 'Normalized AI-extracted skill from the latest performance review.',
  as_of_date DATE COMMENT 'Latest Gold business date used for the talent snapshot.',
  org_unit_id STRING COMMENT 'Current organization-unit identifier.',
  job_code STRING COMMENT 'Current job-code identifier.',
  top_rating_flag BOOLEAN COMMENT 'True when the employee latest rating_numeric equals 5.'
)
CLUSTER BY (demonstrated_skill, org_unit_id, job_code)
COMMENT 'One row per active employee and distinct normalized AI-extracted skill from the employee latest performance review.'
AS
SELECT DISTINCT
  snapshot.employee_id,
  lower(trim(skill)) AS demonstrated_skill,
  snapshot.as_of_date,
  snapshot.org_unit_id,
  snapshot.job_code,
  snapshot.top_rating_flag
FROM `${catalog}`.`${gold_schema}`.`semantic_talent_snapshot` AS snapshot
LATERAL VIEW explode(snapshot.demonstrated_skills) AS skill
WHERE skill IS NOT NULL
  AND trim(skill) <> '';
