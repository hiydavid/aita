# Raw Execution Log

Phase 18 evidence from October 28, 2026 (America/Los_Angeles). Code blocks preserve exact output lines or exact JSON after the shown filters; credentials are omitted. All Databricks commands used profile `genie-workbench`, target `dev` where applicable, and warehouse `813b0ad2f3036e46` for SQL.

## Fresh Pipeline Run

`2026-10-29T03:55:20Z`

`$ databricks jobs get-run 1070492872189033 ... | jq -c '{run_id,result_state:.state.result_state,tasks:(.tasks|map({key:.task_key,value:.state.result_state})|from_entries)}'`

```text
{"run_id":1070492872189033,"result_state":"SUCCESS","tasks":{"sync_lakebase":"SUCCESS","sdp_pipeline":"SUCCESS","gold_governance":"SUCCESS","generate_data":"SUCCESS","publish_semantics":"SUCCESS"}}
{"pipeline":"aita_sdp","update_id":"c7639109-608b-4907-838a-97c0f694a82b","state":"COMPLETED"}
{"pipeline":"talent_watchlist_serving","update_id":"4b8275d5-15a3-448a-84f3-a06d3d7e82f1","state":"COMPLETED"}
```

## Pipeline SQL

`2026-10-29T03:42:40Z`

`$ databricks experimental aitools tools query "SELECT ... FROM event_log(TABLE(...)) ..." | jq -c '[.[]|{expectation,passed,failed}]'`

```json
[{"expectation":"requisition_exists","passed":"28800","failed":"0"},{"expectation":"base_salary_within_band","passed":"40000","failed":"0"},{"expectation":"engagement_score_between_1_and_5","passed":"155063","failed":"0"},{"expectation":"exit_comment_not_empty","passed":"1161","failed":"0"},{"expectation":"job_code_not_null","passed":"60","failed":"0"},{"expectation":"performance_rating_allowed","passed":"40000","failed":"0"},{"expectation":"close_date_on_or_after_open_date","passed":"2400","failed":"0"},{"expectation":"event_date_on_or_after_hire_date","passed":"20000","failed":"0"},{"expectation":"hire_date_not_null","passed":"20000","failed":"0"},{"expectation":"valid_business_line","passed":"20000","failed":"0"}]
```

`2026-10-29T03:42:53Z`

`$ databricks experimental aitools tools query --file src/generate/pattern_checks.sql ... | jq -c '[.[]|{check_name,status,primary_metric}]'`

```json
[{"check_name":"01_contact_center_attrition","status":"PASS","primary_metric":"0.1942"},{"check_name":"02_stalled_high_performers","status":"PASS","primary_metric":"506.0"},{"check_name":"03_fraud_operations_burnout","status":"PASS","primary_metric":"1.537"},{"check_name":"04_standout_managers","status":"PASS","primary_metric":"3.0"},{"check_name":"05_genai_internal_mobility","status":"PASS","primary_metric":"738.0"},{"check_name":"06_licensed_role_hiring","status":"PASS","primary_metric":"2.118"},{"check_name":"07_contact_center_backfills","status":"PASS","primary_metric":"164.0"}]
```

`2026-10-29T03:43:36Z`

`$ databricks experimental aitools tools query --file src/semantic/validation.sql ... | jq '{checks:length,...}'`

```json
{"checks":13,"passed":13,"violations":0}
```

`$ databricks experimental aitools tools query --file src/semantic/metric_validation_*.sql ... | jq -s 'add|{checks:length,...}'`

```json
{"checks":12,"passed":12,"violations":0}
```

## AI and Governance

`2026-10-29T03:44:10Z`

`$ databricks experimental aitools tools query "SELECT function_name,input_text,output_label ..." | jq -c '[.[]|select(...)]'`

