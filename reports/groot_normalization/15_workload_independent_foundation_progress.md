# Workload-independent normalization foundation progress

## Verdict

**SUPERSEDED PARTIAL PASS.** The existing FP16 normalization regressions remain green. A
ready/valid backpressure defect in the bank apply path was repaired, BF16
arithmetic and bank reducer/apply support were added, and deterministic
regression/synthesis gates were introduced. Full BF16 scalar/RSQRT/hierarchical
integration and technology-mapped timing/power remain open, so the foundation
goal was not complete at this checkpoint. BF16 full-path progress after this
checkpoint is recorded in `16_bf16_fullpath_foundation_report.md`.

## Implemented in this step

1. `bank_normalization_apply` no longer treats a producer holding valid during
   downstream backpressure as an error. Missing context and tag mismatch remain
   errors.
2. `bf16_add` and `bf16_mul` implement BF16 ordinary, zero, subnormal,
   overflow/underflow, infinity, and canonical NaN cases.
3. `bank_normalization_local_reducer` and `bank_normalization_apply` now expose
   compile-time `DATA_FORMAT=0/1` FP16/BF16 selection.
4. An interface-contract test covers stalled valid/payload stability, same-cycle
   consume-and-replace, asynchronous reset while stalled, and true no-context
   error detection.
5. A Python-generated BF16 reference suite covers 20,256 edge/random operand
   pairs for both add and multiply.
6. A unified regression produces
   `results/foundation_regression_results.csv`.

## Verification evidence

| Gate | Result |
|---|---|
| Existing FP16 normalization functional scripts (8) | PASS |
| Pipelined vector reducer lane tests 2/4/8/16 | PASS |
| Ready/valid and reset interface contract | PASS |
| BF16 arithmetic random/reference, 20,256 pairs | PASS |
| BF16 primitive + reducer + apply directed test | PASS |
| BF16 add/mul/reducer/apply Yosys check/synthesis | PASS |
| Non-pipelined vector reducer synthesis 1/2/4/8/16 | PASS |
| Pipelined vector reducer synthesis 2/4/8/16 | PASS |
| Shared pair reducer synthesis banks 1/2/4/8/16 | PASS |

The shared-pair gate was rerun independently after the outer combined command
hit its wall-clock limit; the gate itself completed successfully. Yosys warns
that accumulator arrays are lowered to registers in the generic flow. This is
not a standard-cell timing or SRAM-inference result.

## Reproduction

```bash
bash verification/groot_normalization/run_foundation_regression.sh
```

Individual BF16 gates:

```bash
bash verification/groot_normalization/run_bf16_arithmetic_random_test.sh
bash verification/groot_normalization/run_bf16_normalization_test.sh
bash verification/groot_normalization/run_bf16_normalization_synthesis.sh
```

## Remaining workload-independent work

- BF16 vector SUM/SUMSQ, scalar finalize, RSQRT, and hierarchical integration
  were subsequently completed; see report 16.
- Expand FP16/BF16 stage-by-stage normalization vectors to zero variance,
  epsilon-near, large offset, overflow/underflow, NaN, and infinity policies.
- Add reset/backpressure tests to reducer, scalar engine, reduction engine, and
  hierarchical top, not only bank apply.
- Run technology mapping and OpenSTA/OpenROAD timing for comparable FP16/BF16
  1/2/4/8/16-lane candidates. The current WSL shell does not expose standalone
  `opensta`; the repository ORFS setup is a separate reduced-top flow.
- Generate VCD/SAIF activity and a traceable energy report. Energy remains null
  until a characterized library and activity methodology are available.

## Deferred until final GR00T workload evidence

No final lane count, PCU count, FIFO/buffer depth, bank/logic placement, or
offload winner is selected here. Those decisions require the final workload
shape, arrival, and measured platform evidence.
