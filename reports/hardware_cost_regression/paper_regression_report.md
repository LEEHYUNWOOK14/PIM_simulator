# Hardware-cost revision regression

Baseline: `provisional_baseline_2026_08_11`

> All revisions are provisional. GR00T-driven final architecture parameters are intentionally not selected.

## Paper revision table

|Revision|FP16 cells|BF16 cells|Area (um^2)|Power (W)|Energy/op (J)|Peak (K)|Hotspot|Area Δ base|Power Δ base|Peak Δ base|Area Δ prev|Power Δ prev|Peak Δ prev|
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|
|provisional_baseline_2026_08_11|129805|104699|10900000.0|4.000|N/A|322.582|dram_0 (0,1)|0.000%|0.000%|0.000 K|N/A%|N/A%|N/A K|

## Cost-category table

|Revision|Category|Mapped area (um^2)|Power (W)|FP16 cells|BF16 cells|Calibration|
|---|---|---:|---:|---:|---:|---|
|provisional_baseline_2026_08_11|bf16_fp16|4800000.0|2.000|N/A|N/A|synthetic|
|provisional_baseline_2026_08_11|normalization_rounding|0.0|0.000|129805|104699|not_available|
|provisional_baseline_2026_08_11|accumulator_reduction|750000.0|0.700|N/A|N/A|synthetic|
|provisional_baseline_2026_08_11|buffer_register|4350000.0|1.100|N/A|N/A|synthetic|
|provisional_baseline_2026_08_11|control_routing|1000000.0|0.200|N/A|N/A|synthetic|

## Interpretation limits

- Generic cell count is not silicon area; generic topological path length is not ns.
- `N/A` energy/op is expected until a completed GR00T workload supplies throughput or equivalent completed-work timing.
- Synthetic area, power, and temperature establish regression plumbing, not absolute silicon claims.
- A zero with `not_available` calibration means no physical block was mapped for that category; it is not a measured zero-cost claim.
- Categories are exclusive for physical totals. Alternative FP16/BF16 synthesis candidates are reported separately and are never summed into a chosen architecture.
