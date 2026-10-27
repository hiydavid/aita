-- benchmark: 41000000000000000000000000000001
WITH yearly AS (
  SELECT workforce.year, workforce.business_line,
    MEASURE(workforce.voluntary_attrition_rate) AS voluntary_attrition_rate,
    MEASURE(workforce.voluntary_exits) AS voluntary_exits,
    MEASURE(workforce.average_monthly_headcount) AS average_monthly_headcount
  FROM ${catalog}.${gold_schema}.mv_workforce AS workforce
  GROUP BY ALL
), bounds AS (SELECT max(year) AS latest_year FROM yearly)
SELECT yearly.* FROM yearly CROSS JOIN bounds
WHERE yearly.year BETWEEN bounds.latest_year - 2 AND bounds.latest_year
ORDER BY yearly.business_line, yearly.year;

-- benchmark: 41000000000000000000000000000002
WITH centers AS (
  SELECT workforce.year, workforce.org_unit_name,
    MEASURE(workforce.voluntary_attrition_rate) AS voluntary_attrition_rate,
    MEASURE(workforce.period_end_headcount) AS period_end_headcount
  FROM ${catalog}.${gold_schema}.mv_workforce AS workforce
  WHERE workforce.org_type = 'Contact Center'
  GROUP BY ALL
), bounds AS (SELECT max(year) AS latest_year FROM centers)
SELECT centers.org_unit_name, centers.voluntary_attrition_rate, centers.period_end_headcount
FROM centers CROSS JOIN bounds WHERE centers.year = bounds.latest_year
ORDER BY centers.voluntary_attrition_rate DESC;

-- benchmark: 41000000000000000000000000000003
SELECT attrition.exit_reason, MEASURE(attrition.exits) AS exits
FROM ${catalog}.${gold_schema}.mv_attrition AS attrition
WHERE attrition.business_line = 'Consumer Banking' AND attrition.org_type = 'Contact Center'
GROUP BY ALL ORDER BY exits DESC;

-- benchmark: 41000000000000000000000000000004
SELECT attrition.manager_id, MEASURE(attrition.exits) AS exits,
  MEASURE(attrition.voluntary_exits) AS voluntary_exits
FROM ${catalog}.${gold_schema}.mv_attrition AS attrition
WHERE attrition.business_line = 'Consumer Banking' AND attrition.org_type = 'Contact Center'
GROUP BY ALL ORDER BY exits DESC;

-- benchmark: 41000000000000000000000000000005
SELECT engagement.org_unit_name,
  MEASURE(engagement.burnout_or_workload_signal_rate) AS signal_rate,
  MEASURE(engagement.survey_responses) AS survey_responses
FROM ${catalog}.${gold_schema}.mv_engagement AS engagement
GROUP BY ALL ORDER BY signal_rate DESC LIMIT 20;

-- benchmark: 41000000000000000000000000000006
WITH manager_engagement AS (
  SELECT engagement.manager_id, MEASURE(engagement.engagement_index) AS engagement_index,
    MEASURE(engagement.survey_responses) AS survey_responses
  FROM ${catalog}.${gold_schema}.mv_engagement AS engagement
  WHERE engagement.manager_id IS NOT NULL GROUP BY ALL
), manager_exits AS (
  SELECT attrition.manager_id, MEASURE(attrition.voluntary_exits) AS voluntary_exits
  FROM ${catalog}.${gold_schema}.mv_attrition AS attrition
  WHERE attrition.manager_id IS NOT NULL GROUP BY ALL
)
SELECT manager_engagement.manager_id, manager_engagement.engagement_index,
  manager_engagement.survey_responses, coalesce(manager_exits.voluntary_exits, 0) AS voluntary_exits
FROM manager_engagement LEFT JOIN manager_exits USING (manager_id)
ORDER BY manager_engagement.engagement_index DESC, voluntary_exits ASC LIMIT 20;

-- benchmark: 41000000000000000000000000000007
SELECT employee_id, business_line, risk_flags, reasons, signal_count, as_of_date
FROM ${catalog}.${gold_schema}.talent_watchlist
WHERE business_line = 'Consumer Banking'
ORDER BY signal_count DESC, employee_id LIMIT 100;

-- benchmark: 41000000000000000000000000000008
WITH bounds AS (
  SELECT max(productivity.month) AS latest_month
  FROM ${catalog}.${gold_schema}.mv_productivity AS productivity
  WHERE productivity.org_type = 'Fraud Operations'
), engagement_trend AS (
  SELECT engagement.month,
    MEASURE(engagement.engagement_index) AS engagement_index,
    MEASURE(engagement.survey_responses) AS survey_responses
  FROM ${catalog}.${gold_schema}.mv_engagement AS engagement
  WHERE engagement.org_type = 'Fraud Operations' GROUP BY ALL
), overtime_trend AS (
  SELECT productivity.month,
    MEASURE(productivity.average_overtime_hours_per_team_month) AS average_overtime_hours
  FROM ${catalog}.${gold_schema}.mv_productivity AS productivity
  WHERE productivity.org_type = 'Fraud Operations' GROUP BY ALL
), engagement_periods AS (
  SELECT CASE WHEN engagement_trend.month > add_months(bounds.latest_month, -12)
      THEN 'latest_12_months' ELSE 'prior_12_months' END AS period,
    sum(engagement_trend.engagement_index * engagement_trend.survey_responses)
      / sum(engagement_trend.survey_responses) AS engagement_index
  FROM engagement_trend CROSS JOIN bounds
  WHERE engagement_trend.month > add_months(bounds.latest_month, -24)
  GROUP BY period
), overtime_periods AS (
  SELECT CASE WHEN overtime_trend.month > add_months(bounds.latest_month, -12)
      THEN 'latest_12_months' ELSE 'prior_12_months' END AS period,
    avg(overtime_trend.average_overtime_hours) AS average_overtime_hours
  FROM overtime_trend CROSS JOIN bounds
  WHERE overtime_trend.month > add_months(bounds.latest_month, -24)
  GROUP BY period
)
SELECT engagement_periods.period, engagement_periods.engagement_index,
  overtime_periods.average_overtime_hours
FROM engagement_periods INNER JOIN overtime_periods USING (period)
ORDER BY engagement_periods.period;

-- benchmark: 41000000000000000000000000000009
SELECT workforce.job_family,
  MEASURE(workforce.regrettable_attrition_rate) AS regrettable_attrition_rate,
  MEASURE(workforce.regrettable_voluntary_exits) AS regrettable_voluntary_exits,
  MEASURE(workforce.average_monthly_headcount) AS average_monthly_headcount
FROM ${catalog}.${gold_schema}.mv_workforce AS workforce
GROUP BY ALL ORDER BY regrettable_attrition_rate DESC LIMIT 20;

-- benchmark: 41000000000000000000000000000010
WITH monthly AS (
  SELECT workforce.month, workforce.region,
    MEASURE(workforce.period_end_headcount) AS headcount,
    MEASURE(workforce.hires) AS hires, MEASURE(workforce.exits) AS exits
  FROM ${catalog}.${gold_schema}.mv_workforce AS workforce GROUP BY ALL
), bounds AS (SELECT max(month) AS latest_month FROM monthly)
SELECT monthly.region, monthly.headcount, monthly.hires, monthly.exits
FROM monthly CROSS JOIN bounds WHERE monthly.month = bounds.latest_month
ORDER BY monthly.region;
