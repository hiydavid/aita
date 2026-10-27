WITH talent_mv AS (
  SELECT
    MEASURE(active_employees) AS active_employees,
    MEASURE(high_performers) AS high_performers,
    MEASURE(high_performer_share) AS high_performer_share,
    MEASURE(stalled_high_performers) AS stalled_high_performers,
    MEASURE(below_midpoint_employees) AS below_midpoint_employees,
    MEASURE(below_midpoint_share) AS below_midpoint_share,
    MEASURE(average_months_since_promotion_or_hire) AS average_months,
    MEASURE(average_pay_position_to_midpoint) AS average_pay_position
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_talent')
),
talent_direct AS (
  SELECT
    count(DISTINCT employee_id) AS active_employees,
    count(DISTINCT employee_id) FILTER (WHERE top_rating_flag) AS high_performers,
    count(DISTINCT employee_id) FILTER (WHERE top_rating_flag) / count(DISTINCT employee_id) FILTER (WHERE review_id IS NOT NULL) AS high_performer_share,
    count(DISTINCT employee_id) FILTER (WHERE stalled_high_performer_flag) AS stalled_high_performers,
    count(DISTINCT employee_id) FILTER (WHERE below_band_midpoint_flag) AS below_midpoint_employees,
    count(DISTINCT employee_id) FILTER (WHERE below_band_midpoint_flag) / count(DISTINCT employee_id) FILTER (WHERE compensation_id IS NOT NULL) AS below_midpoint_share,
    avg(months_since_promotion_or_hire) AS average_months,
    avg(pay_position_to_midpoint) AS average_pay_position
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_talent_snapshot')
),
skills_mv AS (
  SELECT
    MEASURE(employees_demonstrating_skill) AS employees_demonstrating_skill,
    MEASURE(high_performers_demonstrating_skill) AS high_performers_demonstrating_skill
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_talent_skills')
),
skills_direct AS (
  SELECT
    count(DISTINCT employee_id) AS employees_demonstrating_skill,
    count(DISTINCT employee_id) FILTER (WHERE top_rating_flag) AS high_performers_demonstrating_skill
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.semantic_talent_skills')
),
requisitions_mv AS (
  SELECT
    MEASURE(requisitions) AS requisitions,
    MEASURE(open_requisitions) AS open_requisitions,
    MEASURE(filled_requisitions) AS filled_requisitions,
    MEASURE(average_time_to_fill) AS average_time_to_fill,
    MEASURE(backfill_requisitions) AS backfill_requisitions,
    MEASURE(backfill_share) AS backfill_share,
    MEASURE(estimated_recruiting_cost) AS estimated_recruiting_cost
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_requisitions')
),
requisitions_direct AS (
  SELECT
    count(*) AS requisitions,
    count_if(status = 'Open') AS open_requisitions,
    count_if(filled_flag) AS filled_requisitions,
    avg(time_to_fill_days) FILTER (WHERE filled_flag) AS average_time_to_fill,
    count_if(backfill_flag) AS backfill_requisitions,
    count_if(backfill_flag) / count(*) AS backfill_share,
    sum(estimated_recruiting_cost) AS estimated_recruiting_cost
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_requisition')
),
funnel_mv AS (
  SELECT
    MEASURE(applications) AS applications,
    MEASURE(internal_applications) AS internal_applications,
    MEASURE(internal_applicant_share) AS internal_applicant_share,
    MEASURE(offers_extended) AS offers_extended,
    MEASURE(accepted_offers) AS accepted_offers,
    MEASURE(declined_offers) AS declined_offers,
    MEASURE(offer_acceptance_rate) AS offer_acceptance_rate,
    MEASURE(offer_decline_rate) AS offer_decline_rate,
    MEASURE(applied_to_screen_conversion_rate) AS screen_rate,
    MEASURE(screen_to_interview_conversion_rate) AS interview_rate,
    MEASURE(interview_to_offer_conversion_rate) AS offer_rate,
    MEASURE(offer_to_hire_conversion_rate) AS hire_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_recruiting_funnel')
),
funnel_direct AS (
  SELECT
    count(*) AS applications,
    count_if(internal_candidate_flag) AS internal_applications,
    count_if(internal_candidate_flag) / count(*) AS internal_applicant_share,
    count_if(reached_offer_flag) AS offers_extended,
    count_if(offer_outcome = 'Accepted') AS accepted_offers,
    count_if(declined_offer_flag) AS declined_offers,
    count_if(offer_outcome = 'Accepted') / nullif(count_if(reached_offer_flag), 0) AS offer_acceptance_rate,
    count_if(declined_offer_flag) / nullif(count_if(reached_offer_flag), 0) AS offer_decline_rate,
    count_if(reached_screen_flag) / count(*) AS screen_rate,
    count_if(reached_interview_flag) / nullif(count_if(reached_screen_flag), 0) AS interview_rate,
    count_if(reached_offer_flag) / nullif(count_if(reached_interview_flag), 0) AS offer_rate,
    count_if(hired_flag) / nullif(count_if(reached_offer_flag), 0) AS hire_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_application_funnel')
),
zero_denominator AS (
  SELECT
    MEASURE(offers_extended) AS offers_extended,
    MEASURE(offer_acceptance_rate) AS offer_acceptance_rate,
    MEASURE(offer_decline_rate) AS offer_decline_rate
  FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.mv_recruiting_funnel')
  WHERE current_stage = 'Applied'
),
checks AS (
  SELECT 'talent_all_measures' AS check_name, count_if(NOT (
    mv.active_employees <=> direct.active_employees AND mv.high_performers <=> direct.high_performers
    AND abs(mv.high_performer_share - direct.high_performer_share) < 1e-9
    AND mv.stalled_high_performers <=> direct.stalled_high_performers
    AND mv.below_midpoint_employees <=> direct.below_midpoint_employees
    AND abs(mv.below_midpoint_share - direct.below_midpoint_share) < 1e-9
    AND abs(mv.average_months - direct.average_months) < 1e-9
    AND (mv.average_pay_position <=> direct.average_pay_position)
  )) AS violation_count FROM talent_mv mv CROSS JOIN talent_direct direct
  UNION ALL
  SELECT 'talent_skills_all_measures', count_if(NOT (
    mv.employees_demonstrating_skill <=> direct.employees_demonstrating_skill
    AND mv.high_performers_demonstrating_skill <=> direct.high_performers_demonstrating_skill
  )) FROM skills_mv mv CROSS JOIN skills_direct direct
  UNION ALL
  SELECT 'requisitions_all_measures', count_if(NOT (
    mv.requisitions <=> direct.requisitions AND mv.open_requisitions <=> direct.open_requisitions
    AND mv.filled_requisitions <=> direct.filled_requisitions
    AND abs(mv.average_time_to_fill - direct.average_time_to_fill) < 1e-9
    AND mv.backfill_requisitions <=> direct.backfill_requisitions
    AND abs(mv.backfill_share - direct.backfill_share) < 1e-9
    AND mv.estimated_recruiting_cost <=> direct.estimated_recruiting_cost
  )) FROM requisitions_mv mv CROSS JOIN requisitions_direct direct
  UNION ALL
  SELECT 'recruiting_funnel_all_measures', count_if(NOT (
    mv.applications <=> direct.applications AND mv.internal_applications <=> direct.internal_applications
    AND abs(mv.internal_applicant_share - direct.internal_applicant_share) < 1e-9
    AND mv.offers_extended <=> direct.offers_extended AND mv.accepted_offers <=> direct.accepted_offers
    AND mv.declined_offers <=> direct.declined_offers
    AND abs(mv.offer_acceptance_rate - direct.offer_acceptance_rate) < 1e-9
    AND abs(mv.offer_decline_rate - direct.offer_decline_rate) < 1e-9
    AND abs(mv.screen_rate - direct.screen_rate) < 1e-9
    AND abs(mv.interview_rate - direct.interview_rate) < 1e-9
    AND abs(mv.offer_rate - direct.offer_rate) < 1e-9
    AND abs(mv.hire_rate - direct.hire_rate) < 1e-9
  )) FROM funnel_mv mv CROSS JOIN funnel_direct direct
  UNION ALL
  SELECT 'recruiting_zero_denominator', count_if(
    offers_extended <> 0 OR offer_acceptance_rate IS NOT NULL OR offer_decline_rate IS NOT NULL
  ) FROM zero_denominator
  UNION ALL
  SELECT 'recruiting_internal_job_temporal_match', count_if(
    internal_candidate_flag AND internal_applicant_job_code IS NULL
  ) FROM IDENTIFIER(:catalog || '.' || :gold_schema || '.fact_application_funnel')
)
SELECT
  check_name,
  violation_count,
  CASE WHEN violation_count = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_name;
