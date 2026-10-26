USE CATALOG `${catalog}`;
USE SCHEMA `${silver_schema}`;

CREATE TEMPORARY VIEW worker_changes
AS
SELECT
  upper(trim(worker_id)) AS worker_id,
  trim(first_name) AS first_name,
  trim(last_name) AS last_name,
  CAST(birth_date AS DATE) AS birth_date,
  trim(gender) AS gender,
  CAST(hire_date AS DATE) AS hire_date,
  CAST(termination_date AS DATE) AS termination_date,
  initcap(lower(trim(employment_status))) AS employment_status,
  upper(trim(job_code)) AS job_code,
  upper(trim(org_unit_id)) AS org_unit_id,
  upper(trim(manager_id)) AS manager_id,
  CASE lower(trim(business_line))
    WHEN 'consumer banking' THEN 'Consumer Banking'
    WHEN 'wealth management' THEN 'Wealth Management'
    WHEN 'commercial banking' THEN 'Commercial Banking'
    WHEN 'operations' THEN 'Operations'
    WHEN 'technology' THEN 'Technology'
    WHEN 'corporate functions' THEN 'Corporate Functions'
    ELSE trim(business_line)
  END AS business_line,
  initcap(lower(trim(location))) AS location,
  initcap(lower(trim(worker_type))) AS worker_type,
  lower(trim(email)) AS email,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`workers`);

