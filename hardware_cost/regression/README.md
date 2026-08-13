# Hardware-cost revision regression and Evidence Contract v2

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
- evidence claim class (`measured`, `derived`, `modeled`, or `assumed`);
- toolchain, operating point, workload trace identity, and candidate metadata;
- five non-overlapping cost categories: `bf16_fp16`,
  `normalization_rounding`, `accumulator_reduction`, `buffer_register`, and
  `control_routing`.

Missing timing or workload metrics remain `null`; generic Yosys path length is
never mislabeled as nanoseconds. A snapshot may contain both FP16 and BF16
candidate observations. This preserves evidence without deciding which precision
or architecture is final.

## Evidence Contract v2

`snapshot_schema.json` is a JSON Schema Draft 2020-12 contract. Capture,
comparison, and independent-validation tools additionally enforce cross-field
calibration rules.

Every snapshot requires `schema_version: 2`, contract version 2, provisional
status, all six calibration axes, source SHA-256 and claim classes, an explicit
claim boundary, toolchain metadata, and operating-point metadata. Candidate
parameters are nullable and never imply final architecture selection.

| Declared evidence | Additional required metadata |
|---|---|
| technology-mapped or stronger area/timing | PDK, library, corner, voltage, temperature, synthesis tool/version |
| placed or stronger physical evidence | physical tool/version |
| available timing | clock constraint |
| activity-based or stronger power | power tool/version, voltage, temperature, workload trace ID |
| activity-based or stronger thermal | compatible power calibration and thermal tool/version |
| available workload | workload trace ID |

Energy/op is rejected unless throughput is non-zero and power is
`activity_based`, `post_route`, or `measured`. Synthetic power therefore cannot
be presented as workload energy efficiency.

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

Calibration is tracked independently per axis. Placed area does not upgrade
synthetic power or architectural thermal evidence.

### Cross-calibration comparison policy

| Policy | Condition | Output behavior |
|---|---|---|
| `quantitative` | identical calibration ranks | numerical delta allowed |
| `reference_only` | adjacent ranks | absolute values retained; delta suppressed |
| `prohibited` | ranks differ by two or more | delta suppressed |
| `unavailable` | an axis is pending or unavailable | delta suppressed |

The policy is recorded in `paper_delta_table.csv`. Reports expose the calibration
for area, power, thermal, and workload, preventing a synthetic-to-post-route
change from silently appearing as an improvement percentage.

## Manifest v2 candidate fields

Copy `baseline_manifest.json` for a new candidate and update its contract,
calibration, and evidence paths. Candidate metadata can remain unknown:

```json
{
  "candidate_parameters": {
    "lanes": null,
    "bank_port_mode": null,
    "scheduler_policy": null,
    "context_depth": null
  },
  "final_architecture_parameters_selected": false
}
```

## Five-adapter common output contract

`adapter_output_schema.json` defines one envelope for the five replaceable input
adapters:

| Axis | Required normalized metrics |
|---|---|
| Area | generic cells/path proxy, technology area, floorplan area, five categories |
| Timing | critical path and slack |
| Power | dynamic/leakage/total power, five categories, block breakdown |
| Workload | operation count, cycles, clock period, throughput |
| Thermal | peak temperature, rise, hotspot coordinates |

Every adapter output carries the same candidate identity and nullable candidate
parameters, calibration, claim class, tool/version, operating point, hashed
source evidence, and notes. The bundle builder rejects missing/duplicate axes,
candidate or operating-point disagreement, stale source hashes, and area/power
conservation failures before creating an Evidence Contract v2 snapshot.

Run the independent three-candidate fixture regression with:

```powershell
.\tools\run_hardware_cost_adapter_v2.ps1
```

It generates 15 adapter outputs (five axes × three candidates), three snapshots,
paper CSV/Markdown/PNG comparisons, and an independent validation report under
`output/hardware_cost_adapter_v2/` and `reports/hardware_cost_adapter_v2/`.
The fixtures represent low-area, balanced, and high-performance trade-offs. They
are explicitly synthetic and do not select an architecture or claim Energy/op.

## GR00T boundary

`gr00t_workload_schema.json` defines the future workload exchange contract and
`gr00t_pending.json` is an intentionally empty adapter payload. The regression
tool may consume a completed payload later, but it rejects any payload claiming
that final architecture parameters have already been selected. This pipeline
does not run GR00T and does not alter its reports.
