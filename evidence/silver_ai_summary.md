# Aita Silver AI

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Successful sample job run ID: `501528568974054`
- Successful sample pipeline update ID: `ba87c9cf-eeb4-4d50-9997-d39c059fd47d`
- Successful optimized pipeline update ID: `dab347e2-e973-4b3c-9350-871b79a4014b`
- Final engagement refinement update ID: `2cd52b9d-2486-4924-b7bd-15b8369f0ec8`
- Result: `PASS`

## Implementation

- `jobs_enriched` classifies `genai_exposure_tier` and extracts `required_skills`.
- `exit_interviews_enriched` classifies `exit_reason` and analyzes `exit_sentiment`.
- `engagement_enriched` classifies `comment_theme` and analyzes `comment_sentiment`.
- `performance_enriched` extracts `demonstrated_skills`.
- `applications_enriched` extracts `candidate_skills` and classifies non-empty offer-decline comments.
- Every published table retains `_rescued_data`, `_source_file`, and `_ingested_at`; task-specific AI results also retain explicit error columns.

## Cost Optimization

Initial full-row inference was canceled because the repeated synthetic text would have invoked AI Functions approximately 383,492 times. The final design materializes AI results once per distinct normalized text in six private materialized views, then joins those cached signals into the full silver streaming tables.

| Text input | Source rows | Distinct texts | AI Functions per text | Optimized calls |
|---|---:|---:|---:|---:|
| Job description | 60 | 60 | 2 | 120 |
| Exit comment | 1,161 | 6 | 2 | 12 |
| Engagement comment | 155,063 | 5 | 2 | 10 |
| Manager comment | 40,000 | 4 | 1 | 4 |
| Candidate summary | 28,800 | 4 | 1 | 4 |
| Offer-decline comment | 2,124 | 2 | 1 | 2 |
| **Total** |  | **81** |  | **152** |

The optimized refresh reduces estimated AI calls by 99.96% while preserving every source row in the published tables.

## Row and Grain Reconciliation

| Silver table | Total rows | Distinct grain | Duplicate grain rows | Rescued rows | AI error rows | Missing required AI rows | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| `jobs_enriched` | 60 | 60 `job_code` | 0 | 0 | 0 | 0 | PASS |
| `exit_interviews_enriched` | 1,161 | 1,161 `exit_interview_id` | 0 | 0 | 0 | 0 | PASS |
| `engagement_enriched` | 155,063 | 155,063 `survey_response_id` | 0 | 0 | 0 | 0 | PASS |
| `performance_enriched` | 40,000 | 40,000 `review_id` | 0 | 0 | 0 | 0 | PASS |
| `applications_enriched` | 28,800 | 28,800 `application_id` | 0 | 0 | 0 | 0 | PASS |
| **Total** | **225,084** |  | **0** | **0** | **0** | **0** | **PASS** |

All 2,124 non-empty offer-decline comments produced a non-null `decline_reason`.

## Expectation Results

| Table | Expectation | Action | Passed | Failed |
|---|---|---|---:|---:|
| `jobs_enriched` | `job_code_not_null` | Warn | 60 | 0 |
| `exit_interviews_enriched` | `exit_comment_not_empty` | Warn | 1,161 | 0 |
| `engagement_enriched` | `engagement_score_between_1_and_5` | Drop row | 155,063 | 0 |
| `performance_enriched` | `performance_rating_allowed` | Drop row | 40,000 | 0 |
| `applications_enriched` | `requisition_exists` | Warn | 28,800 | 0 |

The expectation counts come from the pipeline event log for updates `dab347e2-e973-4b3c-9350-871b79a4014b` and `2cd52b9d-2486-4924-b7bd-15b8369f0ec8`.

## Output Review

### Job Exposure

The final classifier matches the generator's planted exposure tier for 55 of 60 jobs (91.7%). All five expected high-exposure jobs classified as high. The five remaining differences are retained as genuine model outputs rather than overwritten with the synthetic expected label.

| Expected tier | AI tier | Rows |
|---|---|---:|
| high | high | 5 |
| medium | medium | 4 |
| medium | low | 1 |
| low | low | 46 |
| low | medium | 3 |
| low | high | 1 |

Representative extractions include contact-center summarization and case routing, operations rules and document review, licensed-role compliance, and technology data, cloud, software, and AI-governance skills.

### Exit Interviews

The tuned classifier matches the planted `stated_reason` on all 1,161 exit interviews.

| Exit reason | Rows | Sentiment |
|---|---:|---|
| manager | 226 | negative |
| career growth | 212 | negative |
| relocation | 212 | neutral |
| other | 208 | neutral |
| compensation | 200 | mixed |
| schedule and workload | 103 | negative |

Twenty representative exit-interview outputs from the initial review are stored in `evidence/silver_exit_interviews_ai_sample.md`.

### Engagement

| Comment pattern | Theme | Sentiment | Rows |
|---|---|---|---:|
| Manageable work; clearer priorities and recognition needed | recognition | mixed | 96,323 |
| Supported and connected to the bank's purpose | positive | positive | 48,666 |
| Manager recognizes work and removes obstacles | recognition | positive | 6,619 |
| Sustained overtime and rising workload causing burnout | burnout | negative | 2,113 |
| Difficult schedule and insufficient recovery between shifts | workload | negative | 1,342 |

The final refinement separates explicit fraud-operations burnout from contact-center schedule and workload pressure.

### Performance

The four distinct manager comments produced reusable skill arrays for all 40,000 reviews. The planted AI/data high-performer comment extracted AI, mentoring, SQL, machine learning, and stakeholder leadership. Developmental comments that did not state demonstrated skills returned an empty array rather than inferred capabilities.

### Applications

- The planted internal-mobility summary extracted SQL, data quality, process automation, controls, customer judgment, fraud case analysis, and bank-sponsored data training for 738 applications.
- The generic closer-fit decline comment classified as `role fit` for 2,007 applications.
- The stronger-client-book and compensation-ramp comment classified as `competing offer` for 117 applications.

## Resolved Execution Issues

- `ai_extract` version 2.1 wrapped array values in objects; the implementation uses version 2.0 so published skill columns are plain `ARRAY<STRING>` values.
- Per-row full refresh `9a47d2e4-f3c7-4d84-858a-fc6e4cb14882` was intentionally canceled for cost control; no rescued records were discarded.
- Initial optimized update `7bdefa31-2a61-4e3d-8891-7f464b857f50` failed because targeted selection omitted the new private dependencies. The corrected update selected all six private views and five published tables and completed successfully.
