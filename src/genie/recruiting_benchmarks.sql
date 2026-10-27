-- benchmark: 43000000000000000000000000000001
SELECT CASE
    WHEN requisitions.licensed_role_flag AND requisitions.job_family LIKE '%Advisor%'
      THEN 'Licensed advisor roles'
    ELSE 'All other roles'
  END AS role_group,
  MEASURE(requisitions.average_time_to_fill) AS average_time_to_fill,
  MEASURE(requisitions.filled_requisitions) AS filled_requisitions
FROM ${catalog}.${gold_schema}.mv_requisitions AS requisitions
GROUP BY ALL ORDER BY role_group;

-- benchmark: 43000000000000000000000000000002
SELECT funnel.decline_reason, MEASURE(funnel.declined_offers) AS declined_offers
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel
WHERE funnel.licensed_role_flag = true
GROUP BY ALL ORDER BY declined_offers DESC;

-- benchmark: 43000000000000000000000000000003
WITH contact_centers AS (
  SELECT requisitions.year, requisitions.org_unit_name,
    MEASURE(requisitions.backfill_requisitions) AS backfill_requisitions
  FROM ${catalog}.${gold_schema}.mv_requisitions AS requisitions
  WHERE requisitions.org_type = 'Contact Center' GROUP BY ALL
), bounds AS (SELECT max(year) AS latest_year FROM contact_centers)
SELECT contact_centers.org_unit_name, contact_centers.backfill_requisitions
FROM contact_centers CROSS JOIN bounds WHERE contact_centers.year = bounds.latest_year
ORDER BY contact_centers.org_unit_name;

-- benchmark: 43000000000000000000000000000004
SELECT funnel.org_unit_name, funnel.job_family,
  MEASURE(funnel.internal_applications) AS internal_applications
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel
WHERE funnel.status = 'Open' AND funnel.internal_candidate_flag = true
  AND funnel.internal_genai_exposure_tier IN ('high', 'medium')
GROUP BY ALL ORDER BY internal_applications DESC LIMIT 50;

-- benchmark: 43000000000000000000000000000005
SELECT funnel.recruiting_source, MEASURE(funnel.offers_extended) AS offers_extended,
  MEASURE(funnel.offer_acceptance_rate) AS offer_acceptance_rate,
  MEASURE(funnel.offer_decline_rate) AS offer_decline_rate
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel
GROUP BY ALL ORDER BY offers_extended DESC;

-- benchmark: 43000000000000000000000000000006
SELECT funnel.licensed_role_flag, MEASURE(funnel.applications) AS applications,
  MEASURE(funnel.applied_to_screen_conversion_rate) AS applied_to_screen_rate,
  MEASURE(funnel.screen_to_interview_conversion_rate) AS screen_to_interview_rate,
  MEASURE(funnel.interview_to_offer_conversion_rate) AS interview_to_offer_rate,
  MEASURE(funnel.offer_to_hire_conversion_rate) AS offer_to_hire_rate
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel GROUP BY ALL;

-- benchmark: 43000000000000000000000000000007
SELECT requisitions.business_line,
  MEASURE(requisitions.open_requisitions) AS open_requisitions
FROM ${catalog}.${gold_schema}.mv_requisitions AS requisitions
GROUP BY ALL ORDER BY open_requisitions DESC;

-- benchmark: 43000000000000000000000000000008
SELECT requisitions.job_family,
  MEASURE(requisitions.backfill_share) AS backfill_share,
  MEASURE(requisitions.average_time_to_fill) AS average_time_to_fill,
  MEASURE(requisitions.requisitions) AS requisitions
FROM ${catalog}.${gold_schema}.mv_requisitions AS requisitions
GROUP BY ALL ORDER BY backfill_share DESC, average_time_to_fill DESC;

-- benchmark: 43000000000000000000000000000009
SELECT funnel.org_unit_name,
  MEASURE(funnel.internal_applicant_share) AS internal_applicant_share,
  MEASURE(funnel.internal_applications) AS internal_applications,
  MEASURE(funnel.applications) AS applications
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel
GROUP BY ALL ORDER BY internal_applicant_share DESC LIMIT 20;

-- benchmark: 43000000000000000000000000000010
SELECT funnel.decline_reason, MEASURE(funnel.declined_offers) AS declined_offers
FROM ${catalog}.${gold_schema}.mv_recruiting_funnel AS funnel
WHERE funnel.business_line = 'Wealth Management'
GROUP BY ALL ORDER BY declined_offers DESC;
