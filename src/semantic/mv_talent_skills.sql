EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_talent_skills` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.semantic_talent_skills
comment: "Current active-employee counts by normalized AI-extracted demonstrated skill."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.org_unit_id = dim_org.org_unit_id
  - name: dim_job
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_job
    "on": source.job_code = dim_job.job_code
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
  - name: demonstrated_skill
    expr: source.demonstrated_skill
    comment: "Normalized AI-extracted skill from the latest review."
    display_name: "AI-Extracted Demonstrated Skill"
    synonyms: [skill, competency]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Current organization-unit identifier."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Current organization-unit name."
    display_name: "Organization Unit"
    synonyms: [team, branch]
  - name: org_type
    expr: dim_org.org_type
    comment: "Current organization hierarchy type."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: dim_org.business_line
    comment: "Current top-level bank business line."
    display_name: "Business Line"
    synonyms: [division]
  - name: region
    expr: dim_org.region
    comment: "Current geographic region."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: dim_org.location
    comment: "Current primary work location."
    display_name: "Location"
    synonyms: [site]
  - name: job_code
    expr: source.job_code
    comment: "Current stable job-code identifier."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_family
    expr: dim_job.job_family
    comment: "Current job family."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: dim_job.job_level
    comment: "Current career level."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: dim_job.licensed_role_flag
    comment: "Whether the current role requires a license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: dim_job.strategic_role_flag
    comment: "Whether the current role is strategic."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: dim_job.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the current role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
measures:
  - name: employees_demonstrating_skill
    expr: COUNT(DISTINCT source.employee_id)
    comment: "Active employees demonstrating the selected AI-extracted skill."
    display_name: "Employees Demonstrating Skill"
    synonyms: [employees_with_skill]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: high_performers_demonstrating_skill
    expr: COUNT(DISTINCT source.employee_id) FILTER (WHERE source.top_rating_flag)
    comment: "High performers demonstrating the selected AI-extracted skill."
    display_name: "High Performers Demonstrating Skill"
    synonyms: [top_talent_with_skill]
    format: {type: number, decimal_places: {type: exact, places: 0}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
