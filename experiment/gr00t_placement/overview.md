# GR00T Placement Overview

This folder captures the current GR00T-driven HBM2 logic-die placement study.

## What is already established

- Target model: `nvidia/GR00T-N1.7-3B`
- Model revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- Placement study status: `withheld_pending_rtl_and_model_calibration`

## Current best-known facts

- 333 candidate placements were evaluated; 293 pass candidate-level constraints.
- 15 candidates landed on the Pareto frontier.
- The center placement `(0.0 mm, 0.0 mm)` remains the provisional Monte Carlo mode.
- All four deterministic profiles select the center under the current MET1 RC model.
- The center wins 94.7% of Monte Carlo samples and has a 97.2% top-5 rate.
- No candidate passes signoff because global RTL timing is not closed.

## What the current results do and do not mean

The analysis is useful for narrowing the candidate region, but it is not yet a final recommendation.

The main limitations are still active:

- Temperature comes from an uncalibrated compact RC model.
- TSV, microbump, PHY, package dimensions, and power are explicit assumptions.
- The current GDS is a reduced logic block with negative setup slack at the current 10 ns constraint.
- The GR00T workload uses deterministic synthetic FP16 normalization inputs, not full BF16 inference activations.

## Read order

1. [`index.md`](index.md)
2. [`README.md`](README.md)
3. [`decision_memo.md`](decision_memo.md)
4. [`recommendation.json`](recommendation.json)
5. [`results/summary.json`](results/summary.json)
6. [`results/analysis_stdout.json`](results/analysis_stdout.json)

## Reproduction

```powershell
.\tools\reproduce_gr00t_placement_pre_rtl.ps1
```

Outputs are written to `experiment/gr00t_placement/results/`.
