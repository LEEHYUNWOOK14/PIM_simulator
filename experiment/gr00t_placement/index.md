# GR00T Placement Index

Start here:

1. [`README.md`](README.md)
2. [`decision_memo.md`](decision_memo.md)
3. [`claim_map.md`](claim_map.md)
4. [`recommendation.json`](recommendation.json)

Supporting evidence:

- [`results/summary.json`](results/summary.json)
- [`results/analysis_stdout.json`](results/analysis_stdout.json)
- [`sources.json`](sources.json)
- [`assumptions.json`](assumptions.json)

Current decision:

- `withheld_pending_rtl_and_model_calibration`

Current provisional winners:

- Balanced: `(0.0 mm, 0.0 mm)`
- Thermal-first: `(0.0 mm, 0.0 mm)`
- Performance-first: `(0.0 mm, 0.0 mm)`
- Cost-first: `(0.0 mm, 0.0 mm)`

Main caveats:

- Thermal values are from an uncalibrated compact RC model.
- TSV, microbump, PHY, package dimensions, and power are assumptions.
- The current GDS is a reduced logic block with negative setup slack at 10 ns.
- The GR00T workload uses synthetic FP16 normalization inputs, not full BF16 inference activations.
