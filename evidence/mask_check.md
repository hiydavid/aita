# Aita Compensation Mask Check

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Governance group: `aita_hr_admin` (`2120313189110874`)
- Mask function: `genie_workbench_dev_catalog.aita_gold.mask_compensation`
- HR administrator verified: `david.huang@databricks.com`
- Result: `PASS`

## Function and Attachment

- The scalar mask accepts and returns `DECIMAL(18,4)`.
- It returns the input for members of `aita_hr_admin` and null for all other users.
- `DESCRIBE TABLE EXTENDED` confirms the function is attached to `base_salary`, `bonus`, and `pay_position_to_midpoint`.
- No row filter is attached.

## Verification Query

```sql
SELECT
  employee_id,
  compensation_year,
  base_salary,
  bonus,
  band_min,
  band_mid,
  band_max,
  pay_position_to_midpoint
FROM genie_workbench_dev_catalog.aita_gold.fact_compensation
ORDER BY employee_id, compensation_year
LIMIT 5;
```

## Non-HR Result

The query ran as `david.huang@databricks.com` while `is_member('aita_hr_admin')` was false.

| employee_id | year | base_salary | bonus | band_min | band_mid | band_max | pay_position_to_midpoint |
|---|---:|---:|---:|---:|---:|---:|---:|
| EMP000001 | 2025 | NULL | NULL | 41600.00 | 52000.00 | 65000.00 | NULL |
| EMP000001 | 2026 | NULL | NULL | 41600.00 | 52000.00 | 65000.00 | NULL |
| EMP000002 | 2025 | NULL | NULL | 41600.00 | 52000.00 | 65000.00 | NULL |
| EMP000002 | 2026 | NULL | NULL | 41600.00 | 52000.00 | 65000.00 | NULL |
| EMP000003 | 2025 | NULL | NULL | 41600.00 | 52000.00 | 65000.00 | NULL |

Across all 40,000 compensation rows, the three governed personal-pay columns were null and all three visible band columns were populated.

## HR-Admin Result

After explicit approval, `david.huang@databricks.com` was added to `aita_hr_admin`. The same query then ran while `is_member('aita_hr_admin')` was true.

| employee_id | year | base_salary | bonus | band_min | band_mid | band_max | pay_position_to_midpoint |
|---|---:|---:|---:|---:|---:|---:|---:|
| EMP000001 | 2025 | 54399.0700 | 5828.8600 | 41600.00 | 52000.00 | 65000.00 | 1.0461 |
| EMP000001 | 2026 | 58056.9600 | 5371.7200 | 41600.00 | 52000.00 | 65000.00 | 1.1165 |
| EMP000002 | 2025 | 55895.4200 | 10788.3800 | 41600.00 | 52000.00 | 65000.00 | 1.0749 |
| EMP000002 | 2026 | 56969.9500 | 3004.0300 | 41600.00 | 52000.00 | 65000.00 | 1.0956 |
| EMP000003 | 2025 | 49413.3100 | 5149.3600 | 41600.00 | 52000.00 | 65000.00 | 0.9503 |

Across all 40,000 compensation rows, HR-admin members could see all three governed personal-pay columns and all three band columns remained populated.
