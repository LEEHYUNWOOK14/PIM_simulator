# Hardware-cost revision regression

Baseline: `provisional_baseline_2026_08_11`

> All revisions are provisional. GR00T-driven final architecture parameters are intentionally not selected.

## Paper revision table

|Revision|Physical gate|RTL freeze|Cells|Area (um^2)|Path (ns)|Throughput (op/s)|Power (W)|Energy/op (J)|Peak (K)|Calibrations (A/T/P/W/Th)|Area Δ|Path Δ|Throughput Δ|Power Δ|Peak Δ|
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|
|provisional_baseline_2026_08_11|PENDING|False|129805|10900000.0|N/A|N/A|4.000|N/A|322.582|synthetic / not_available / synthetic / pending / synthetic_architectural|0.000% (quantitative)|N/A% (unavailable)|N/A% (unavailable)|0.000% (quantitative)|0.000 K (quantitative)|
|physical_feasibility_2026_08_12|FAIL|False|129805|10900000.0|N/A|N/A|4.000|N/A|322.582|synthetic / not_available / synthetic / pending / synthetic_architectural|0.000% (quantitative)|N/A% (unavailable)|N/A% (unavailable)|0.000% (quantitative)|0.000 K (quantitative)|

## Cost-category table

|Revision|Category|Mapped area (um^2)|Power (W)|FP16 cells|BF16 cells|Area calibration|Power calibration|
|---|---|---:|---:|---:|---:|---|---|
|provisional_baseline_2026_08_11|bf16_fp16|4800000.0|2.000|N/A|N/A|synthetic|synthetic|
|provisional_baseline_2026_08_11|normalization_rounding|0.0|0.000|129805|104699|not_available|not_available|
|provisional_baseline_2026_08_11|accumulator_reduction|750000.0|0.700|N/A|N/A|synthetic|synthetic|
|provisional_baseline_2026_08_11|buffer_register|4350000.0|1.100|N/A|N/A|synthetic|synthetic|
|provisional_baseline_2026_08_11|control_routing|1000000.0|0.200|N/A|N/A|synthetic|synthetic|
|physical_feasibility_2026_08_12|bf16_fp16|4800000.0|2.000|N/A|N/A|synthetic|synthetic|
|physical_feasibility_2026_08_12|normalization_rounding|0.0|0.000|129805|104699|not_available|not_available|
|physical_feasibility_2026_08_12|accumulator_reduction|750000.0|0.700|N/A|N/A|synthetic|synthetic|
|physical_feasibility_2026_08_12|buffer_register|4350000.0|1.100|N/A|N/A|synthetic|synthetic|
|physical_feasibility_2026_08_12|control_routing|1000000.0|0.200|N/A|N/A|synthetic|synthetic|

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
