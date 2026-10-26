# Aita Gold Comment Governance

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Successful job run ID: `74640997233422`
- Successful pipeline update ID: `baf23f7b-cfd2-421f-b52a-6e1f089cb3fe`
- Result: `PASS`

## Coverage

| Check | Total | Missing comments | Result |
|---|---:|---:|---|
| Gold tables | 13 | 0 | PASS |
| Gold columns | 187 | 0 | PASS |
| Published Bronze and Silver tables | 24 | 0 | PASS |

Pipeline-private Silver AI lookup views also define short table comments in their `CREATE OR REFRESH PRIVATE MATERIALIZED VIEW` statements.

## Extended Descriptions

`DESCRIBE TABLE EXTENDED` was run for `dim_job`, `fact_attrition_event`, and `fact_compensation`.

### `dim_job`

- Table comment: One row per job code with role attributes and AI-derived GenAI exposure and required skills. Used across talent and recruiting analysis.
- `genai_exposure_tier`: AI-classified from `job_description` using `ai_classify`. Values: high, medium, low.
- `required_skills`: AI-extracted from `job_description` using `ai_extract`; each element is a concise required skill.

### `fact_attrition_event`

- Table comment: One row per voluntary or involuntary exit with departure context, AI-classified exit signals, and a latest-review regrettable flag. Used for attrition analysis.
- `exit_reason`: AI-classified from `exit_comment` using `ai_classify`. Values: compensation, manager, schedule and workload, career growth, relocation, other.
- `regrettable_flag`: true when the exiting employee had `rating_numeric` 4 or 5 in the latest performance review; false when the latest rating was lower or absent.

The table contains 1,161 exit rows, 890 regrettable rows, and zero rows that disagree with the documented latest-review rule.

### `fact_compensation`

- Table comment: One row per employee and compensation year with masked personal pay, visible pay-band policy fields, and pay-position indicators. Used for governed compensation analysis.
- The table contains 40,000 rows and 40,000 distinct compensation identifiers.
- `annual_bonus` is exposed under the governed name `bonus`.
- `compa_ratio` is replaced by the governed name `pay_position_to_midpoint`.
- Legacy columns `annual_bonus`, `compa_ratio`, `range_penetration`, and `bonus_pct_of_base` are absent.
- `band_min`, `band_mid`, and `band_max` are documented as visible policy data and contain no null values.
