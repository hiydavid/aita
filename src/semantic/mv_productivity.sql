EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_productivity` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.fact_productivity
comment: "Team-month productivity, overtime, service, and quality metrics with case-weighted averages."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.team_id = dim_org.org_unit_id
dimensions:
  - name: month
    expr: source.month_start
    comment: "First date of the productivity reporting month."
    display_name: "Month"
    synonyms: [reporting_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.month_start)"
    comment: "First date of the productivity calendar quarter."
    display_name: "Quarter"
    synonyms: [calendar_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.month_start)
    comment: "Calendar year of the productivity month."
    display_name: "Year"
    synonyms: [calendar_year]
  - name: org_unit_id
    expr: source.team_id
    comment: "Team organization-unit identifier."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Business-friendly team or organization-unit name."
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
    comment: "Geographic region of the team."
    display_name: "Region"
    synonyms: [geography]
  - name: location
    expr: dim_org.location
    comment: "Primary work location of the team."
    display_name: "Location"
    synonyms: [site]
measures:
  - name: cases_handled
    expr: SUM(source.cases_handled)
    comment: "Cases completed by teams in the selected period."
    display_name: "Cases Handled"
    synonyms: [case_volume]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: overtime_hours
    expr: SUM(source.overtime_hours)
    comment: "Total team overtime hours in the selected period."
    display_name: "Overtime Hours"
    synonyms: [overtime]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: team_months
    expr: COUNT(1)
    comment: "Team-month rows in the selected population."
    display_name: "Team-Months"
    synonyms: [reporting_team_months]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: average_overtime_hours_per_team_month
    expr: "MEASURE(overtime_hours) / NULLIF(MEASURE(team_months), 0)"
    comment: "Overtime hours divided by selected team-months."
    display_name: "Average Overtime Hours per Team-Month"
    synonyms: [average_overtime]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: csat_case_points
    expr: SUM(source.csat_score * source.cases_handled)
    comment: "Supporting case-weighted CSAT numerator."
    display_name: "CSAT Case Points"
    synonyms: [weighted_csat_points]
  - name: handle_time_case_minutes
    expr: SUM(source.avg_handle_time_minutes * source.cases_handled)
    comment: "Supporting case-weighted handle-time numerator."
    display_name: "Handle-Time Case Minutes"
    synonyms: [weighted_handle_time_minutes]
  - name: quality_case_points
    expr: SUM(source.quality_score * source.cases_handled)
    comment: "Supporting case-weighted quality numerator."
    display_name: "Quality Case Points"
    synonyms: [weighted_quality_points]
  - name: case_weighted_csat
    expr: "MEASURE(csat_case_points) / NULLIF(MEASURE(cases_handled), 0)"
    comment: "CSAT weighted by cases handled."
    display_name: "Case-Weighted CSAT"
    synonyms: [weighted_csat]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: case_weighted_average_handle_time
    expr: "MEASURE(handle_time_case_minutes) / NULLIF(MEASURE(cases_handled), 0)"
    comment: "Average handle minutes weighted by cases handled."
    display_name: "Case-Weighted Average Handle Time"
    synonyms: [weighted_handle_time]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: case_weighted_quality_score
    expr: "MEASURE(quality_case_points) / NULLIF(MEASURE(cases_handled), 0)"
    comment: "Quality score weighted by cases handled."
    display_name: "Case-Weighted Quality Score"
    synonyms: [weighted_quality]
    format: {type: number, decimal_places: {type: max, places: 2}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
