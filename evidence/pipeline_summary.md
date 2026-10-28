# Pipeline Evidence

Synthetic generation through Gold, run October 24–25, 2026 on profile `genie-workbench` and bundle target `dev`. Every check below passed.

## Runs

| Stage | Job run | Pipeline update |
|---|---|---|
| Bronze ingestion | `65455966715028` | `256ca01f-05d2-4300-9eb3-c709c9317656` |
| Silver core | `332861017181304` | `936675c5-59cd-498d-869d-50d35bc342f0` |
| Silver AI sample | `501528568974054` | `ba87c9cf-eeb4-4d50-9997-d39c059fd47d` |
| Silver AI optimized | | `dab347e2-e973-4b3c-9350-871b79a4014b` |
| Silver AI engagement refinement | | `2cd52b9d-2486-4924-b7bd-15b8369f0ec8` |
| Gold dimensions | `961565381599131` | `ed904241-36ae-4fd2-ab91-15eaa1882df3` |
| Gold facts | `24365280429776` | `9f70c7ed-566a-4fc9-8793-de4d05e54ec5` |
| Talent watchlist | `618778647851719` | `30cecb4b-3be0-4180-9d69-8c79bc38fe14` |
| Gold worker-version refactor | | `a40a2324-758c-4fb8-a0e5-4b5ce27054f4` |

## Row Reconciliation

Generator seed `20261024`. Landing and Bronze counts match for every dataset.

| Dataset | Landing = Bronze | Silver table | Silver rows |
|---|---:|---|---:|
| workers | 20,000 | `workers` | 20,000 |
| job_history | 28,504 | `worker_history` | 28,504 |
| org_units | 72 | `org_units` | 72 |
| jobs | 60 | `jobs_enriched` | 60 |
| engagement_surveys | 155,063 | `engagement_enriched` | 155,063 |
| exit_interviews | 1,161 | `exit_interviews_enriched` | 1,161 |
| team_productivity | 1,728 | `team_productivity` | 1,728 |
| performance_reviews | 40,000 | `performance_enriched` | 40,000 |
| compensation | 40,000 | `compensation` | 40,000 |
| requisitions | 2,400 | `requisitions` | 2,400 |
| applications | 28,800 | `applications_enriched` | 28,800 |
| application_events | 86,240 | `application_events` | 86,240 |
| **Total** | **404,028** | | **404,028** |

- Bronze: zero null `_source_file` or `_ingested_at` values and zero non-null `_rescued_data` values in all 12 tables.
- Silver: zero duplicate grain rows, rescued rows, AI error rows, or missing required AI outputs. `worker_history` has exactly one current row for each of the 20,000 workers and no event before hire date.

## Planted Patterns

| Pattern | Evidence |
|---|---|
| Contact-center attrition spike | 108 spike exits; 95.4% under the three target managers; 95.4% of exit comments mention schedule or workload |
| Stalled strategic high performers | 506 high performers below band midpoint with 3+ years and no recent promotion |
| Fraud-operations burnout | Engagement fell 1.537 points; overtime grew 2.456x; 100% of late comments mention burnout, overtime, or workload |
| Standout managers | 3 managers combine high engagement, high CSAT, and less than half the company attrition rate |
| GenAI internal mobility | 738 internal applicants from GenAI-exposed operations roles applied to technology roles using adjacent skills |
| Licensed-role hiring friction | Licensed roles take 2.118x as long to fill; compensation or competing offers explain 100% of licensed-role declines |
| Contact-center backfills | 164 post-spike backfills versus 3 in the baseline period; 100% follow an exit in the prior 90 days |

## Expectations

From the pipeline event log for the Silver core and final Silver AI updates.

| Table | Expectation | Action | Passed | Failed |
|---|---|---|---:|---:|
| `workers` | `valid_business_line` | Drop row | 20,000 | 0 |
| `workers` | `hire_date_not_null` | Fail update | 20,000 | 0 |
| `worker_history` | `event_date_on_or_after_hire_date` | Warn | 20,000 | 0 |
| `compensation` | `base_salary_within_band` | Warn | 40,000 | 0 |
| `requisitions` | `close_date_on_or_after_open_date` | Warn | 2,400 | 0 |
| `jobs_enriched` | `job_code_not_null` | Warn | 60 | 0 |
| `exit_interviews_enriched` | `exit_comment_not_empty` | Warn | 1,161 | 0 |
| `engagement_enriched` | `engagement_score_between_1_and_5` | Drop row | 155,063 | 0 |
| `performance_enriched` | `performance_rating_allowed` | Drop row | 40,000 | 0 |
| `applications_enriched` | `requisition_exists` | Warn | 28,800 | 0 |

The `worker_history` expectation reports on the 20,000 current SCD Type 2 rows; a separate check across all 28,504 versions found zero events before hire date.

## Silver AI

