WITH workforce_mv AS (
  SELECT
    MEASURE(period_end_headcount) AS period_end_headcount,
    MEASURE(average_monthly_headcount) AS average_monthly_headcount,
    MEASURE(hires) AS hires,
    MEASURE(exits) AS exits,
    MEASURE(voluntary_exits) AS voluntary_exits,
    MEASURE(regrettable_voluntary_exits) AS regrettable_voluntary_exits,
    MEASURE(voluntary_attrition_rate) AS voluntary_attrition_rate,
    MEASURE(regrettable_attrition_rate) AS regrettable_attrition_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_workforce')
),
workforce_direct AS (
  SELECT
    sum(headcount_eom) FILTER (
      WHERE month_start = (SELECT max(month_start) FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_workforce_monthly'))
    ) AS period_end_headcount,
    sum(headcount_eom) / count(DISTINCT month_start) AS average_monthly_headcount,
    sum(hire_count) AS hires,
    sum(exit_count) AS exits,
    sum(voluntary_exit_count) AS voluntary_exits,
    sum(regrettable_voluntary_exit_count) AS regrettable_voluntary_exits
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_workforce_monthly')
),
workforce_year_mv AS (
  SELECT
    year,
    MEASURE(period_end_headcount) AS period_end_headcount,
    MEASURE(average_monthly_headcount) AS average_monthly_headcount,
    MEASURE(voluntary_attrition_rate) AS voluntary_attrition_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_workforce')
  GROUP BY ALL
),
workforce_year_direct AS (
  SELECT
    year(workforce.month_start) AS year,
    sum(workforce.headcount_eom) FILTER (WHERE workforce.month_start = bounds.latest_month) AS period_end_headcount,
    sum(workforce.headcount_eom) / count(DISTINCT workforce.month_start) AS average_monthly_headcount,
    sum(workforce.voluntary_exit_count) / (sum(workforce.headcount_eom) / count(DISTINCT workforce.month_start)) AS voluntary_attrition_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_workforce_monthly') AS workforce
  INNER JOIN (
    SELECT year(month_start) AS year, max(month_start) AS latest_month
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_workforce_monthly')
    GROUP BY year(month_start)
  ) AS bounds
    ON year(workforce.month_start) = bounds.year
  GROUP BY year(workforce.month_start)
),
attrition_mv AS (
  SELECT
    MEASURE(exits) AS exits,
    MEASURE(voluntary_exits) AS voluntary_exits,
    MEASURE(regrettable_exits) AS regrettable_exits,
    MEASURE(regrettable_voluntary_exits) AS regrettable_voluntary_exits
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_attrition')
),
attrition_direct AS (
  SELECT
    count(*) AS exits,
    count_if(is_voluntary) AS voluntary_exits,
    count_if(regrettable_flag) AS regrettable_exits,
    count_if(is_voluntary AND regrettable_flag) AS regrettable_voluntary_exits
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_attrition_event')
),
engagement_mv AS (
  SELECT
    MEASURE(negative_comment_share) AS negative_comment_share,
    MEASURE(burnout_or_workload_signal_rate) AS burnout_or_workload_signal_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_engagement')
),
engagement_direct AS (
  SELECT
    count_if(comment_sentiment = 'negative') / nullif(count(comment_sentiment), 0) AS negative_comment_share,
    count_if(comment_theme IN ('burnout', 'workload')) / nullif(count(comment_theme), 0) AS burnout_or_workload_signal_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_engagement')
),
engagement_wave_mv AS (
  SELECT
    survey_date,
    MEASURE(engagement_index) AS engagement_index,
    MEASURE(previous_wave_engagement_index) AS previous_wave_engagement_index,
    MEASURE(engagement_change) AS engagement_change
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_engagement')
  GROUP BY ALL
),
engagement_wave_direct AS (
  SELECT
    survey_date,
    engagement_index,
    lag(engagement_index) OVER (ORDER BY survey_date) AS previous_wave_engagement_index,
    engagement_index - lag(engagement_index) OVER (ORDER BY survey_date) AS engagement_change
  FROM (
    SELECT survey_date, avg(engagement_score) AS engagement_index
    FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_engagement')
    GROUP BY survey_date
  )
),
productivity_mv AS (
  SELECT
    MEASURE(cases_handled) AS cases_handled,
    MEASURE(overtime_hours) AS overtime_hours,
    MEASURE(average_overtime_hours_per_team_month) AS average_overtime,
    MEASURE(case_weighted_csat) AS weighted_csat,
    MEASURE(case_weighted_average_handle_time) AS weighted_handle_time,
    MEASURE(case_weighted_quality_score) AS weighted_quality
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_productivity')
),
productivity_direct AS (
  SELECT
    sum(cases_handled) AS cases_handled,
    sum(overtime_hours) AS overtime_hours,
    avg(overtime_hours) AS average_overtime,
    sum(csat_score * cases_handled) / sum(cases_handled) AS weighted_csat,
    sum(avg_handle_time_minutes * cases_handled) / sum(cases_handled) AS weighted_handle_time,
    sum(quality_score * cases_handled) / sum(cases_handled) AS weighted_quality
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_productivity')
),
checks AS (
  SELECT 'workforce_all_measures' AS check_name,
    count_if(NOT (
      mv.period_end_headcount <=> direct.period_end_headcount
      AND abs(mv.average_monthly_headcount - direct.average_monthly_headcount) < 1e-9
      AND mv.hires <=> direct.hires AND mv.exits <=> direct.exits
      AND mv.voluntary_exits <=> direct.voluntary_exits
      AND mv.regrettable_voluntary_exits <=> direct.regrettable_voluntary_exits
      AND abs(mv.voluntary_attrition_rate - direct.voluntary_exits / direct.average_monthly_headcount) < 1e-9
      AND abs(mv.regrettable_attrition_rate - direct.regrettable_voluntary_exits / direct.average_monthly_headcount) < 1e-9
    )) AS violation_count
  FROM workforce_mv mv CROSS JOIN workforce_direct direct
  UNION ALL
  SELECT 'workforce_year_semiadditive', count_if(NOT (
    mv.period_end_headcount <=> direct.period_end_headcount
    AND abs(mv.average_monthly_headcount - direct.average_monthly_headcount) < 1e-9
    AND abs(mv.voluntary_attrition_rate - direct.voluntary_attrition_rate) < 1e-9
  )) FROM workforce_year_mv mv FULL JOIN workforce_year_direct direct USING (year)
  UNION ALL
  SELECT 'attrition_all_measures', count_if(NOT (
    mv.exits <=> direct.exits AND mv.voluntary_exits <=> direct.voluntary_exits
    AND mv.regrettable_exits <=> direct.regrettable_exits
    AND mv.regrettable_voluntary_exits <=> direct.regrettable_voluntary_exits
  )) FROM attrition_mv mv CROSS JOIN attrition_direct direct
  UNION ALL
  SELECT 'engagement_rates', count_if(NOT (
    abs(mv.negative_comment_share - direct.negative_comment_share) < 1e-9
    AND abs(mv.burnout_or_workload_signal_rate - direct.burnout_or_workload_signal_rate) < 1e-9
  )) FROM engagement_mv mv CROSS JOIN engagement_direct direct
  UNION ALL
  SELECT 'engagement_previous_wave', count_if(NOT (
    abs(mv.engagement_index - direct.engagement_index) < 1e-6
    AND (mv.previous_wave_engagement_index <=> direct.previous_wave_engagement_index)
    AND (mv.engagement_change <=> direct.engagement_change)
  )) FROM engagement_wave_mv mv FULL JOIN engagement_wave_direct direct USING (survey_date)
  UNION ALL
  SELECT 'productivity_all_measures', count_if(NOT (
    mv.cases_handled <=> direct.cases_handled
    AND abs(mv.overtime_hours - direct.overtime_hours) < 1e-9
    AND abs(mv.average_overtime - direct.average_overtime) < 1e-6
    AND abs(mv.weighted_csat - direct.weighted_csat) < 1e-9
    AND abs(mv.weighted_handle_time - direct.weighted_handle_time) < 1e-9
    AND abs(mv.weighted_quality - direct.weighted_quality) < 1e-9
  )) FROM productivity_mv mv CROSS JOIN productivity_direct direct
)
SELECT
  check_name,
  violation_count,
  CASE WHEN violation_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_name;
