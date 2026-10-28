WITH
workers AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/workers',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
job_history AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/job_history',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
org_units AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/org_units',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
jobs AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/jobs',
    format => 'json'
  )
),
engagement_surveys AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/engagement_surveys',
    format => 'json'
  )
),
exit_interviews AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/exit_interviews',
    format => 'json'
  )
),
team_productivity AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/team_productivity',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
performance_reviews AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/performance_reviews',
    format => 'json'
  )
),
compensation AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/compensation',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
requisitions AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/requisitions',
    format => 'csv',
    header => true,
    inferSchema => true
  )
),
applications AS (
  SELECT *
  FROM read_files(
    '/Volumes/genie_workbench_dev_catalog/aita_bronze/landing/applications',
    format => 'json'
  )
),
population_stats AS (
  SELECT
    COUNT(*) AS company_worker_count,
    COUNT_IF(org_unit_id IN ('ORG001', 'ORG002')) AS center_worker_count,
    COUNT_IF(termination_date IS NOT NULL) / COUNT(*) AS company_attrition_rate
  FROM workers
),
exit_stats AS (
  SELECT
    COUNT(*) AS company_exit_count,
    COUNT_IF(org_unit_id IN ('ORG001', 'ORG002')) AS center_exit_count,
    COUNT_IF(
      org_unit_id IN ('ORG001', 'ORG002')
        AND manager_id IN ('EMP000001', 'EMP000073', 'EMP000002')
    ) AS target_manager_exits
  FROM job_history
  WHERE event_type = 'EXIT'
    AND TO_DATE(event_date) BETWEEN DATE '2026-02-01' AND DATE '2026-05-31'
),
contact_center_comments AS (
  SELECT
    COUNT(*) AS interview_count,
    COUNT_IF(LOWER(exit_comment) RLIKE 'schedule|workload') AS schedule_comment_count
  FROM exit_interviews
  WHERE org_unit_id IN ('ORG001', 'ORG002')
    AND TO_DATE(exit_date) BETWEEN DATE '2026-02-01' AND DATE '2026-05-31'
),
attrition_pattern AS (
  SELECT
    es.center_exit_count / NULLIF(ps.center_worker_count, 0) AS center_exit_rate,
    es.company_exit_count / NULLIF(ps.company_worker_count, 0) AS company_exit_rate,
    es.target_manager_exits / NULLIF(es.center_exit_count, 0) AS target_manager_share,
    ccc.schedule_comment_count / NULLIF(ccc.interview_count, 0) AS schedule_comment_share,
    es.center_exit_count AS center_exits
  FROM exit_stats es
  CROSS JOIN population_stats ps
  CROSS JOIN contact_center_comments ccc
),
promotions AS (
  SELECT worker_id, MAX(TO_DATE(event_date)) AS last_promotion_date
  FROM job_history
  WHERE event_type = 'PROMOTION'
  GROUP BY worker_id
),
stalled_talent AS (
  SELECT COUNT(DISTINCT w.worker_id) AS worker_count
  FROM workers w
  INNER JOIN jobs j ON w.job_code = j.job_code
  INNER JOIN performance_reviews p
    ON w.worker_id = p.worker_id AND p.review_year = 2026
  INNER JOIN compensation c
    ON w.worker_id = c.worker_id AND c.compensation_year = 2026
  LEFT JOIN promotions pr ON w.worker_id = pr.worker_id
  WHERE j.strategic_role_flag = true
    AND p.performance_rating = 'Exceeds Expectations'
    AND p.potential_rating = 'High'
    AND c.base_salary < c.band_mid * 0.95
    AND DATEDIFF(DATE '2026-09-30', TO_DATE(w.hire_date)) >= 1095
    AND (pr.last_promotion_date IS NULL OR pr.last_promotion_date < DATE '2023-10-01')
),
fraud_engagement AS (
  SELECT
    AVG(CASE WHEN TO_DATE(survey_date) <= DATE '2025-03-15' THEN engagement_score END) AS early_score,
    AVG(CASE WHEN TO_DATE(survey_date) >= DATE '2026-06-15' THEN engagement_score END) AS late_score,
    AVG(
      CASE
        WHEN TO_DATE(survey_date) >= DATE '2026-06-15'
          THEN IF(LOWER(comment) RLIKE 'burnout|overtime|workload', 1.0, 0.0)
      END
    ) AS burnout_comment_share
  FROM engagement_surveys
  WHERE org_unit_id IN ('ORG037', 'ORG038')
),
fraud_productivity AS (
  SELECT
    AVG(CASE WHEN TO_DATE(month) <= DATE '2025-03-01' THEN overtime_hours END) AS early_overtime,
    AVG(CASE WHEN TO_DATE(month) >= DATE '2026-04-01' THEN overtime_hours END) AS late_overtime
  FROM team_productivity
  WHERE team_id IN ('ORG037', 'ORG038')
),
team_engagement AS (
  SELECT org_unit_id, AVG(engagement_score) AS avg_engagement
  FROM engagement_surveys
  GROUP BY org_unit_id
),
team_performance AS (
  SELECT team_id, AVG(csat_score) AS avg_csat
  FROM team_productivity
  GROUP BY team_id
),
team_attrition AS (
  SELECT
    org_unit_id,
    COUNT_IF(termination_date IS NOT NULL) / COUNT(*) AS attrition_rate
  FROM workers
  GROUP BY org_unit_id
),
standout_managers AS (
  SELECT COUNT(*) AS manager_count
  FROM org_units o
  INNER JOIN team_engagement e ON o.org_unit_id = e.org_unit_id
  INNER JOIN team_performance p ON o.org_unit_id = p.team_id
  INNER JOIN team_attrition a ON o.org_unit_id = a.org_unit_id
  CROSS JOIN population_stats ps
  WHERE o.standout_manager_flag = true
    AND e.avg_engagement >= 4.4
    AND p.avg_csat >= 4.6
    AND a.attrition_rate < ps.company_attrition_rate * 0.5
),
genai_internal_mobility AS (
  SELECT COUNT(DISTINCT a.application_id) AS application_count
  FROM applications a
  INNER JOIN workers w ON a.internal_worker_id = w.worker_id
  INNER JOIN jobs source_job ON w.job_code = source_job.job_code
  INNER JOIN requisitions r ON a.requisition_id = r.requisition_id
  INNER JOIN jobs target_job ON r.job_code = target_job.job_code
  WHERE a.source = 'Internal'
    AND w.business_line = 'Operations'
    AND source_job.expected_genai_exposure_tier = 'high'
    AND target_job.business_line = 'Technology'
    AND LOWER(a.candidate_summary) RLIKE 'sql|data quality|automation'
),
licensed_fill AS (
  SELECT
    AVG(CASE WHEN licensed_role_flag = true THEN DATEDIFF(TO_DATE(close_date), TO_DATE(open_date)) END) AS licensed_days,
    AVG(CASE WHEN licensed_role_flag = false THEN DATEDIFF(TO_DATE(close_date), TO_DATE(open_date)) END) AS other_days
  FROM requisitions
  WHERE status = 'Filled'
),
licensed_declines AS (
  SELECT
    COUNT(*) AS decline_count,
    COUNT_IF(LOWER(a.offer_decline_comment) RLIKE 'compensation|competing offer') AS market_decline_count
  FROM applications a
  INNER JOIN requisitions r ON a.requisition_id = r.requisition_id
  WHERE r.licensed_role_flag = true
    AND a.offer_outcome = 'Declined'
),
licensed_hiring AS (
  SELECT
    lf.licensed_days,
    lf.other_days,
    ld.market_decline_count / NULLIF(ld.decline_count, 0) AS market_decline_share
  FROM licensed_fill lf
  CROSS JOIN licensed_declines ld
),
backfill_counts AS (
  SELECT
    COUNT_IF(TO_DATE(open_date) BETWEEN DATE '2026-03-01' AND DATE '2026-06-30') AS post_count,
    COUNT_IF(TO_DATE(open_date) BETWEEN DATE '2025-03-01' AND DATE '2025-06-30') AS baseline_count
  FROM requisitions
  WHERE org_unit_id IN ('ORG001', 'ORG002')
    AND requisition_type = 'Backfill'
),
linked_backfills AS (
  SELECT COUNT(DISTINCT r.requisition_id) AS requisition_count
  FROM requisitions r
  INNER JOIN job_history h
    ON r.org_unit_id = h.org_unit_id
    AND h.event_type = 'EXIT'
    AND TO_DATE(h.event_date) BETWEEN DATE_SUB(TO_DATE(r.open_date), 90) AND TO_DATE(r.open_date)
  WHERE r.org_unit_id IN ('ORG001', 'ORG002')
    AND r.requisition_type = 'Backfill'
    AND TO_DATE(r.open_date) BETWEEN DATE '2026-03-01' AND DATE '2026-06-30'
),
backfill_pattern AS (
  SELECT
    b.post_count,
    b.baseline_count,
    l.requisition_count / NULLIF(b.post_count, 0) AS linked_share
  FROM backfill_counts b
  CROSS JOIN linked_backfills l
)
SELECT
  '01_contact_center_attrition' AS check_name,
  IF(
    center_exit_rate >= company_exit_rate * 2
      AND target_manager_share >= 0.60
      AND schedule_comment_share >= 0.60,
    'PASS',
    'FAIL'
  ) AS status,
  ROUND(center_exit_rate, 4) AS primary_metric,
  ROUND(company_exit_rate, 4) AS comparison_metric,
  CONCAT(
    'spike_exits=', center_exits,
    '; target_manager_share=', ROUND(target_manager_share, 3),
    '; schedule_comment_share=', ROUND(schedule_comment_share, 3)
  ) AS evidence