CREATE OR REFRESH STREAMING TABLE workers (
  CONSTRAINT valid_business_line EXPECT (
    business_line IN (
      'Consumer Banking',
      'Wealth Management',
      'Commercial Banking',
      'Operations',
      'Technology',
      'Corporate Functions'
    )
  ) ON VIOLATION DROP ROW,
  CONSTRAINT hire_date_not_null EXPECT (hire_date IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Typed and conformed worker master at one current row per employee.';

CREATE FLOW workers_cdc AS AUTO CDC INTO workers
FROM STREAM(worker_changes)
KEYS (worker_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE TEMPORARY VIEW worker_history_changes
AS
SELECT
  upper(trim(history.event_id)) AS event_id,
  upper(trim(history.worker_id)) AS worker_id,
  upper(trim(history.event_type)) AS event_type,
  CAST(history.event_date AS DATE) AS event_date,
  upper(trim(history.job_code)) AS job_code,
  upper(trim(history.previous_job_code)) AS previous_job_code,
  upper(trim(history.org_unit_id)) AS org_unit_id,
  upper(trim(history.previous_org_unit_id)) AS previous_org_unit_id,
  upper(trim(history.manager_id)) AS manager_id,
  upper(trim(history.previous_manager_id)) AS previous_manager_id,
  initcap(lower(trim(history.termination_type))) AS termination_type,
  trim(history.event_reason) AS event_reason,
  CAST(worker.hire_date AS DATE) AS hire_date,
  history._rescued_data,
  history._source_file,
  history._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`job_history`) AS history
INNER JOIN `${catalog}`.`${bronze_schema}`.`workers` AS worker
  ON upper(trim(history.worker_id)) = upper(trim(worker.worker_id));

CREATE OR REFRESH STREAMING TABLE worker_history (
  CONSTRAINT event_date_on_or_after_hire_date EXPECT (
    event_date >= hire_date
  )
)
COMMENT 'Effective-dated employee job, organization, manager, and exit history maintained as SCD Type 2.';

CREATE FLOW worker_history_cdc AS AUTO CDC INTO worker_history
FROM STREAM(worker_history_changes)
KEYS (worker_id)
SEQUENCE BY STRUCT(event_date, event_id)
STORED AS SCD TYPE 2;

CREATE TEMPORARY VIEW org_unit_changes
AS
SELECT
  upper(trim(org_unit_id)) AS org_unit_id,
  trim(org_unit_name) AS org_unit_name,
  CASE lower(trim(business_line))
    WHEN 'consumer banking' THEN 'Consumer Banking'
    WHEN 'wealth management' THEN 'Wealth Management'
    WHEN 'commercial banking' THEN 'Commercial Banking'
    WHEN 'operations' THEN 'Operations'
    WHEN 'technology' THEN 'Technology'
    WHEN 'corporate functions' THEN 'Corporate Functions'
    ELSE trim(business_line)
  END AS business_line,
  trim(org_type) AS org_type,
  initcap(lower(trim(region))) AS region,
  initcap(lower(trim(location))) AS location,
  upper(trim(parent_org_unit_id)) AS parent_org_unit_id,
  upper(trim(manager_id)) AS manager_id,
  CAST(schedule_change_date AS DATE) AS schedule_change_date,
  CAST(standout_manager_flag AS BOOLEAN) AS standout_manager_flag,
  _rescued_data,
  _source_file,
  _ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`org_units`);

CREATE OR REFRESH STREAMING TABLE org_units
COMMENT 'Typed and conformed organization hierarchy at one row per organization unit.';

CREATE FLOW org_units_cdc AS AUTO CDC INTO org_units
FROM STREAM(org_unit_changes)
KEYS (org_unit_id)
SEQUENCE BY STRUCT(_ingested_at, _source_file)
STORED AS SCD TYPE 1;

CREATE OR REFRESH PRIVATE MATERIALIZED VIEW job_description_ai_signals
COMMENT 'Pipeline-private AI classifications and extracted skills at one row per distinct normalized job description.'
AS
SELECT
  job_ai_source.job_description,
  exposure_result:response[0]::STRING AS genai_exposure_tier,
  exposure_result:error_message::STRING AS genai_exposure_error,
  skills_result:response:required_skills::ARRAY<STRING> AS required_skills,
  skills_result:error_message::STRING AS required_skills_error
FROM (
  SELECT
    job_text.job_description,
    ai_classify(
      job_text.job_description,
      '{"high":"Core work includes high-volume rules, repetitive case decisions, scripted knowledge, summarization, routing, or similar recurring tasks that generative AI can substantially accelerate even when human empathy or escalation remains essential","medium":"Generative AI can materially assist analytical, data science, data engineering, or software engineering work, but expert design, validation, and judgment remain central","low":"Core work centers customer relationships, leadership, licensed accountability, cybersecurity, enterprise architecture, physical presence, or generic banking delivery with limited explicit generative AI substitution"}',
      map(
        'version', '2.0',
        'instructions', 'Classify the role described, using both its title and named tasks. High includes contact-center and operations work with scripted, summarization, routing, document-review, rules, or repetitive case tasks. Medium includes hands-on data science, data engineering, and software engineering. Low includes cybersecurity, enterprise architecture, relationship, leadership, licensed, physical, and generic banking roles unless high-exposure tasks are explicit.'
      )
    ) AS exposure_result,
    ai_extract(
      job_text.job_description,
      '{"required_skills":{"type":"array","items":{"type":"string"}}}',
      map(
        'version', '2.0',
        'instructions', 'Extract only skills, capabilities, domain knowledge, tools, licenses, or behaviors explicitly named by the job description. Do not convert the job title into a skill or infer capabilities that are not stated. Return concise normalized skill phrases.'
      )
    ) AS skills_result
  FROM (
    SELECT trim(job_description) AS job_description
    FROM `${catalog}`.`${bronze_schema}`.`jobs`
    WHERE job_description IS NOT NULL
      AND trim(job_description) <> ''
    GROUP BY trim(job_description)
  ) AS job_text
) AS job_ai_source;

CREATE OR REFRESH STREAMING TABLE jobs_enriched (
  CONSTRAINT job_code_not_null EXPECT (job_code IS NOT NULL)
)
COMMENT 'Typed job catalog enriched with AI-classified GenAI exposure and AI-extracted required skills.'
AS
SELECT
  upper(trim(job.job_code)) AS job_code,
  trim(job.job_title) AS job_title,
  trim(job.job_family) AS job_family,
  trim(job.job_level) AS job_level,
  trim(job.business_line) AS business_line,
  CAST(job.licensed_role_flag AS BOOLEAN) AS licensed_role_flag,
  CAST(job.strategic_role_flag AS BOOLEAN) AS strategic_role_flag,
  trim(job.expected_genai_exposure_tier) AS expected_genai_exposure_tier,
  trim(job.job_description) AS job_description,
  signals.genai_exposure_tier,
  signals.genai_exposure_error,
  signals.required_skills,
  signals.required_skills_error,
  job._rescued_data,
  job._source_file,
  job._ingested_at
FROM STREAM(`${catalog}`.`${bronze_schema}`.`jobs`) AS job
LEFT JOIN job_description_ai_signals AS signals
  ON trim(job.job_description) = signals.job_description;
