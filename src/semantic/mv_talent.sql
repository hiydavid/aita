EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_talent` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.semantic_talent_snapshot
comment: "Current active-employee talent metrics using latest performance, compensation, and promotion context."
dimensions:
  - name: as_of_date
    expr: source.as_of_date
    comment: "Business date of the current talent snapshot."
    display_name: "As-of Date"
    synonyms: [snapshot_date]
    format: {type: date, date_format: year_month_day}
  - name: month
    expr: "DATE_TRUNC(\'MONTH\', source.as_of_date)"
    comment: "First date of the snapshot calendar month."
    display_name: "Month"
    synonyms: [snapshot_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.as_of_date)"
    comment: "First date of the snapshot calendar quarter."
    display_name: "Quarter"
    synonyms: [snapshot_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.as_of_date)
    comment: "Calendar year of the talent snapshot."
    display_name: "Year"
    synonyms: [snapshot_year]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Current organization-unit identifier."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: source.org_unit_name
    comment: "Current organization-unit name."
    display_name: "Organization Unit"
    synonyms: [team, branch]
  - name: org_type
    expr: source.org_type
    comment: "Current organization hierarchy type."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: source.business_line
    comment: "Current top-level bank business line."
    display_name: "Business Line"
    synonyms: [division]
  - name: region
    expr: source.region
    comment: "Current geographic region."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: source.location
    comment: "Current primary work location."
    display_name: "Location"
    synonyms: [site]
  - name: job_code
    expr: source.job_code
    comment: "Current stable job-code identifier."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_title
    expr: source.job_title
    comment: "Current business-friendly job title."
    display_name: "Job Title"
    synonyms: [role_title]
  - name: job_family
    expr: source.job_family
    comment: "Current job family."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: source.job_level
    comment: "Current career level."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: source.licensed_role_flag
    comment: "Whether the current role requires a license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: source.strategic_role_flag
    comment: "Whether the current role is strategic."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: source.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the current role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
  - name: manager_id
    expr: source.manager_id
    comment: "Current manager employee identifier."
    display_name: "Manager ID"
    synonyms: [supervisor_id]
  - name: tenure_band
    expr: source.tenure_band
    comment: "Current employee tenure band."
    display_name: "Tenure Band"
    synonyms: [service_band]
  - name: performance_rating
    expr: source.performance_rating
    comment: "Latest performance-review outcome."
    display_name: "Performance Rating"
    synonyms: [latest_rating]
  - name: potential_rating
    expr: source.potential_rating
    comment: "Latest assessed employee potential."
    display_name: "Potential Rating"
    synonyms: [talent_potential]
  - name: pay_position_band
    expr: source.pay_position_band
    comment: "Non-sensitive latest pay-position category."
    display_name: "Pay Position Band"
    synonyms: [compa_band]
measures:
  - name: active_employees
    expr: COUNT(DISTINCT source.employee_id)
    comment: "Active employees in the current snapshot."
    display_name: "Active Employees"
    synonyms: [current_employees]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: employees_with_latest_review
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.review_id IS NOT NULL)
    comment: "Active employees with a latest performance review."
    display_name: "Employees with Latest Review"
    synonyms: [reviewed_employees]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: high_performers
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.top_rating_flag)
    comment: "Active employees whose latest rating_numeric equals 5."
    display_name: "High Performers"
    synonyms: [top_talent]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: high_performer_share
    expr: "MEASURE(high_performers) / NULLIF(MEASURE(employees_with_latest_review), 0)"
    comment: "High performers divided by active employees with a latest review."
    display_name: "High-Performer Share"
    synonyms: [top_talent_share]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
  - name: stalled_high_performers
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.stalled_high_performer_flag)
    comment: "High performers below midpoint without a promotion in at least 36 months."
    display_name: "Stalled High Performers"
    synonyms: [overlooked_high_performers]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: employees_with_latest_compensation
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.compensation_id IS NOT NULL)
    comment: "Active employees with a latest compensation record."
    display_name: "Employees with Latest Compensation"
    synonyms: [compensated_employees]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: below_midpoint_employees
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.below_band_midpoint_flag)
    comment: "Active employees whose latest base salary is below band midpoint."
    display_name: "Below-Midpoint Employees"
    synonyms: [below_band_midpoint]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: below_midpoint_share
    expr: "MEASURE(below_midpoint_employees) / NULLIF(MEASURE(employees_with_latest_compensation), 0)"
    comment: "Below-midpoint employees divided by employees with latest compensation."
    display_name: "Below-Midpoint Share"
    synonyms: [below_midpoint_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
  - name: average_months_since_promotion_or_hire
    expr: AVG(source.months_since_promotion_or_hire)
    comment: "Average months since latest promotion, or hire when never promoted."
    display_name: "Average Months Since Promotion or Hire"
    synonyms: [average_career_movement_age]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: average_pay_position_to_midpoint
    expr: AVG(source.pay_position_to_midpoint)
    comment: "Average latest base-salary position to midpoint; masked to NULL for unauthorized users."
    display_name: "Average Pay Position to Midpoint"
    synonyms: [average_compa_ratio]
    format: {type: number, decimal_places: {type: max, places: 3}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
