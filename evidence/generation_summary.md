# Aita Synthetic Data Generation

- Run date: 2026-10-24
- Databricks profile: `genie-workbench`
- Seed: `20261024`
- Landing path: `/Volumes/genie_workbench_dev_catalog/aita_bronze/landing`

## Dataset Counts

| Dataset | Rows |
|---|---:|
| workers | 20,000 |
| job_history | 28,504 |
| org_units | 72 |
| jobs | 60 |
| engagement_surveys | 155,063 |
| exit_interviews | 1,161 |
| team_productivity | 1,728 |
| performance_reviews | 40,000 |
| compensation | 40,000 |
| requisitions | 2,400 |
| applications | 28,800 |
| application_events | 86,240 |

## Pattern Checks

| Pattern | Status | Evidence |
|---|---|---|
| Contact-center attrition spike | PASS | 108 spike exits; 95.4% under the three target managers; 95.4% of exit comments mention schedule or workload |
| Stalled strategic high performers | PASS | 506 workers are high performers below band midpoint with 3+ years and no recent promotion |
| Fraud-operations burnout | PASS | Engagement fell 1.537 points; overtime grew 2.456x; 100% of late comments mention burnout, overtime, or workload |
| Standout managers | PASS | 3 managers combine high engagement, high CSAT, and less than half the company attrition rate |
| GenAI internal mobility | PASS | 738 internal applicants moved from GenAI-exposed operations roles toward technology roles using adjacent skills |
| Licensed-role hiring friction | PASS | Licensed roles take 2.118x as long to fill; compensation or competing offers explain 100% of licensed-role declines |
| Contact-center backfills | PASS | 164 post-spike backfills versus 3 in the baseline period; 100% link to an exit in the prior 90 days |
