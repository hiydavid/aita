-- benchmark: 42000000000000000000000000000001
SELECT employee_id, employee_name, job_title, job_level, business_line,
  months_since_promotion_or_hire, as_of_date
FROM ${catalog}.${gold_schema}.semantic_talent_snapshot
WHERE rating_numeric = 5 AND job_level IN ('Senior', 'Lead', 'Manager', 'Director')
  AND months_since_promotion_or_hire >= 36
ORDER BY months_since_promotion_or_hire DESC, employee_id LIMIT 100;

-- benchmark: 42000000000000000000000000000002
SELECT MEASURE(talent.below_midpoint_share) AS below_midpoint_share,
  MEASURE(talent.below_midpoint_employees) AS below_midpoint_employees,
  MEASURE(talent.employees_with_latest_compensation) AS employees_with_compensation
FROM ${catalog}.${gold_schema}.mv_talent AS talent
WHERE talent.strategic_role_flag = true AND talent.performance_rating = 'Exceeds Expectations';

-- benchmark: 42000000000000000000000000000003
SELECT talent.genai_exposure_tier, talent.job_family,
  MEASURE(talent.active_employees) AS active_employees
FROM ${catalog}.${gold_schema}.mv_talent AS talent
GROUP BY ALL ORDER BY talent.genai_exposure_tier, active_employees DESC;

-- benchmark: 42000000000000000000000000000004
SELECT skills.demonstrated_skill,
  MEASURE(skills.high_performers_demonstrating_skill) AS high_performers
FROM ${catalog}.${gold_schema}.mv_talent_skills AS skills
WHERE skills.business_line = 'Technology'
GROUP BY ALL ORDER BY high_performers DESC LIMIT 20;

-- benchmark: 42000000000000000000000000000005
SELECT talent.business_line, MEASURE(talent.high_performer_share) AS high_performer_share,
  MEASURE(talent.high_performers) AS high_performers,
  MEASURE(talent.employees_with_latest_review) AS employees_with_review
FROM ${catalog}.${gold_schema}.mv_talent AS talent
GROUP BY ALL ORDER BY high_performer_share DESC;

-- benchmark: 42000000000000000000000000000006
SELECT talent.job_family, MEASURE(talent.below_midpoint_share) AS below_midpoint_share,
  MEASURE(talent.employees_with_latest_compensation) AS employees_with_compensation
FROM ${catalog}.${gold_schema}.mv_talent AS talent
GROUP BY ALL ORDER BY below_midpoint_share DESC LIMIT 20;

-- benchmark: 42000000000000000000000000000007
SELECT talent.job_family,
  MEASURE(talent.average_months_since_promotion_or_hire) AS average_months
FROM ${catalog}.${gold_schema}.mv_talent AS talent
WHERE talent.strategic_role_flag = true
GROUP BY ALL ORDER BY average_months DESC;

-- benchmark: 42000000000000000000000000000008
SELECT employee_id, employee_name, job_title, business_line, performance_rating,
  risk_flags, risk_reasons, as_of_date
FROM ${catalog}.${gold_schema}.semantic_talent_snapshot
WHERE rating_numeric = 5 AND watchlist_flag
ORDER BY business_line, employee_id LIMIT 100;

-- benchmark: 42000000000000000000000000000009
WITH potential_counts AS (
  SELECT talent.job_level, talent.potential_rating,
    MEASURE(talent.active_employees) AS employees
  FROM ${catalog}.${gold_schema}.mv_talent AS talent
  WHERE talent.potential_rating IS NOT NULL GROUP BY ALL
)
SELECT job_level, sum(CASE WHEN potential_rating = 'High' THEN employees ELSE 0 END) AS high_potential_employees,
  sum(employees) AS rated_employees,
  sum(CASE WHEN potential_rating = 'High' THEN employees ELSE 0 END) / nullif(sum(employees), 0) AS high_potential_share
FROM potential_counts GROUP BY job_level ORDER BY high_potential_share DESC;

-- benchmark: 42000000000000000000000000000010
SELECT skills.demonstrated_skill,
  MEASURE(skills.employees_demonstrating_skill) AS employees
FROM ${catalog}.${gold_schema}.mv_talent_skills AS skills
WHERE skills.genai_exposure_tier = 'high'
GROUP BY ALL ORDER BY employees DESC LIMIT 20;
