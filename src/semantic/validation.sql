WITH dim_worker AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.dim_worker')
),
worker_history AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :silver_schema || '.worker_history')
),
headcount AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_headcount_monthly')
),
attrition AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_attrition_event')
),
performance AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_performance')
),
compensation AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_compensation')
),
watchlist AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.talent_watchlist')
),
workforce AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_workforce_monthly')
),
talent AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_talent_snapshot')
),
talent_skills AS (
  SELECT * FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_talent_skills')
),
expected_promotions AS (
  SELECT worker_id AS employee_id, max(event_date) AS last_promotion_date
  FROM worker_history
  WHERE event_type = 'PROMOTION'
  GROUP BY worker_id
),
latest_performance AS (
  SELECT employee_id, review_id
  FROM performance
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY review_date DESC, review_id DESC
  ) = 1
),
latest_compensation AS (
  SELECT employee_id, compensation_id, pay_position_to_midpoint
  FROM compensation
  QUALIFY row_number() OVER (
    PARTITION BY employee_id
    ORDER BY effective_date DESC, compensation_id DESC
  ) = 1
),
expected_skills AS (
  SELECT DISTINCT
    employee_id,
    lower(trim(skill)) AS demonstrated_skill
  FROM talent
  LATERAL VIEW explode(demonstrated_skills) AS skill
  WHERE skill IS NOT NULL
    AND trim(skill) <> ''
),
checks AS (
  SELECT
    'dim_worker_grain' AS check_name,
    count(*) - count(DISTINCT employee_id) AS violation_count
  FROM dim_worker

  UNION ALL

  SELECT
    'dim_worker_last_promotion_parity',
    count_if(NOT (worker.last_promotion_date <=> promotion.last_promotion_date))
  FROM dim_worker AS worker
  LEFT JOIN expected_promotions AS promotion
    ON worker.employee_id = promotion.employee_id

  UNION ALL

  SELECT
    'semantic_workforce_monthly_grain',
    count(*) - count(DISTINCT struct(month_start, org_unit_id, job_code))
  FROM workforce

  UNION ALL

  SELECT
    'semantic_workforce_monthly_row_parity',
    abs(
      (SELECT count(*) FROM workforce)
      - (SELECT count(*) FROM headcount)
    )

  UNION ALL

  SELECT
    'semantic_workforce_monthly_fact_parity',
    count_if(
      NOT (workforce.month_end <=> source.month_end)
      OR NOT (workforce.headcount_eom <=> source.headcount_eom)
      OR NOT (workforce.hire_count <=> source.hire_count)
      OR NOT (workforce.exit_count <=> source.exit_count)
      OR NOT (workforce.voluntary_exit_count <=> source.voluntary_exit_count)
      OR NOT (workforce.transfer_in_count <=> source.transfer_in_count)
      OR NOT (workforce.promotion_count <=> source.promotion_count)
      OR NOT (workforce.manager_change_count <=> source.manager_change_count)
    )
  FROM workforce
  FULL OUTER JOIN headcount AS source
    ON workforce.month_start = source.month_start
    AND workforce.org_unit_id = source.org_unit_id
    AND workforce.job_code = source.job_code

  UNION ALL

  SELECT
    'semantic_workforce_monthly_regrettable_parity',
    abs(
      (SELECT sum(regrettable_voluntary_exit_count) FROM workforce)
      - (SELECT count_if(is_voluntary AND regrettable_flag) FROM attrition)
    )

  UNION ALL

  SELECT
    'semantic_talent_snapshot_grain',
    count(*) - count(DISTINCT employee_id)
  FROM talent

  UNION ALL

  SELECT
    'semantic_talent_snapshot_active_population',
    abs(
      (SELECT count(*) FROM talent)
      - (SELECT count(*) FROM dim_worker WHERE employment_status = 'Active')
    )

  UNION ALL

  SELECT
    'semantic_talent_snapshot_latest_performance',
    count_if(NOT (talent.review_id <=> latest.review_id))
  FROM talent
  LEFT JOIN latest_performance AS latest
    ON talent.employee_id = latest.employee_id

  UNION ALL

  SELECT
    'semantic_talent_snapshot_latest_compensation',
    count_if(
      NOT (talent.compensation_id <=> latest.compensation_id)
      OR NOT (
        talent.pay_position_to_midpoint
          <=> latest.pay_position_to_midpoint
      )
    )
  FROM talent
  LEFT JOIN latest_compensation AS latest
    ON talent.employee_id = latest.employee_id

  UNION ALL

  SELECT
    'semantic_talent_snapshot_stalled_watchlist_parity',
    count_if(
      talent.stalled_high_performer_flag
        <> coalesce(array_contains(watchlist.risk_flags, 'stalled_high_performer'), false)
    )
  FROM talent
  LEFT JOIN watchlist
    ON talent.employee_id = watchlist.employee_id

  UNION ALL

  SELECT
    'semantic_talent_skills_grain',
    count(*) - count(DISTINCT struct(employee_id, demonstrated_skill))
  FROM talent_skills

  UNION ALL

  SELECT
    'semantic_talent_skills_explode_parity',
    count_if(expected.employee_id IS NULL OR actual.employee_id IS NULL)
  FROM expected_skills AS expected
  FULL OUTER JOIN talent_skills AS actual
    ON expected.employee_id = actual.employee_id
    AND expected.demonstrated_skill = actual.demonstrated_skill
)
SELECT
  check_name,
  violation_count,
  CASE WHEN violation_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_name;
