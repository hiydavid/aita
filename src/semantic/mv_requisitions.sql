EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_requisitions` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.fact_requisition
comment: "Requisition volume, status, time-to-fill, backfill, and estimated recruiting-cost metrics."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.org_unit_id = dim_org.org_unit_id
  - name: dim_job
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_job
    "on": source.job_code = dim_job.job_code
dimensions:
  - name: open_date
    expr: source.open_date
    comment: "Date the requisition opened."
    display_name: "Open Date"
    synonyms: [requisition_open_date]
    format: {type: date, date_format: year_month_day}
  - name: month
    expr: "DATE_TRUNC(\'MONTH\', source.open_date)"
    comment: "First date of the requisition-open month."
    display_name: "Month"
    synonyms: [open_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.open_date)"
    comment: "First date of the requisition-open quarter."
    display_name: "Quarter"
    synonyms: [open_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.open_date)
    comment: "Calendar year the requisition opened."
    display_name: "Year"
    synonyms: [open_year]
  - name: close_date
    expr: source.close_date
    comment: "Date the requisition closed; null while open."
    display_name: "Close Date"
    synonyms: [requisition_close_date]
    format: {type: date, date_format: year_month_day}
  - name: requisition_type
    expr: source.requisition_type
    comment: "Backfill or new-position hiring demand type."
    display_name: "Requisition Type"
    synonyms: [req_type]
  - name: status
    expr: source.status
    comment: "Current requisition status."
    display_name: "Requisition Status"
    synonyms: [req_status]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Hiring organization-unit identifier."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Hiring organization-unit name."
    display_name: "Organization Unit"
    synonyms: [team, branch, contact_center]
  - name: org_type
    expr: dim_org.org_type
    comment: "Hiring organization hierarchy type."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: dim_org.business_line
    comment: "Hiring top-level bank business line."
    display_name: "Business Line"
    synonyms: [division]
  - name: region
    expr: dim_org.region
    comment: "Geographic region of the hiring unit."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: dim_org.location
    comment: "Primary location of the hiring unit."
    display_name: "Location"
    synonyms: [site]
  - name: job_code
    expr: source.job_code
    comment: "Requested stable job-code identifier."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_title
    expr: dim_job.job_title
    comment: "Requested business-friendly job title."
    display_name: "Job Title"
    synonyms: [role_title]
  - name: job_family
    expr: dim_job.job_family
    comment: "Requested job family."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: dim_job.job_level
    comment: "Requested career level."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: source.licensed_role_flag
    comment: "Whether the requested role requires a license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: dim_job.strategic_role_flag
    comment: "Whether the requested role is strategic."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: dim_job.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the requested role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
measures:
  - name: requisitions
    expr: COUNT(1)
    comment: "Requisitions in the selected population."
    display_name: "Requisitions"
    synonyms: [reqs]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: open_requisitions
    expr: COUNT(1) FILTER (WHERE source.status = \'Open\')
    comment: "Requisitions whose current status is Open."
    display_name: "Open Requisitions"
    synonyms: [open_reqs]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: filled_requisitions
    expr: COUNT(1) FILTER (WHERE source.filled_flag)
    comment: "Requisitions whose current status is Filled."
    display_name: "Filled Requisitions"
    synonyms: [filled_reqs]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: average_time_to_fill
    expr: AVG(source.time_to_fill_days) FILTER (WHERE source.filled_flag)
    comment: "Average calendar days to fill for filled requisitions only."
    display_name: "Average Time to Fill"
    synonyms: [average_ttf]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: backfill_requisitions
    expr: COUNT(1) FILTER (WHERE source.backfill_flag)
    comment: "Requisitions opened to replace departing employees."
    display_name: "Backfill Requisitions"
    synonyms: [backfill_reqs]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: backfill_share
    expr: "MEASURE(backfill_requisitions) / NULLIF(MEASURE(requisitions), 0)"
    comment: "Backfill requisitions divided by all requisitions."
    display_name: "Backfill Share"
    synonyms: [backfill_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
  - name: estimated_recruiting_cost
    expr: SUM(source.estimated_recruiting_cost)
    comment: "Estimated recruiting cost in US dollars."
    display_name: "Estimated Recruiting Cost"
    synonyms: [hiring_cost]
    format: {type: currency, currency_code: USD, decimal_places: {type: max, places: 2}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