```json
[{"function_name":"ai_classify + ai_analyze_sentiment engagement","input_text":"Sustained overtime and rising workload are causing burnout; staffing has not kept pace with fraud alerts.","output_label":"theme=burnout; sentiment=negative"},{"function_name":"ai_classify + ai_analyze_sentiment exit","input_text":"The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role.","output_label":"reason=schedule and workload; sentiment=negative"},{"function_name":"ai_classify job exposure","input_text":"Resolve customer requests across phone and chat using scripted knowledge, summarization, and case routing. Generative AI can augment this contact center representative role while empathy and escalation judgment remain essential.","output_label":"high"},{"function_name":"ai_extract demonstrated skills","input_text":"Reliable performance with strong customer focus, controls, and collaboration.","output_label":"customer focus, controls, collaboration"}]
```

`2026-10-29T03:44:52Z`

`$ databricks experimental aitools tools query "DESCRIBE TABLE EXTENDED ...fact_compensation" | jq '[...mask_compensation...]|map({col_name,data_type})'`

```json
[{"col_name":"# Column Masks","data_type":""},{"col_name":"base_salary","data_type":"`genie_workbench_dev_catalog`.`aita_gold`.`mask_compensation`"},{"col_name":"bonus","data_type":"`genie_workbench_dev_catalog`.`aita_gold`.`mask_compensation`"},{"col_name":"pay_position_to_midpoint","data_type":"`genie_workbench_dev_catalog`.`aita_gold`.`mask_compensation`"}]
```

## Genie and Router

`2026-10-29T03:45:10Z`

`$ python3 src/genie/manage_agents.py check-sql ... | awk ...`

```text
PASS total=36 workforce_attrition=12 talent_performance=12 recruiting=12
```

`2026-10-29T03:46:56Z`

`$ python3 src/genie/evaluate_agent.py <agent> ...; grep -c '^COMPLETE ' <output>` (three Agents)

```text
workforce_attrition COMPLETE=10
talent_performance COMPLETE=10
recruiting COMPLETE=10
```

`2026-10-29T03:28:25Z`

`$ TOKEN=$(databricks auth token genie-workbench ...); npx appkit agent eval aita --header "Authorization: Bearer $TOKEN" --strict --concurrency 1 ...`

```text
[1/1] ✓ aita/routing — Routes three canonical questions to each domain Agent
PASS — 1 passed, 0 failed, 0 skipped (1 total)
```

## Lakebase and App

`2026-10-29T03:50:06Z`

`$ curl -H "Authorization: Bearer $TOKEN" "$URL/api/foundation" | jq ...`

```json
{"deployment":"owner-only","genieAliases":["workforce_attrition","talent_performance","recruiting"],"genieExecution":"on-behalf-of-user","lakebaseExecution":"service-principal","threadStore":"lakebase","watchlist":{"row_count":3427,"distinct_employee_id":3427,"null_employee_id":0,"max_as_of_date":"2026-12-31"}}
```

`$ curl -H "Authorization: Bearer $TOKEN" "$URL/api/watchlist?pageSize=1" | jq ...`

```json
{"reviewSummary":{"reviewed":1,"total":3427},"freshness":{"asOfDate":"2026-12-31","stale":false},"parity":{"rowCount":3427,"distinctEmployeeId":3427,"nullEmployeeId":0,"passed":true}}
```

`$ curl -X POST -H "Authorization: Bearer $TOKEN" ... "$URL/api/watchlist/EMP002939/review"`

```text
{"review":{"status":"reviewed","note":"Phase 18 execution evidence verification.","reviewer":"3101383667725164@7474649446784190","createdAt":"2026-10-29T03:50:08.320Z"}}
HTTP 201
```

`$ curl -X POST ... --data '{"status":"approved"}' ...; curl "$URL/api/watchlist"`

```text
{"error":"Invalid watchlist review"}
HTTP 400
{}HTTP 401
```

`2026-10-29T03:27:10Z`

`$ databricks apps get aita-david-huang ... | jq ...`

```json
{"name":"aita-david-huang","app_status":"RUNNING","compute_status":"ACTIVE","deployment_status":"SUCCEEDED","resource_names":["orchestrator-endpoint","postgres","genie-workforce-attrition","genie-talent-performance","genie-recruiting"]}
```
