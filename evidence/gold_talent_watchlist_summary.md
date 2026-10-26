# Aita Gold Talent Watchlist

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Successful job run ID: `618778647851719`
- Successful pipeline update ID: `30cecb4b-3be0-4180-9d69-8c79bc38fe14`
- Result: `PASS`

## Implementation

- `talent_watchlist` publishes one row per current employee with at least one risk signal.
- `risk_flags` and `reasons` are aligned arrays, and `signal_count` is the number of emitted flags.
- The stalled-high-performer rule uses the latest performance and compensation records, at least three years of tenure, and no promotion during the prior 36 months.
- The disengaging rule uses either two consecutive declines across the latest three survey waves or a latest comment classified as burnout.
- The team-at-risk rule uses trailing-12-month voluntary exits divided by average monthly headcount. The threshold is twice the bank-wide average rate and requires at least one manager or schedule-and-workload exit reason.
- The hard-to-backfill rule requires another watchlist flag, a licensed or strategic role, and job-family average time to fill above the bank median.
- The deterministic watchlist `as_of_date` is the maximum business date across its gold inputs.

## Grain and Contract Checks

| Check | Result |
|---|---:|
| Total rows | 3,427 |
| Distinct employees | 3,427 |
| Null employee, business-line, or as-of values | 0 |
| Signal-count mismatches | 0 |
| Reason-count mismatches | 0 |
| Empty signal rows | 0 |
| Uncombined hard-to-backfill rows | 0 |
| Distinct as-of dates | 1 |
| As-of date | 2026-12-31 |

## Signal Counts

| Risk flag | Employees |
|---|---:|
| `stalled_high_performer` | 969 |
| `disengaging` | 2,199 |
| `team_at_risk` | 418 |
| `hard_to_backfill_risk` | 311 |

The 3,427 employees form ten valid signal combinations. All 311 hard-to-backfill flags matched the licensed-or-strategic, above-median fill-time, and combined-risk rule.

## Threshold Results

- The trailing-12-month team-risk threshold was 5.3% voluntary attrition.
- `ORG001` had a 35.2% rate and `ORG002` had a 15.8% rate.
- These were the only two organization units above the rule threshold with qualifying exit reasons.
- The bank median job-family time to fill was 45.4 days.

## Planted-Pattern Coverage

| Pattern check | Result |
|---|---:|
| Active planted stalled employees flagged | 504 / 504 |
| Active fraud-operations employees flagged as disengaging | 522 / 522 |
| Planted contact-center organization units flagged | 2 / 2 |
| Unexpected team-at-risk organization units | 0 |

The active-employee watchlist excludes departed employees by design. This accounts for the difference between the 504 active planted stalled employees and the 506 employees in the generation-time pattern check.

## Deployment

- `databricks bundle validate --strict -t dev --profile genie-workbench` completed successfully.
- The existing `../src/pipeline/**` library glob included `src/pipeline/gold/talent_watchlist.sql` without a resource-definition change.
- Job run `618778647851719` terminated with `SUCCESS` in serverless `STANDARD` mode.
- Pipeline update `30cecb4b-3be0-4180-9d69-8c79bc38fe14` completed successfully and returned the pipeline to `IDLE`.
