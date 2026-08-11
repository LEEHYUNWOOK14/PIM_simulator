# GR00T Placement Decision Memo

Date: 2026-08-06

This memo records the current placement exploration state for the GR00T-driven HBM2 logic-die study.

## What is being studied

- Target model: `nvidia/GR00T-N1.7-3B`
- Model revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- Local normalization profile: `experiment/gr00t_placement/results/gr00t_normalization_reproduction.log`

## What is already measured

The current placement model is based on a reduced HBM2 logic-die layout, not a final signoff package.

- Candidate placements evaluated: 333
- Pareto points found: 15
- Baseline center placement: `(0.0 mm, 0.0 mm)`
- Baseline balanced score: `0.3789725375130252`
- Baseline max temperature: `35.5518 C` unvalidated compact-RC estimate
- Baseline mean channel wirelength: `1950.0 um`

The provisional Monte Carlo mode also lands at the center point:

- `provisional_monte_carlo_mode`
- Win rate: `94.7%` (95% Wilson interval 93.13% to 95.93%)
- Top-5 rate: `97.2%`
- Signoff hard-constraint candidates: `0/333`
- Reason it is not a final recommendation: RTL/PPA and thermal/package calibration are still unstable

## Current winners by profile

- Balanced: `(0.0 mm, 0.0 mm)`
- Thermal-first: `(0.0 mm, 0.0 mm)`
- Performance-first: `(0.0 mm, 0.0 mm)`
- Cost-first: `(0.0 mm, 0.0 mm)`

## Validation limits

The following warnings remain active and must stay visible in any follow-up report:

- Temperature is from an uncalibrated compact RC model.
- TSV, microbump, PHY, package dimensions, and power are explicit assumptions.
- The current GDS is a reduced logic block and has negative setup slack under the current 10 ns constraint.
- The GR00T workload uses deterministic synthetic FP16 normalization inputs, not full BF16 inference activations.

## Decision status

Status: `withheld_pending_rtl_and_model_calibration`

Interpretation:

- The analysis is strong enough to narrow the candidate region.
- It is not strong enough to publish a final placement recommendation yet.
- The next step should be RTL stabilization plus model/package calibration, then rerun the same placement pipeline.

## Key files

- `experiment/gr00t_placement/assumptions.json`
- `experiment/gr00t_placement/sources.json`
- `experiment/gr00t_placement/results/summary.json`
- `experiment/gr00t_placement/results/analysis_stdout.json`
- `experiment/gr00t_placement/results/provisional_placement.json`
