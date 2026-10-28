EXECUTE IMMEDIATE CONCAT(
  'CREATE OR REPLACE VIEW `', :catalog, '`.`', :gold_schema,
  '`.`mv_engagement` WITH METRICS LANGUAGE YAML AS $$\n',
  REPLACE(
    REPLACE(
      'version: 1.1
source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.fact_engagement
comment: "Survey-wave engagement metrics with previous-wave comparison and AI-classified comment signals."
joins:
  - name: dim_org
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_org
    "on": source.org_unit_id = dim_org.org_unit_id
  - name: dim_job
    source: __AITA_CATALOG__.__AITA_GOLD_SCHEMA__.dim_job
    "on": source.job_code = dim_job.job_code
dimensions:
  - name: survey_date
    expr: source.survey_date
    comment: "Date the survey response was recorded."
    display_name: "Survey Date"
    synonyms: [response_date]
    format: {type: date, date_format: year_month_day}
  - name: month
    expr: "DATE_TRUNC(\'MONTH\', source.survey_date)"
    comment: "First date of the survey calendar month."
    display_name: "Month"
    synonyms: [survey_month]
    format: {type: date, date_format: year_month_day}
  - name: quarter
    expr: "DATE_TRUNC(\'QUARTER\', source.survey_date)"
    comment: "First date of the survey calendar quarter."
    display_name: "Quarter"
    synonyms: [survey_quarter]
    format: {type: date, date_format: year_month_day}
  - name: year
    expr: YEAR(source.survey_date)
    comment: "Calendar year of the survey response."
    display_name: "Year"
    synonyms: [survey_year]
  - name: survey_wave
    expr: source.survey_wave
    comment: "Source survey-wave label."
    display_name: "Survey Wave"
    synonyms: [pulse_wave]
  - name: org_unit_id
    expr: source.org_unit_id
    comment: "Organization-unit identifier recorded on the survey."
    display_name: "Organization Unit ID"
    synonyms: [team_id]
  - name: org_unit_name
    expr: dim_org.org_unit_name
    comment: "Organization-unit name recorded on the survey."
    display_name: "Organization Unit"
    synonyms: [team, branch, contact_center]
  - name: org_type
    expr: dim_org.org_type
    comment: "Organization hierarchy type."
    display_name: "Organization Type"
    synonyms: [unit_type]
  - name: business_line
    expr: dim_org.business_line
    comment: "Business line recorded on the survey."
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
    comment: "Job code effective on the survey date."
    display_name: "Job Code"
    synonyms: [role_code]
  - name: job_family
    expr: dim_job.job_family
    comment: "Job family effective on the survey date."
    display_name: "Job Family"
    synonyms: [role_family]
  - name: job_level
    expr: dim_job.job_level
    comment: "Career level effective on the survey date."
    display_name: "Job Level"
    synonyms: [career_level]
  - name: licensed_role_flag
    expr: dim_job.licensed_role_flag
    comment: "Whether the surveyed role requires a license."
    display_name: "Licensed Role"
    synonyms: [licensed_job]
  - name: strategic_role_flag
    expr: dim_job.strategic_role_flag
    comment: "Whether the surveyed role is strategic."
    display_name: "Strategic Role"
    synonyms: [critical_role]
  - name: genai_exposure_tier
    expr: dim_job.genai_exposure_tier
    comment: "AI-classified GenAI exposure tier of the surveyed role."
    display_name: "GenAI Exposure Tier"
    synonyms: [ai_exposure]
  - name: manager_id
    expr: source.manager_id
    comment: "Manager identifier recorded on the survey."
    display_name: "Manager ID"
    synonyms: [supervisor_id]
  - name: comment_theme
    expr: source.comment_theme
    comment: "AI-classified theme from the survey comment."
    display_name: "AI-Classified Comment Theme"
    synonyms: [survey_theme]
  - name: comment_sentiment
    expr: source.comment_sentiment
    comment: "AI-analyzed sentiment from the survey comment."
    display_name: "Comment Sentiment"
    synonyms: [survey_sentiment]
measures:
  - name: survey_responses
    expr: COUNT(1)
    comment: "Survey responses in the selected population."
    display_name: "Survey Responses"
    synonyms: [responses]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: classified_sentiment_responses
    expr: COUNT(source.comment_sentiment)
    comment: "Survey responses with an AI-analyzed comment sentiment."
    display_name: "Classified Sentiment Responses"
    synonyms: [sentiment_responses]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: negative_comment_responses
    expr: COUNT(1) FILTER (WHERE source.comment_sentiment = \'negative\')
    comment: "Responses with AI-analyzed negative comment sentiment."
    display_name: "Negative Comment Responses"
    synonyms: [negative_responses]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: classified_theme_responses
    expr: COUNT(source.comment_theme)
    comment: "Survey responses with an AI-classified comment theme."
    display_name: "Classified Theme Responses"
    synonyms: [theme_responses]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: burnout_or_workload_responses
    expr: COUNT(1) FILTER (WHERE source.comment_theme IN (\'burnout\', \'workload\'))
    comment: "Responses whose AI-classified theme is burnout or workload."
    display_name: "Burnout or Workload Responses"
    synonyms: [burnout_signals, workload_signals]
    format: {type: number, decimal_places: {type: exact, places: 0}}
  - name: engagement_index
    expr: AVG(source.engagement_score)
    comment: "Average engagement score for the current survey wave."
    display_name: "Engagement Index"
    synonyms: [engagement_score]
    format: {type: number, decimal_places: {type: max, places: 2}}
    window:
      - order: survey_date
        range: current
        semiadditive: last
  - name: previous_wave_engagement_index
    expr: AVG(source.engagement_score)
    comment: "Average engagement score from the immediately preceding quarterly wave."
    display_name: "Previous-Wave Engagement Index"
    synonyms: [prior_engagement_index]
    format: {type: number, decimal_places: {type: max, places: 2}}
    window:
      - order: survey_date
        range: trailing 3 month
        semiadditive: last
  - name: engagement_change
    expr: "MEASURE(engagement_index) - MEASURE(previous_wave_engagement_index)"
    comment: "Current survey-wave engagement index minus the previous wave."
    display_name: "Engagement Change"
    synonyms: [engagement_delta]
    format: {type: number, decimal_places: {type: max, places: 2}}
  - name: negative_comment_share
    expr: "MEASURE(negative_comment_responses) / NULLIF(MEASURE(classified_sentiment_responses), 0)"
    comment: "Negative-sentiment responses divided by classified-sentiment responses."
    display_name: "Negative Comment Share"
    synonyms: [negative_sentiment_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
  - name: burnout_or_workload_signal_rate
    expr: "MEASURE(burnout_or_workload_responses) / NULLIF(MEASURE(classified_theme_responses), 0)"
    comment: "Burnout-or-workload responses divided by classified-theme responses."
    display_name: "Burnout or Workload Signal Rate"
    synonyms: [burnout_rate, workload_signal_rate]
    format: {type: percentage, decimal_places: {type: max, places: 2}}
$$',
      '__AITA_CATALOG__', :catalog
    ),
    '__AITA_GOLD_SCHEMA__', :gold_schema
  )
);
