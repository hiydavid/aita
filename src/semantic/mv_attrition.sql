EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_attrition` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.fact_attrition_event
comment: "Exit-event metrics with historical organization, job, manager, and AI-classified exit signals."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.org_unit_id = dim_org.org_unit_id
  - name: dim_job
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_job
    "on": source.job_code = dim_job.job_code
dimensions:
  - name: exit_date
    expr: source.exit_date
    comment: "Effective date of the employee exit."
    display_name: "Exit Date"
    synonyms: [termination_date]
    format: {type: date, date_format: year_month_day}
  - name: month
    expr: source.exit_month
    comment: "First date of the exit calendar month."
    display_name: "Month"
    synonyms: [exit_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.exit_date)"
    comment: "First date of the exit calendar quarter."
    display_name: "Quarter"
    synonyms: [exit_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.exit_date)
    comment: "Calendar year of the exit."
    display_name: "Year"
    synonyms: [exit_year]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Organization-unit identifier at exit."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Organization-unit name at exit."
    display_name: "Organization Unit"
    synonyms: [team, branch, contact_center]
  - name: org_type
    expr: dim_org.org_type
    comment: "Organization hierarchy type at exit."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: dim_org.business_line
    comment: "Business line at exit."
    display_name: "Business Line"
    synonyms: [division]
  - name: region
    expr: dim_org.region
    comment: "Geographic region at exit."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: dim_org.location
    comment: "Primary organization location at exit."
    display_name: "Location"
    synonyms: [site]
  - name: job_code
    expr: source.job_code
    comment: "Job-code identifier at exit."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_family
    expr: dim_job.job_family
    comment: "Job family at exit."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: dim_job.job_level
    comment: "Career level at exit."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: source.licensed_role_flag
    comment: "Whether the role at exit required a license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: source.strategic_role_flag
    comment: "Whether the role at exit was strategic."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: dim_job.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the exited role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
  - name: manager_id
    expr: source.manager_id
    comment: "Manager identifier recorded at exit."
    display_name: "Manager ID"
    synonyms: [supervisor_id]
  - name: tenure_band
    expr: "CASE WHEN source.tenure_days < 365 THEN \'Under 1 year\' WHEN source.tenure_days < 1095 THEN \'1-2 years\' WHEN source.tenure_days < 1826 THEN \'3-4 years\' ELSE \'5+ years\' END"
    comment: "Employee tenure band at exit."
    display_name: "Tenure Band"
    synonyms: [service_band]
  - name: termination_type
    expr: source.termination_type
    comment: "Voluntary or involuntary exit classification."
    display_name: "Termination Type"
    synonyms: [exit_type]
  - name: exit_reason
    expr: source.exit_reason
    comment: "AI-classified reason from exit-interview text."
    display_name: "AI-Classified Exit Reason"
    synonyms: [departure_reason]
  - name: exit_sentiment
    expr: source.exit_sentiment
    comment: "AI-analyzed sentiment from exit-interview text."
    display_name: "Exit Sentiment"
    synonyms: [departure_sentiment]
measures:
  - name: exits
    expr: COUNT(1)
    comment: "Voluntary and involuntary exit events."
    display_name: "Exits"
    synonyms: [leavers]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: voluntary_exits
    expr: COUNT(1) FILTER (WHERE source.is_voluntary)
    comment: "Exit events classified as voluntary."
    display_name: "Voluntary Exits"
    synonyms: [voluntary_leavers]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: regrettable_exits
    expr: COUNT(1) FILTER (WHERE source.regrettable_flag)
    comment: "Exits where the latest performance rating was 4 or 5."
    display_name: "Regrettable Exits"
    synonyms: [high_value_exits]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: regrettable_voluntary_exits
    expr: COUNT(1) FILTER (WHERE source.is_voluntary AND source.regrettable_flag)
    comment: "Voluntary exits where the latest performance rating was 4 or 5."
    display_name: "Regrettable Voluntary Exits"
    synonyms: [regrettable_turnover]
    format: {type: number, decimal_places: {type: exact, places: 0}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
