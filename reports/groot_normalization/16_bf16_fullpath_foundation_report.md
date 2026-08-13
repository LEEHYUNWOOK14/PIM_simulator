# BF16 workload-independent full-path foundation report

## Verdict

**SUPERSEDED FUNCTIONAL AND GENERIC-SYNTHESIS PASS.** BF16 now spans
add/multiply, scalar and vector SUM/SUMSQ, LUT256 RSQRT, scalar finalize, affine
apply, cross-bank reduction, hierarchical normalization, and the normalization
parameter propagated into `full_pim_system_top`. No GR00T workload parameter was
selected or inferred. Sky130HD timing evidence added after this checkpoint is
recorded in `17_workload_independent_physical_and_robustness_report.md`.

## Functional evidence

| Scope | Evidence | Result |
|---|---|---|
| BF16 add/multiply | 20,256 Python-reference edge/random pairs | PASS |
| BF16 RSQRT | all 65,536 input bit patterns, output stalls | PASS |
| BF16 scalar finalize | 2,048 stage-bit-exact vectors | PASS |
| BF16 bank reducer/apply | directed ordinary/special/backpressure cases | PASS |
| BF16 pipelined vector reducer | 2/4/8/16 lanes, II=1, tagged output stall | PASS |
| BF16 hierarchical end-to-end | RMSNorm + LayerNorm, 4 banks, 32 outputs | PASS |
| BF16 reduced full-system top | parameter elaboration, proc, opt, check -assert | PASS |

The scalar vectors independently calculate sequentially rounded SUM/SUMSQ to
mean, variance/clamp, epsilon, LUT RSQRT, and expected metadata. FP16 and BF16
use separate generated files and separate RTL elaborations.

## Generic synthesis comparison

`results/normalization_synthesis_metrics.csv` contains 18 directly comparable
FP16/BF16 tree points. These are Yosys generic cells and topological path lengths,
not micrometre area or nanosecond timing.

- Combinational tree: lanes 1/2/4/8/16 for FP16 and BF16.
- Pipelined tree: lanes 2/4/8/16 for FP16 and BF16.
- FP16 pipelined path proxy is 333 at every measured lane count.
- BF16 pipelined path proxy is 280 at every measured lane count.
- Cell count remains approximately linear with lanes in both formats.

No lane count is selected by this report. Generic counts cannot replace a
technology-mapped area/timing/power decision.

## Full-top synthesis distinction

The scalar, reduction, and hierarchical tops complete normal Yosys synthesis and
`check -assert` for both formats. The reduced `full_pim_system_top` completes
parameter elaboration, process lowering, cleanup, and `check -assert`. Full-top
generic technology mapping is intentionally kept separate because this local
Yosys 0.52 flow expands DRAM/register arrays and exceeded the command window;
the arithmetic hierarchy already has complete generic synthesis evidence.

## Commands

```bash
bash verification/groot_normalization/run_bf16_rsqrt_test.sh
bash verification/groot_normalization/run_normalization_scalar_test.sh
bash verification/groot_normalization/run_hierarchical_normalization_test.sh
bash verification/groot_normalization/run_bank_normalization_pipelined_vector_reducer_test.sh
bash verification/groot_normalization/run_normalization_fullpath_synthesis.sh
python3 tools/collect_normalization_synthesis_metrics.py
```

## Still open

- Broader reset-during-transaction tests for scalar, reduction, and hierarchical
  paths beyond the bank apply contract test.
- Explicit NaN/Inf policy tests at end-to-end normalization level; primitive
  policies are already exhaustive.
- Sky130HD mapping and OpenROAD timing were subsequently completed for 2/4-lane
  candidates; VCD/SAIF and power/energy evidence remain separate work.
- HBM2 PHY, vendor macro, CDC/DFT, and full-chip signoff are out of scope and are
  not implied by these results.
- Final lane/PCU/FIFO/buffer/offload choices remain deferred to GR00T evidence.
