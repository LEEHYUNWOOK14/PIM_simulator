# Hardware-cost revision regression

Baseline: `synthetic_low_area`

> All revisions are provisional. GR00T-driven final architecture parameters are intentionally not selected.

## Paper revision table

|Revision|Physical gate|RTL freeze|Cells|Area (um^2)|Path (ns)|Throughput (op/s)|Power (W)|Energy/op (J)|Peak (K)|Calibrations (A/T/P/W/Th)|Area Δ|Path Δ|Throughput Δ|Power Δ|Peak Δ|
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
|synthetic_low_area|PENDING|False|80000|8000000.0|12.000|1000000000.0|3.000|N/A|318.000|synthetic / synthetic / synthetic / workload_model / synthetic_architectural|0.000% (quantitative)|0.000% (quantitative)|0.000% (quantitative)|0.000% (quantitative)|0.000 K (quantitative)|
|synthetic_balanced|PENDING|False|105000|10000000.0|9.000|1800000000.0|3.800|N/A|322.000|synthetic / synthetic / synthetic / workload_model / synthetic_architectural|25.000% (quantitative)|-25.000% (quantitative)|80.000% (quantitative)|26.667% (quantitative)|4.000 K (quantitative)|
|synthetic_high_performance|PENDING|False|150000|14000000.0|7.000|2400000000.0|5.500|N/A|334.000|synthetic / synthetic / synthetic / workload_model / synthetic_architectural|75.000% (quantitative)|-41.667% (quantitative)|140.000% (quantitative)|83.333% (quantitative)|16.000 K (quantitative)|

## Cost-category table

|Revision|Category|Mapped area (um^2)|Power (W)|FP16 cells|BF16 cells|Area calibration|Power calibration|
|---|---|---:|---:|---:|---:|---|---|
|synthetic_low_area|bf16_fp16|2560000.0|1.140|N/A|N/A|synthetic|synthetic|
|synthetic_low_area|normalization_rounding|1920000.0|0.660|N/A|80000|synthetic|synthetic|
|synthetic_low_area|accumulator_reduction|1440000.0|0.540|N/A|N/A|synthetic|synthetic|
|synthetic_low_area|buffer_register|1280000.0|0.360|N/A|N/A|synthetic|synthetic|
|synthetic_low_area|control_routing|800000.0|0.300|N/A|N/A|synthetic|synthetic|
|synthetic_balanced|bf16_fp16|3200000.0|1.444|N/A|N/A|synthetic|synthetic|
|synthetic_balanced|normalization_rounding|2400000.0|0.836|N/A|105000|synthetic|synthetic|
|synthetic_balanced|accumulator_reduction|1800000.0|0.684|N/A|N/A|synthetic|synthetic|
|synthetic_balanced|buffer_register|1600000.0|0.456|N/A|N/A|synthetic|synthetic|
|synthetic_balanced|control_routing|1000000.0|0.380|N/A|N/A|synthetic|synthetic|
|synthetic_high_performance|bf16_fp16|4480000.0|2.090|N/A|N/A|synthetic|synthetic|
|synthetic_high_performance|normalization_rounding|3360000.0|1.210|N/A|150000|synthetic|synthetic|
|synthetic_high_performance|accumulator_reduction|2520000.0|0.990|N/A|N/A|synthetic|synthetic|
|synthetic_high_performance|buffer_register|2240000.0|0.660|N/A|N/A|synthetic|synthetic|
|synthetic_high_performance|control_routing|1400000.0|0.550|N/A|N/A|synthetic|synthetic|

## Calibration comparison policy

- `quantitative`: identical calibration stages; numerical deltas are emitted.
- `reference_only`: adjacent stages; absolute values remain visible but deltas are suppressed.
- `prohibited`: stages differ by two or more levels; deltas are suppressed.
- `unavailable`: at least one required evidence axis is pending or unavailable.

## Interpretation limits

- Generic cell count is not silicon area; generic topological path length is not ns.
- Energy/op requires activity-based or stronger power evidence plus workload throughput.
- Synthetic area, power, and temperature establish regression plumbing, not absolute silicon claims.
- A zero with `not_available` calibration means no physical block was mapped for that category; it is not a measured zero-cost claim.
- Categories are exclusive for physical totals. Alternative FP16/BF16 synthesis candidates are reported separately and are never summed into a chosen architecture.