FROM attrition_pattern
UNION ALL
SELECT
  '02_stalled_high_performers',
  IF(worker_count >= 100, 'PASS', 'FAIL'),
  worker_count,
  100,
  'Strategic high performers below midpoint with 3+ years and no recent promotion'
FROM stalled_talent
UNION ALL
SELECT
  '03_fraud_operations_burnout',
  IF(
    early_score - late_score >= 1.0
      AND late_overtime >= early_overtime * 1.8
      AND burnout_comment_share >= 0.80,
    'PASS',
    'FAIL'
  ),
  ROUND(early_score - late_score, 3),
  ROUND(late_overtime / NULLIF(early_overtime, 0), 3),
  CONCAT(
    'engagement_early=', ROUND(early_score, 2),
    '; engagement_late=', ROUND(late_score, 2),
    '; burnout_comment_share=', ROUND(burnout_comment_share, 3)
  )
FROM fraud_engagement
CROSS JOIN fraud_productivity
UNION ALL
SELECT
  '04_standout_managers',
  IF(manager_count >= 3, 'PASS', 'FAIL'),
  manager_count,
  3,
  'Managers whose teams combine high engagement, high CSAT, and less than half company attrition'
FROM standout_managers
UNION ALL
SELECT
  '05_genai_internal_mobility',
  IF(application_count >= 400, 'PASS', 'FAIL'),
  application_count,
  400,
  'Internal operations candidates from GenAI-exposed roles applying to technology roles with adjacent skills'
FROM genai_internal_mobility
UNION ALL
SELECT
  '06_licensed_role_hiring',
  IF(
    licensed_days >= other_days * 1.8 AND market_decline_share >= 0.80,
    'PASS',
    'FAIL'
  ),
  ROUND(licensed_days / NULLIF(other_days, 0), 3),
  ROUND(market_decline_share, 3),
  CONCAT(
    'licensed_avg_days=', ROUND(licensed_days, 1),
    '; other_avg_days=', ROUND(other_days, 1)
  )
FROM licensed_hiring
UNION ALL
SELECT
  '07_contact_center_backfills',
  IF(post_count >= baseline_count * 5 AND linked_share >= 0.80, 'PASS', 'FAIL'),
  post_count,
  baseline_count,
  CONCAT('backfills_linked_to_prior_90_day_exit=', ROUND(linked_share, 3))
FROM backfill_pattern
ORDER BY check_name;
