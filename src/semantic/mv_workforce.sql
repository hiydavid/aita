EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_workforce` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.semantic_workforce_monthly
comment: "Monthly workforce metrics with semi-additive period-end headcount and grain-safe attrition rates."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.org_unit_id = dim_org.org_unit_id
  - name: dim_job
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_job
    "on": source.job_code = dim_job.job_code
dimensions:
  - name: month
    expr: source.month_start
    comment: "First date of the workforce reporting month."
    display_name: "Month"
    synonyms: [reporting_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.month_start)"
    comment: "First date of the calendar quarter."
    display_name: "Quarter"
    synonyms: [calendar_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.month_start)
    comment: "Calendar year of the reporting month."
    display_name: "Year"
    synonyms: [calendar_year]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Stable organization-unit identifier."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Business-friendly organization-unit name."
    display_name: "Organization Unit"
    synonyms: [team, branch, contact_center]
  - name: org_type
    expr: dim_org.org_type
    comment: "Organization hierarchy type."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: dim_org.business_line
    comment: "Top-level bank business line."
    display_name: "Business Line"
    synonyms: [division]
  - name: region
    expr: dim_org.region
    comment: "Geographic region of the organization unit."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: dim_org.location
    comment: "Primary work location of the organization unit."
    display_name: "Location"
    synonyms: [site]
  - name: job_code
    expr: source.job_code
    comment: "Stable job-code identifier."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_family
    expr: dim_job.job_family
    comment: "Job family used for workforce comparisons."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: dim_job.job_level
    comment: "Career level assigned to the job."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: dim_job.licensed_role_flag
    comment: "Whether the role requires a professional license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: dim_job.strategic_role_flag
    comment: "Whether the role is strategically designated."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: dim_job.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
measures:
  - name: period_end_headcount
    expr: SUM(source.headcount_eom)
    comment: "Active employees at the latest selected month end; semi-additive over time."
    display_name: "Period-End Headcount"
    synonyms: [ending_headcount, headcount]
    format: {type: number, decimal_places: {type: exact, places: 0}}
    window:
      - order: month
        range: current
        semiadditive: last
  - name: average_monthly_headcount
    expr: "SUM(source.headcount_eom) / NULLIF(COUNT(DISTINCT source.month_start), 0)"
    comment: "Sum of monthly headcount divided by distinct selected months."
    display_name: "Average Monthly Headcount"
    synonyms: [average_headcount]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: hires
    expr: SUM(source.hire_count)
    comment: "Hire events during the selected period."
    display_name: "Hires"
    synonyms: [new_hires]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: exits
    expr: SUM(source.exit_count)
    comment: "Voluntary and involuntary exits during the selected period."
    display_name: "Exits"
    synonyms: [leavers]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: voluntary_exits
    expr: SUM(source.voluntary_exit_count)
    comment: "Voluntary exits during the selected period."
    display_name: "Voluntary Exits"
    synonyms: [voluntary_leavers]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: regrettable_voluntary_exits
    expr: SUM(source.regrettable_voluntary_exit_count)
    comment: "Voluntary exits whose latest performance rating was 4 or 5."
    display_name: "Regrettable Voluntary Exits"
    synonyms: [regrettable_exits]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: voluntary_attrition_rate
    expr: "MEASURE(voluntary_exits) / NULLIF(MEASURE(average_monthly_headcount), 0)"
    comment: "Voluntary exits divided by average monthly headcount."
    display_name: "Voluntary Attrition Rate"
    synonyms: [turnover_rate, attrition_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
  - name: regrettable_attrition_rate
    expr: "MEASURE(regrettable_voluntary_exits) / NULLIF(MEASURE(average_monthly_headcount), 0)"
    comment: "Regrettable voluntary exits divided by average monthly headcount."
    display_name: "Regrettable Attrition Rate"
    synonyms: [regrettable_turnover_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
