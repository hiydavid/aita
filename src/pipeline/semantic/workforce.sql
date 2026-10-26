USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`semantic_workforce_monthly` (
  month_start DATE COMMENT 'First date of the reporting month.',
  month_end DATE COMMENT 'Last date of the reporting month.',
  org_unit_id STRING COMMENT 'Organization-unit identifier joining to dim_org.',
  job_code STRING COMMENT 'Job-code identifier joining to dim_job.',
  headcount_eom BIGINT COMMENT 'Distinct active employees at month end.',
  hire_count BIGINT COMMENT 'Hire events effective during the month.',
  exit_count BIGINT COMMENT 'Voluntary and involuntary exit events during the month.',
  voluntary_exit_count BIGINT COMMENT 'Voluntary exit events during the month.',
  regrettable_voluntary_exit_count BIGINT COMMENT 'Voluntary exit events whose latest rating at exit was 4 or 5.',
  transfer_in_count BIGINT COMMENT 'Transfer events effective during the month.',
  promotion_count BIGINT COMMENT 'Promotion events effective during the month.',
  manager_change_count BIGINT COMMENT 'Manager-change events effective during the month.'
)
CLUSTER BY (month_start, org_unit_id)
COMMENT 'One row per organization unit, job code, and month with headcount, movement, and grain-aligned regrettable voluntary exits.'
AS
WITH regrettable_attrition AS (
  SELECT
    exit_month AS month_start,
    org_unit_id,
    job_code,
    count_if(is_voluntary AND regrettable_flag)
      AS regrettable_voluntary_exit_count
  FROM `${catalog}`.`${gold_schema}`.`fact_attrition_event`
  GROUP BY exit_month, org_unit_id, job_code
)
SELECT
  workforce.month_start,
  workforce.month_end,
  workforce.org_unit_id,
  workforce.job_code,
  workforce.headcount_eom,
  workforce.hire_count,
  workforce.exit_count,
  workforce.voluntary_exit_count,
  coalesce(attrition.regrettable_voluntary_exit_count, 0)
    AS regrettable_voluntary_exit_count,
  workforce.transfer_in_count,
  workforce.promotion_count,
  workforce.manager_change_count
FROM `${catalog}`.`${gold_schema}`.`fact_headcount_monthly` AS workforce
LEFT JOIN regrettable_attrition AS attrition
  ON workforce.month_start = attrition.month_start
  AND workforce.org_unit_id = attrition.org_unit_id
  AND workforce.job_code = attrition.job_code;
