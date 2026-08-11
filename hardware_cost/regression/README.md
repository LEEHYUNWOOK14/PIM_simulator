# Hardware-cost revision regression

This pipeline freezes provisional RTL/physical snapshots and compares later RTL
revisions without selecting final PIM architecture parameters. It is deliberately
separate from the GR00T workload exploration.

Each snapshot records:

- Yosys generic cell count and topological path observations;
- technology-mapped area, critical-path time, and slack when available;
- block dynamic/leakage power and the mapped physical area;
- workload operation count, latency, throughput, and energy/op when available;
- peak temperature and hotspot from the 3-D thermal solver;
- calibration level and source hash for every observation;
- five non-overlapping cost categories: `bf16_fp16`,
  `normalization_rounding`, `accumulator_reduction`, `buffer_register`, and
  `control_routing`.

Missing timing or workload metrics remain `null`; generic Yosys path length is
never mislabeled as nanoseconds. A snapshot may contain both FP16 and BF16
candidate observations. This preserves evidence without deciding which precision
or architecture is final.

## Capture and compare

```powershell
.\tools\run_hardware_cost_regression.ps1
```

To capture a later revision, copy `baseline_manifest.json`, change
`revision_id`, point it to the new reports, and run:

```powershell
.\.venv\Scripts\python.exe tools\capture_hardware_cost_revision.py `
  --manifest path\to\revision_manifest.json `
  --output hardware_cost\regression\revisions\revision-name.json

.\.venv\Scripts\python.exe tools\compare_hardware_cost_revisions.py `
  --revisions hardware_cost\regression\revisions `
  --baseline provisional_baseline_2026_08_11 `
  --output reports\hardware_cost_regression
```

Generated paper artifacts include a revision table, category table, delta table,
Markdown report, and PNG plots. The baseline manifest points to the existing
synthetic RTL-to-3D data and frozen workload-independent Yosys evidence. The
small frozen evidence file retains the SHA-256 of each original log so concurrent
GR00T work cannot silently move the baseline.
An observation may additionally provide `technology_mapped_area_um2`,
`critical_path_ns`, `slack_ns`, and `calibration`; absent fields remain `null`.
`primary_observation` can identify the candidate under test so its technology
area/timing appears in the revision table. This is an evaluation selector, not a
final architecture decision, and the snapshot still requires
`final_architecture_parameters_selected: false`.

## Calibration levels

| Level | Meaning |
|---|---|
| `synthetic` | Explicit architectural stimulus or placeholder geometry |
| `synthesis_generic` | Generic Yosys cells/path; not area or timing |
| `technology_mapped` | Characterized standard-cell area/timing |
| `placed` | Physical placement/floorplan result |
| `activity_based` | VCD/SAIF-based power with library and operating point |
| `post_route` | Extracted parasitic timing/power |
| `measured` | Calibrated measurement |

## GR00T boundary

`gr00t_workload_schema.json` defines the future workload exchange contract and
`gr00t_pending.json` is an intentionally empty adapter payload. The regression
tool may consume a completed payload later, but it rejects any payload claiming
that final architecture parameters have already been selected. This pipeline
does not run GR00T and does not alter its reports.