| Text input | Source rows | Distinct texts | AI calls |
|---|---:|---:|---:|
| Job description | 60 | 60 | 120 |
| Exit comment | 1,161 | 6 | 12 |
| Engagement comment | 155,063 | 5 | 10 |
| Manager comment | 40,000 | 4 | 4 |
| Candidate summary | 28,800 | 4 | 4 |
| Offer-decline comment | 2,124 | 2 | 2 |
| **Total** | | **81** | **152** |

Per-row inference would have made about 383,492 calls; cached lookups over distinct normalized text cut that by 99.96%.

| AI output | Result |
|---|---|
| `genai_exposure_tier` | Matches the planted tier for 55 of 60 jobs, including all 5 expected-high jobs; the 5 differences (medium→low 1, low→medium 3, low→high 1) are kept and flagged by `dim_job.genai_tier_mismatch_flag` |
| `exit_reason` | Matches the planted `stated_reason` on all 1,161 exits: manager 226, career growth 212, relocation 212, other 208, compensation 200, schedule and workload 103 |
| `comment_theme` | recognition 102,942; positive 48,666; burnout 2,113 (explicit overtime and burnout); workload 1,342 (difficult schedule and recovery time) |
| `demonstrated_skills` | The planted AI/data comment yields AI, mentoring, SQL, machine learning, and stakeholder leadership; developmental comments yield empty arrays |
| `candidate_skills` | The planted mobility summary yields SQL, data quality, process automation, controls, customer judgment, fraud case analysis, and bank-sponsored data training for 738 applications |
| `decline_reason` | All 2,124 decline comments classified: role fit 2,007, competing offer 117 |

Example: "The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role." → `schedule and workload`, negative.

Resolved issues behind the current design:

- Streaming `SELECT DISTINCT` requires a watermark in append mode (failed run `162906550700389`); keyed AUTO CDC Type 1 flows deduplicate instead.
- `ai_extract` version 2.1 wrapped array elements in objects; version 2.0 returns plain `ARRAY<STRING>`.
- Per-row refresh `9a47d2e4-f3c7-4d84-858a-fc6e4cb14882` was canceled for cost. The first cached update, `7bdefa31-2a61-4e3d-8891-7f464b857f50`, failed because the targeted refresh omitted the new private views.

## Gold

| Table | Rows | Grain |
|---|---:|---|
| `dim_worker` | 20,000 | employee |
| `dim_org` | 72 | organization unit |
| `dim_job` | 60 | job code |
| `dim_date` | 6,939 | day, 2009-01-01 through 2027-12-31 with no gaps |
| `fact_headcount_monthly` | 17,436 | org × job × month |
| `fact_attrition_event` | 1,161 | exit |
| `fact_engagement` | 155,063 | employee × wave |
| `fact_productivity` | 1,728 | team × month |
| `fact_performance` | 40,000 | employee × year |
| `fact_compensation` | 40,000 | employee × year |
| `fact_requisition` | 2,400 | requisition |
| `fact_application_funnel` | 28,800 | application |

All 12 tables have zero duplicate or null keys and zero source-count differences; 19 fact-to-dimension checks found zero orphan keys. Updates `a40a2324-758c-4fb8-a0e5-4b5ce27054f4` (`worker_versions`) and `84990991-4115-4097-9d9c-6d01e74bfe77` (`latest_talent`) retained exact counts, grains, and dual fingerprints; all 13 semantic and relevant metric checks passed.

- Headcount: 24 months, 2024-10 through 2026-09, derived from `team_productivity`; September 2026 month-end headcount is 18,839; 1,161 exits, 884 voluntary; zero empty cells.
- Temporal joins use half-open SCD Type 2 intervals. The single zero-length history version is excluded from interval scans, and its manager-change event is still counted.
- Engagement: 8 waves; all 155,063 responses match exactly one effective job.
- Recruiting: every requisition has 12 applications; `time_to_fill_days` is populated for filled requisitions only; zero negative funnel durations; 3,138 internal applications; screen, interview, offer, and hire milestones are 22,544, 11,448, 6,648, and 2,124.

## Talent Watchlist

3,427 rows and 3,427 distinct employees, with one as-of date (`2026-12-31`). Zero null grain values, signal-count or reason-count mismatches, empty-signal rows, or hard-to-backfill flags without another flag.

| Risk flag | Employees |
|---|---:|
| `stalled_high_performer` | 969 |
| `disengaging` | 2,199 |
| `team_at_risk` | 418 |
| `hard_to_backfill_risk` | 311 |

- Team-risk threshold: 5.3% trailing-12-month voluntary attrition (twice the bank average). Only `ORG001` (35.2%) and `ORG002` (15.8%) exceed it with qualifying exit reasons.
- Bank median job-family time to fill: 45.4 days.
- Planted coverage: 504 of 504 active stalled employees (the generator's 506 includes 2 who left), 522 of 522 active fraud-operations employees, and 2 of 2 contact-center units, with no unexpected team-at-risk units.
