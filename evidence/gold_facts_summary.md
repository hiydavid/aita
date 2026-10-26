# Aita Gold Facts

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Successful job run ID: `24365280429776`
- Successful pipeline update ID: `9f70c7ed-566a-4fc9-8793-de4d05e54ec5`
- Result: `PASS`

## Implementation

- `fact_headcount_monthly` publishes month-end headcount and in-month movements at organization, job, and month grain for the 24-month productivity window.
- `fact_attrition_event` publishes one row per exit with tenure, voluntary and regrettable flags, job attributes, and AI-enriched exit-interview signals.
- `fact_engagement` publishes one row per employee and survey wave with a date-effective job assignment, survey scores, sentiment, theme, and burnout flag.
- `fact_productivity` publishes monthly cases, handle time, CSAT, overtime, and quality measures at team grain.
- `fact_performance` publishes annual employee ratings, potential, high-performer flags, and AI-extracted demonstrated skills.
- `fact_compensation` publishes masked pay-position ratios and bands without salary, bonus, pay-band, or currency amounts.
- `fact_requisition` publishes fill-cycle, backfill, licensed-role, application-volume, hire, and recruiting-cost measures.
- `fact_application_funnel` publishes one application lifecycle with stage milestones, elapsed times, internal-candidate status, candidate skills, and AI-derived decline reason.

## Temporal Rules

- Headcount uses half-open SCD Type 2 intervals: the version start is included and the version end is excluded.
- The single zero-length worker-history version is excluded from temporal scans, preventing double counting, while its manager-change event remains included in monthly movements.
- The headcount window is derived from the minimum and maximum `team_productivity.month` values rather than hardcoded dates.
- Engagement joins each response to the worker-history version in force on `survey_date`; all 155,063 rows matched exactly one effective job.

## Row and Grain Reconciliation

| Gold table | Total rows | Distinct grain | Null grain rows | Expected rows | Difference | Result |
|---|---:|---:|---:|---:|---:|---|
| `fact_headcount_monthly` | 17,436 | 17,436 org × job × month | 0 | 17,436 | 0 | PASS |
| `fact_attrition_event` | 1,161 | 1,161 attrition events | 0 | 1,161 | 0 | PASS |
| `fact_engagement` | 155,063 | 155,063 employee × wave | 0 | 155,063 | 0 | PASS |
| `fact_productivity` | 1,728 | 1,728 team × month | 0 | 1,728 | 0 | PASS |
| `fact_performance` | 40,000 | 40,000 employee × year | 0 | 40,000 | 0 | PASS |
| `fact_compensation` | 40,000 | 40,000 employee × year | 0 | 40,000 | 0 | PASS |
| `fact_requisition` | 2,400 | 2,400 requisitions | 0 | 2,400 | 0 | PASS |
| `fact_application_funnel` | 28,800 | 28,800 applications | 0 | 28,800 | 0 | PASS |
| **Total** | **286,588** |  | **0** | **286,588** | **0** | **PASS** |

## Referential Integrity

Nineteen fact-to-dimension checks returned zero invalid rows. These cover employee, manager, organization, job, team, requisition, and internal-candidate keys across all eight facts.

## Business-Rule Checks

| Check | Result |
|---|---:|
| Headcount months, `2024-10-01` through `2026-09-01` | 24 |
| September 2026 month-end headcount | 18,839 |
| Headcount cells with zero employees | 0 |
| Headcount exit count | 1,161 |
| Headcount voluntary exit count | 884 |
| Attrition rows missing interview AI enrichment | 0 |
| Regrettable voluntary exits eligible for rehire | 603 |
| Engagement temporal job misses | 0 |
| Engagement waves | 8 |
| AI-classified burnout responses | 2,113 |
| Requisitions not containing 12 applications | 0 |
| Filled requisitions missing time to fill | 0 |
| Non-filled requisitions with time to fill | 0 |
| Funnel rows with a negative duration | 0 |
| Internal applications | 3,138 |
| Screen / interview / offer / hire milestones | 22,544 / 11,448 / 6,648 / 2,124 |
| Declined offers with an AI-classified reason | 2,124 |

`regrettable_flag` is defined as a voluntary departure where the exit interview marks the employee eligible for rehire.

## Compensation Privacy

Unity Catalog metadata confirms that `fact_compensation` exposes only identifiers, dates, `compa_ratio`, `range_penetration`, `pay_position_band`, `below_band_midpoint_flag`, and `bonus_pct_of_base`. It exposes zero raw `base_salary`, `annual_bonus`, `band_min`, `band_mid`, `band_max`, or `currency` columns.

## Deployment

- `databricks bundle validate --strict -t dev --profile genie-workbench` completed successfully.
- The existing `../src/pipeline/**` library glob automatically included `src/pipeline/gold/facts.sql`; no resource-definition change was required.
- Job run `24365280429776` terminated with `SUCCESS`.
- Pipeline update `9f70c7ed-566a-4fc9-8793-de4d05e54ec5` completed successfully and returned the pipeline to `IDLE`.
