# Semantic Helper Validation

- Run date: 2026-10-26
- Profile: `genie-workbench`
- Bundle target: `dev`
- Serverless SQL warehouse: `genie-workbench-test` (`813b0ad2f3036e46`)
- Pipeline update: `daa262c6-d33b-409c-9af0-5cd6a137059d`
- Result: `PASS`

## Published Outputs

| Output | Rows | Declared grain |
|---|---:|---|
| `semantic_workforce_monthly` | 17,436 | organization unit × job code × month |
| `semantic_talent_snapshot` | 18,839 | active employee |
| `semantic_talent_skills` | 58,656 | active employee × normalized demonstrated skill |

`dim_worker` remains at 20,000 employees, including 3,019 with promotion history. The talent snapshot uses Gold business date `2026-12-31`. The governed watchlist remains unchanged at 3,427 rows.

## Validation Results

All checks returned zero violations.

| Control | Status |
|---|---|
| `dim_worker` employee grain | PASS |
| `dim_worker.last_promotion_date` parity to Silver history | PASS |
| Workforce helper grain and source-row parity | PASS |
| Workforce movement-field and regrettable-exit parity | PASS |
| Talent snapshot employee grain and active-population parity | PASS |
| Latest performance and compensation selection | PASS |
| Stalled-high-performer parity to the governed watchlist | PASS |
| Talent-skill grain and normalized explode parity | PASS |

The workforce helper contains 680 regrettable voluntary exits. The talent snapshot and watchlist both identify 969 stalled high performers.

## Governance

`SHOW CREATE TABLE` confirms `semantic_talent_snapshot.pay_position_to_midpoint` retains `aita_gold.mask_compensation`. The HR administrator saw 18,839 populated values; the previously completed non-HR and HR function behavior remains recorded in `evidence/mask_check.md`.

The workspace group `aita_users` (`2124487482070223`) contains `david.huang@databricks.com` as its sole initial member and has no grants yet. The separate `aita_hr_admin` membership remains unchanged. No Aita app service principal exists yet; add it only after the app identity is created and approved.
