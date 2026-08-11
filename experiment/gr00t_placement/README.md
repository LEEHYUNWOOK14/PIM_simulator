# GR00T Placement Exploration

This folder tracks the GR00T-driven HBM2 logic-die placement study.

## Current state

- Target model: `nvidia/GR00T-N1.7-3B`
- Model revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- Final recommendation status: `withheld_pending_rtl_and_model_calibration`

## What to read first

1. [`decision_memo.md`](decision_memo.md)
2. [`claim_map.md`](claim_map.md)
3. [`summary.json`](results/summary.json)
4. [`analysis_stdout.json`](results/analysis_stdout.json)
5. [`sources.json`](sources.json)
6. [`assumptions.json`](assumptions.json)
7. [`../report_97_gr00t_placement_uncertainty_and_cost_v2.md`](../report_97_gr00t_placement_uncertainty_and_cost_v2.md)
8. [`../report_98_gr00t_logic_die_scheduler_trace_replay.md`](../report_98_gr00t_logic_die_scheduler_trace_replay.md)

## Key measured facts

- 333 candidate placements evaluated
- 15 Pareto candidates
- Baseline center placement at `(0.0 mm, 0.0 mm)`
- Balanced-profile winner at `(0.0 mm, 0.0 mm)`
- Candidate-level constraints: `293/333` pass
- Signoff hard constraints: `0/333` pass
- Provisional center Monte Carlo mode win rate: `94.7%`
- Center top-5 rate: `97.2%`, but the overall gate still fails

## Validation limits

- Thermal values are from an uncalibrated compact RC model.
- TSV, microbump, PHY, package dimensions, and power are explicit assumptions.
- The current GDS is a reduced logic block with negative setup slack under the current 10 ns constraint.
- The GR00T workload uses deterministic synthetic FP16 normalization inputs, not full BF16 inference activations.

## Reproduction

Run the placement analysis from the repository root:

```powershell
.\tools\reproduce_gr00t_placement_pre_rtl.ps1
```

The generated plots and tables are written under `results/`.
