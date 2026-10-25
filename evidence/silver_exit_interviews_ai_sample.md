# Exit Interview AI Sample

- Run date: 2026-10-25
- Databricks profile: `genie-workbench`
- Bundle target: `dev`
- Job run ID: `903360430328551`
- Pipeline update ID: `6adf54c1-b3c4-4e71-84c1-2c0e742bf05f`
- Result: `SUCCESS`
- Sample table rows: 200

## Expectation Result

| Expectation | Passed | Failed |
|---|---:|---:|
| `exit_comment_not_empty` | 200 | 0 |

## Sample Outputs

| Exit interview | Exit comment | Exit reason | Sentiment |
|---|---|---|---|
| EXIT-EMP000001 | The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role. | schedule and workload | negative |
| EXIT-EMP000031 | I am relocating outside the bank's current operating footprint. | relocation | neutral |
| EXIT-EMP000066 | I wanted clearer priorities, more consistent coaching, and stronger support from my manager. | manager | negative |
| EXIT-EMP000133 | My compensation fell behind comparable banking roles, so I accepted a better offer. | compensation | mixed |
| EXIT-EMP000216 | My compensation fell behind comparable banking roles, so I accepted a better offer. | compensation | mixed |
| EXIT-EMP000289 | The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role. | schedule and workload | negative |
| EXIT-EMP000361 | The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role. | schedule and workload | negative |
| EXIT-EMP000505 | I could not see a timely path to promotion or broader responsibilities. | career growth | negative |
| EXIT-EMP000525 | My compensation fell behind comparable banking roles, so I accepted a better offer. | compensation | mixed |
| EXIT-EMP000642 | I wanted clearer priorities, more consistent coaching, and stronger support from my manager. | manager | negative |
| EXIT-EMP000698 | I am leaving for a combination of personal priorities and a different opportunity. | career growth | neutral |
| EXIT-EMP000730 | I am relocating outside the bank's current operating footprint. | relocation | neutral |
| EXIT-EMP000801 | I wanted clearer priorities, more consistent coaching, and stronger support from my manager. | manager | negative |
| EXIT-EMP000852 | I am leaving for a combination of personal priorities and a different opportunity. | career growth | neutral |
| EXIT-EMP000901 | My compensation fell behind comparable banking roles, so I accepted a better offer. | compensation | mixed |
| EXIT-EMP000967 | I am relocating outside the bank's current operating footprint. | relocation | neutral |
| EXIT-EMP001088 | My compensation fell behind comparable banking roles, so I accepted a better offer. | compensation | mixed |
| EXIT-EMP001154 | The schedule change created unpredictable shifts and an unsustainable workload. My manager could not provide flexibility, so I accepted another role. | schedule and workload | negative |
| EXIT-EMP001251 | I am relocating outside the bank's current operating footprint. | relocation | neutral |
| EXIT-EMP001300 | I wanted clearer priorities, more consistent coaching, and stronger support from my manager. | manager | negative |

## Review Note

The explicit schedule, relocation, manager, compensation, and career-growth comments classified consistently. The generic personal-priorities comment classified as `career growth` rather than `other`, so the label definitions may benefit from descriptions or classification instructions before removing the 200-row limit.
