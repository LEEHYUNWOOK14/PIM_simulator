# GR00T Placement Claim Map

This page links the main study claims to the current evidence trail.
It is meant to make the analysis easy to audit, not to overstate signoff.

## Status

- Target model: `nvidia/GR00T-N1.7-3B`
- Study status: `withheld_pending_rtl_and_model_calibration`
- Current evidence shows a useful placement exploration, but not a final chip-level recommendation.

## Claim to evidence map

| Claim | Evidence | Current reading |
| --- | --- | --- |
| The study is about GR00T N1.7 on an HBM2-oriented logic die. | `S1`, `S2`, `S3`, `S4`, `README.md` | Supported by the source snapshot, release tag, model card, and HBM2 channel organization references. |
| The placement search is reproducible from local analysis artifacts. | `experiment/gr00t_placement/analyze_placement.py`, `results/summary.json`, `results/analysis_stdout.json`, `assumptions.json` | Supported. The analysis script and generated outputs are present together. |
| The search explored a nontrivial candidate set and found a Pareto set. | `results/summary.json` | Supported. Current summary reports `candidate_count: 333` and `pareto_count: 15`. |
| The center placement is a candidate-level baseline but not a final recommendation. | `results/summary.json`, `decision_memo.md` | Supported. Candidate constraints pass, but global timing fails. |
| The provisional Monte Carlo mode currently favors the center placement. | `results/summary.json` | Supported. The mode is `(0.0, 0.0)` with win rate `0.947` and top-5 rate `0.972`, but the overall gate still fails. |
| Thermal conclusions are only early-stage estimates. | `S5`, `S6`, `A3`, `results/summary.json` | Supported with caveat. Thermal values come from an uncalibrated compact RC model. |
| TSV, microbump, package, and power numbers are assumptions rather than signoff values. | `A1`, `A2`, `A4`, `A5`, `A6`, `results/summary.json` | Supported with caveat. These are explicitly labeled assumptions. |
| The OpenROAD-derived physical data is useful but not enough to close the full system problem. | `S8`, `L2`, `L3`, `L4`, `README.md` | Supported. The flow metrics exist, but the current GDS is a reduced logic block and timing is not clean. |
| The current result should not be treated as a final placement recommendation. | `results/summary.json`, `decision_memo.md`, `recommendation.json` | Supported. The robustness gate fails and the status remains withheld. |

## Important numbers

- Candidate placements evaluated: `333`
- Pareto candidates: `15`
- Baseline center placement: `(0.0 mm, 0.0 mm)`
- Baseline balanced score: `0.3789725375130252`
- Baseline max temperature: `35.55179977854542 C`
- Provisional Monte Carlo mode win rate: `0.947`
- Signoff hard-constraint feasible candidates: `0`
- Robustness gate: `failed`

## What this does not prove

- It does not prove silicon signoff.
- It does not prove the thermal model is calibrated.
- It does not prove the RTL, PPA, and package assumptions are final.
- It does not prove the current GDS represents the final chip.

## Where to continue

1. Check `README.md` for the reading order.
2. Inspect `decision_memo.md` for the human summary.
3. Use `results/summary.json` and `results/analysis_stdout.json` for the numerical trail.
4. Keep `assumptions.json` open while interpreting any placement claim.
