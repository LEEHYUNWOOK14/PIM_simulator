# GR00T Pre-RTL Placement Sensitivity Report

Date: 2026-08-06
Status: `withheld_pending_rtl_and_model_calibration`

This report summarizes the current GR00T-driven HBM2 logic-die placement study in a form that is easier to read than the raw analysis logs.

## 1. Summary

The current analysis supports a useful placement exploration, but not a final recommendation.

The center placement is still the provisional Monte Carlo mode, and the best low-risk reading remains to keep the result withheld until the RTL and package/model assumptions are calibrated.

## 2. Study scope

- Target model: `nvidia/GR00T-N1.7-3B`
- Model revision: `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- Isaac-GR00T revision: `b9955401d50c92a29258732e3ad6ccd579f1bdc0`
- Local normalization profile: `experiment/gr00t_placement/results/gr00t_normalization_reproduction.log`

## 3. Measured results

| Item | Value |
| --- | ---: |
| Candidate placements evaluated | 333 |
| Pareto candidates | 15 |
| Baseline placement | `(0.0 mm, 0.0 mm)` |
| Baseline balanced score | `0.2712376970782007` |
| Baseline max temperature | `35.55179977854542 C` |
| Baseline mean channel wirelength | `1950.0 um` |
| Provisional Monte Carlo win rate | `55.6%` |

Profile winners currently read as:

- Balanced: `(0.0 mm, 0.0 mm)`
- Thermal-first: `(0.0 mm, 0.0 mm)`
- Performance-first: `(0.0 mm, 0.0 mm)`
- Cost-first: `(0.0 mm, 0.0 mm)`

## 4. What the result does and does not say

What it says:

- The placement sweep is reproducible from the local analysis artifacts.
- The current candidate set is large enough to show a meaningful tradeoff surface.
- The center point remains a strong baseline under the current weighting and uncertainty model.

What it does not say:

- It does not prove silicon signoff.
- It does not prove thermal calibration.
- It does not prove the RTL is timing closed.
- It does not prove the package, TSV, and power assumptions are final.

## 5. Active caveats

- Temperature comes from an uncalibrated compact RC model.
- TSV, microbump, PHY, package dimensions, and power are explicit assumptions.
- The current GDS is a reduced logic block and has negative setup slack under the current 10 ns constraint.
- The GR00T workload uses deterministic synthetic FP16 normalization inputs, not full BF16 inference activations.

## 6. Evidence trail

Primary references:

- [`experiment/gr00t_placement/claim_map.md`](gr00t_placement/claim_map.md)
- [`experiment/gr00t_placement/decision_memo.md`](gr00t_placement/decision_memo.md)
- [`experiment/gr00t_placement/README.md`](gr00t_placement/README.md)
- [`experiment/gr00t_placement/results/summary.json`](gr00t_placement/results/summary.json)
- [`experiment/gr00t_placement/results/analysis_stdout.json`](gr00t_placement/results/analysis_stdout.json)
- [`experiment/gr00t_placement/sources.json`](gr00t_placement/sources.json)
- [`experiment/gr00t_placement/assumptions.json`](gr00t_placement/assumptions.json)

## 7. Next step

Stabilize the RTL and model/package calibration, rerun the same placement pipeline, and only then consider promoting the best candidate.
