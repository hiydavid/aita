USE CATALOG `${catalog}`;

CREATE OR REFRESH MATERIALIZED VIEW `${catalog}`.`${gold_schema}`.`talent_watchlist` (
  employee_id STRING COMMENT 'Current employee identifier joining to dim_worker; one row per flagged employee.',
  business_line STRING COMMENT 'Current employee business line.',
  risk_flags ARRAY<STRING> COMMENT 'Triggered rule identifiers. Values: stalled_high_performer, disengaging, team_at_risk, hard_to_backfill_risk.',
  reasons ARRAY<STRING> COMMENT 'Business-readable explanation for each risk flag in matching array order.',
  signal_count INT COMMENT 'Number of triggered risk flags; equals the size of risk_flags and reasons.',
  as_of_date DATE COMMENT 'Maximum business date across the Gold inputs used to evaluate the rules.'
)
CLUSTER BY (business_line, employee_id)
COMMENT 'One row per current employee with at least one rule-based talent risk, readable reasons, and an as-of date. Used by the talent watchlist experience.'
AS
WITH activity_dates AS (
  SELECT max(month_end) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_headcount_monthly`
  UNION ALL
  SELECT max(exit_date) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_attrition_event`
  UNION ALL
  SELECT max(survey_date) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_engagement`
  UNION ALL
  SELECT max(review_date) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_performance`
  UNION ALL
  SELECT max(effective_date) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_compensation`
  UNION ALL
  SELECT max(coalesce(close_date, open_date)) AS activity_date
  FROM `${catalog}`.`${gold_schema}`.`fact_requisition`
),
as_of AS (
  SELECT max(activity_date) AS as_of_date
  FROM activity_dates
),
current_employees AS (
  SELECT
    worker.employee_id,
    worker.hire_date,
    worker.job_code,
    worker.org_unit_id,
    org.business_line,
    job.job_family,
    job.licensed_role_flag,
    job.strategic_role_flag,
    bounds.as_of_date
  FROM `${catalog}`.`${gold_schema}`.`dim_worker` AS worker
  INNER JOIN `${catalog}`.`${gold_schema}`.`dim_org` AS org
    ON worker.org_unit_id = org.org_unit_id
  INNER JOIN `${catalog}`.`${gold_schema}`.`dim_job` AS job
    ON worker.job_code = job.job_code
  CROSS JOIN as_of AS bounds
  WHERE worker.employment_status = 'Active'
),
latest_performance AS (
  SELECT
    employee_id,
    top_rating_flag
  FROM `${catalog}`.`${gold_schema}`.`fact_performance`
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY review_date DESC, review_id DESC
  ) = 1
),
latest_compensation AS (
  SELECT
    employee_id,
    below_band_midpoint_flag
  FROM `${catalog}`.`${gold_schema}`.`fact_compensation`
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY effective_date DESC, compensation_id DESC
  ) = 1
),
promotion_history AS (
  SELECT
    worker_id AS employee_id,
    max(event_date) AS last_promotion_date
  FROM `${catalog}`.`${silver_schema}`.`worker_history`
  WHERE event_type = 'PROMOTION'
  GROUP BY worker_id
),
stalled_high_performers AS (
  SELECT employee.employee_id
  FROM current_employees AS employee
  INNER JOIN latest_performance AS performance
    ON employee.employee_id = performance.employee_id
  INNER JOIN latest_compensation AS compensation
    ON employee.employee_id = compensation.employee_id
  LEFT JOIN promotion_history AS promotion
    ON employee.employee_id = promotion.employee_id
  WHERE performance.top_rating_flag
    AND compensation.below_band_midpoint_flag
    AND datediff(employee.as_of_date, employee.hire_date) >= 1095
    AND (
      promotion.last_promotion_date IS NULL
      OR promotion.last_promotion_date < add_months(employee.as_of_date, -36)
    )
),
engagement_ranked AS (
  SELECT
    employee_id,
    engagement_score,
    burnout_flag,
    row_number() OVER (
      PARTITION BY employee_id
      ORDER BY survey_date DESC, survey_response_id DESC
    ) AS recency_rank
  FROM `${catalog}`.`${gold_schema}`.`fact_engagement`
),
recent_engagement AS (
  SELECT
    employee_id,
    max(CASE WHEN recency_rank = 1 THEN engagement_score END) AS latest_score,
    max(CASE WHEN recency_rank = 2 THEN engagement_score END) AS previous_score,
    max(CASE WHEN recency_rank = 3 THEN engagement_score END) AS prior_score,
    coalesce(
      max(CASE WHEN recency_rank = 1 THEN burnout_flag END),
      false
    ) AS latest_burnout_flag
  FROM engagement_ranked
  WHERE recency_rank <= 3
  GROUP BY employee_id
),
disengaging_employees AS (
  SELECT
    employee_id,
    latest_score < previous_score
      AND previous_score < prior_score AS consecutive_decline_flag,
    latest_burnout_flag
  FROM recent_engagement
  WHERE (
    latest_score < previous_score
    AND previous_score < prior_score
  )
    OR latest_burnout_flag
),
headcount_as_of AS (
  SELECT max(month_end) AS workforce_as_of_date
  FROM `${catalog}`.`${gold_schema}`.`fact_headcount_monthly`
),
monthly_org_headcount AS (
  SELECT
    headcount.org_unit_id,
    headcount.month_end,
    sum(headcount.headcount_eom) AS headcount_eom
  FROM `${catalog}`.`${gold_schema}`.`fact_headcount_monthly` AS headcount
  CROSS JOIN headcount_as_of AS bounds
  WHERE headcount.month_end > add_months(bounds.workforce_as_of_date, -12)
    AND headcount.month_end <= bounds.workforce_as_of_date
  GROUP BY
    headcount.org_unit_id,
    headcount.month_end
),
average_org_headcount AS (
  SELECT
    org_unit_id,
    avg(headcount_eom) AS average_headcount
  FROM monthly_org_headcount
  GROUP BY org_unit_id
),
recent_org_attrition AS (
  SELECT
    attrition.org_unit_id,
    count_if(attrition.is_voluntary) AS voluntary_exit_count,
    count_if(
      attrition.is_voluntary
      AND attrition.exit_reason IN ('manager', 'schedule and workload')
    ) AS qualifying_exit_count
  FROM `${catalog}`.`${gold_schema}`.`fact_attrition_event` AS attrition
  CROSS JOIN headcount_as_of AS bounds
  WHERE attrition.exit_date > add_months(bounds.workforce_as_of_date, -12)
    AND attrition.exit_date <= bounds.workforce_as_of_date
  GROUP BY attrition.org_unit_id
),
org_attrition_rates AS (
  SELECT
    headcount.org_unit_id,
    coalesce(attrition.voluntary_exit_count, 0) AS voluntary_exit_count,
    coalesce(attrition.qualifying_exit_count, 0) AS qualifying_exit_count,
    coalesce(attrition.voluntary_exit_count, 0)
      / nullif(headcount.average_headcount, 0) AS voluntary_attrition_rate
  FROM average_org_headcount AS headcount
  LEFT JOIN recent_org_attrition AS attrition
    ON headcount.org_unit_id = attrition.org_unit_id
),
bank_attrition_threshold AS (
  SELECT
    avg(voluntary_attrition_rate) * 2 AS voluntary_attrition_rate_threshold
  FROM org_attrition_rates
),
teams_at_risk AS (
  SELECT
    org.org_unit_id,
    org.voluntary_exit_count,
    org.qualifying_exit_count,
    org.voluntary_attrition_rate,
    threshold.voluntary_attrition_rate_threshold
  FROM org_attrition_rates AS org
  CROSS JOIN bank_attrition_threshold AS threshold
  WHERE org.voluntary_attrition_rate > threshold.voluntary_attrition_rate_threshold
    AND org.qualifying_exit_count > 0
),
job_family_fill_time AS (
  SELECT
    job.job_family,
    avg(requisition.time_to_fill_days) AS average_time_to_fill_days
  FROM `${catalog}`.`${gold_schema}`.`fact_requisition` AS requisition
  INNER JOIN `${catalog}`.`${gold_schema}`.`dim_job` AS job
    ON requisition.job_code = job.job_code
  WHERE requisition.filled_flag
    AND requisition.time_to_fill_days IS NOT NULL
  GROUP BY job.job_family
),
bank_fill_threshold AS (
  SELECT
    percentile_approx(average_time_to_fill_days, 0.5)
      AS median_job_family_fill_days
  FROM job_family_fill_time
),
hard_to_fill_job_families AS (
  SELECT
    family.job_family,
    family.average_time_to_fill_days,
    threshold.median_job_family_fill_days
  FROM job_family_fill_time AS family
  CROSS JOIN bank_fill_threshold AS threshold
  WHERE family.average_time_to_fill_days > threshold.median_job_family_fill_days
),
base_signals AS (
  SELECT
    employee.*,
    stalled.employee_id IS NOT NULL AS stalled_high_performer_flag,
    disengaging.employee_id IS NOT NULL AS disengaging_flag,
    coalesce(disengaging.consecutive_decline_flag, false)
      AS consecutive_engagement_decline_flag,
    coalesce(disengaging.latest_burnout_flag, false) AS latest_burnout_flag,
    team.org_unit_id IS NOT NULL AS team_at_risk_flag,
    team.voluntary_attrition_rate,
    team.voluntary_attrition_rate_threshold,
    family.average_time_to_fill_days,
    family.median_job_family_fill_days
  FROM current_employees AS employee
  LEFT JOIN stalled_high_performers AS stalled
    ON employee.employee_id = stalled.employee_id
  LEFT JOIN disengaging_employees AS disengaging
    ON employee.employee_id = disengaging.employee_id
  LEFT JOIN teams_at_risk AS team
    ON employee.org_unit_id = team.org_unit_id
  LEFT JOIN hard_to_fill_job_families AS family
    ON employee.job_family = family.job_family
),
all_signals AS (
  SELECT
    *,
    (licensed_role_flag OR strategic_role_flag)
      AND average_time_to_fill_days IS NOT NULL
      AND (
        stalled_high_performer_flag
        OR disengaging_flag
        OR team_at_risk_flag
      ) AS hard_to_backfill_risk_flag
  FROM base_signals
),
flagged_employees AS (
  SELECT
    *,
    filter(
      array(
        CASE
          WHEN stalled_high_performer_flag THEN 'stalled_high_performer'
        END,
        CASE WHEN disengaging_flag THEN 'disengaging' END,
        CASE WHEN team_at_risk_flag THEN 'team_at_risk' END,
        CASE
          WHEN hard_to_backfill_risk_flag THEN 'hard_to_backfill_risk'
        END
      ),
      flag -> flag IS NOT NULL
    ) AS risk_flags,
    filter(
      array(
        CASE
          WHEN stalled_high_performer_flag
            THEN 'Top-rated employee is below band midpoint and has not been promoted in at least three years.'
        END,
        CASE
          WHEN disengaging_flag
            AND consecutive_engagement_decline_flag
            AND latest_burnout_flag
            THEN 'Engagement declined in each of the two latest wave-to-wave changes, and the latest comment was AI-classified as burnout.'
          WHEN disengaging_flag
            AND consecutive_engagement_decline_flag
            THEN 'Engagement declined in each of the two latest wave-to-wave changes.'
          WHEN disengaging_flag
            THEN 'The latest engagement comment was AI-classified as burnout.'
        END,
        CASE
          WHEN team_at_risk_flag
            THEN format_string(
              'Team trailing-12-month voluntary attrition is %.1f%%, above the %.1f%% risk threshold, with manager or schedule and workload exit reasons.',
              voluntary_attrition_rate * 100,
              voluntary_attrition_rate_threshold * 100
            )
        END,
        CASE
          WHEN hard_to_backfill_risk_flag
            THEN format_string(
              '%s is a licensed or strategic job family averaging %.1f days to fill, above the bank median of %.1f days.',
              job_family,
              average_time_to_fill_days,
              median_job_family_fill_days
            )
        END
      ),
      reason -> reason IS NOT NULL
    ) AS reasons
  FROM all_signals
  WHERE stalled_high_performer_flag
    OR disengaging_flag
    OR team_at_risk_flag
)
SELECT
  employee_id,
  business_line,
  risk_flags,
  reasons,
  size(risk_flags) AS signal_count,
  as_of_date
FROM flagged_employees;
