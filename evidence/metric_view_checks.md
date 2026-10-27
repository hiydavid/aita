# Metric View Checks

## Deployment

| Item | Result |
|---|---|
| Final pipeline job run | `910806891063837` — PASS |
| Final pipeline update | `50b9c66a-d2d6-458a-8664-4f5c731317b7` — COMPLETED |
| Semantic job run | `1017977579100747` — eight publish tasks PASS; grants task FAILED, remediation DEFERRED |
| Metric views | 8 of 8 registered as `METRIC_VIEW` |

Published: `mv_workforce`, `mv_attrition`, `mv_engagement`, `mv_productivity`, `mv_talent`, `mv_talent_skills`, `mv_requisitions`, and `mv_recruiting_funnel`.

## Parity

| Validation statement | Checks | Violations |
|---|---:|---:|
| `01f1d168-6c1a-1d67-a8f4-c7d3fbe2f373` | 6 | 0 |
| `01f1d168-5a69-1a21-885c-67d71bf87b73` | 6 | 0 |

The 12 passing checks cover every required measure plus yearly semi-additive headcount, multi-month rates, previous-wave engagement, weighted productivity, zero denominators, stage conversions, and historical internal-applicant job matching.

As `aita_hr_admin`, `mv_talent` returned 18,839 active employees, 2,393 high performers, a 30.5802% below-midpoint share, and average pay position `1.04664904`. The source `semantic_talent_snapshot.pay_position_to_midpoint` remains attached to `aita_gold.mask_compensation`; the prior HR/non-HR comparison remains in `evidence/mask_check.md`.

## Access

- SQL warehouse `813b0ad2f3036e46` grants explicit `CAN USE` to `aita_users` and `aita_hr_admin`.
- Unity Catalog grants are not applied: both IDs `2124487482070223` and `2120313189110874` report `resourceType: WorkspaceGroup`, and UC returns `PRINCIPAL_DOES_NOT_EXIST` for `aita_users`.
- Account-level group provisioning is deferred because no account administrator is available. The constrained demo runs only as the project owner through existing privileges; it excludes multi-user, app service-principal, and shared Genie Agent access.
- No direct per-user grant or compensation-mask bypass is used. `src/semantic/grants.sql` remains ready to rerun when account-level groups can be assigned to the workspace.
