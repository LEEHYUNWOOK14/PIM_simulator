# Workload-independent physical and robustness report

## Verdict

**PASS WITH TIMING VIOLATIONS RECORDED.** Reset recovery and normalization
special-value policies pass for FP16 and BF16. Sky130HD standard-cell mapping and
pre-layout STA complete for pipelined 2/4-lane candidates, but none meets the
10 ns target. This is evidence that the arithmetic stage needs further pipeline
partitioning; it is not a final lane-count decision.

## Reset and protocol robustness

The reset contract injects asynchronous reset in three phases:

1. after only one cross-bank partial has arrived;
2. while scalar finalize/RSQRT is in flight;
3. while a completed response is stalled by downstream backpressure.

Both FP16 and BF16 discard stale context, clear output/error valid state, reject
post-reset stale partials, and complete a fresh transaction. The existing bank
apply contract additionally verifies held-valid input during backpressure,
same-cycle consume/replace, and reset of a stalled output.

## Special-value policy

Seven directed scalar-path cases pass in both formats:

- zero statistic and zero epsilon produces positive infinity;
- minimum-subnormal epsilon produces a finite large reciprocal square root;
- positive infinity produces zero;
- NaN and negative RMS statistics produce canonical quiet NaN;
- a negative LayerNorm variance caused by rounded subtraction clamps to zero;
- statistic multiplication overflow produces infinity and therefore RSQRT zero.

These complement exhaustive RSQRT testing over all 65,536 bit patterns and the
20,256-pair BF16 add/multiply reference test.

## Sky130HD results

Corner: `sky130_fd_sc_hd__tt_025C_1v80`, ideal 10 ns clock, Yosys ABC mapping,
OpenROAD pre-layout STA. No placement, extracted interconnect, CTS, or signoff
derating is included.

| Format | Lanes | Mapped area (um^2) | Critical path (ns) | Worst slack (ns) | 100 MHz |
|---|---:|---:|---:|---:|---|
| FP16 | 2 | 30,335.3440 | 19.61 | -9.74 | FAIL |
| FP16 | 4 | 57,617.7600 | 20.28 | -10.41 | FAIL |
| BF16 | 2 | 25,552.0064 | 19.97 | -10.10 | FAIL |
| BF16 | 4 | 48,305.0784 | 21.48 | -11.61 | FAIL |

The current pipeline registers separate tree levels, but one FP add/multiply
implementation still forms a long combinational stage. Meeting 100 MHz requires
internal arithmetic pipelining or a different macro/library implementation.
Simply selecting fewer lanes does not close timing in the measured candidates.

Machine-readable evidence:
`results/normalization_sky130_metrics.csv` and
`results/sky130_mapping/*_{yosys,sta}.log`.

## Integration regression

After dtype and arithmetic changes, `rtl/run_full_pim_tests.sh` passes all nine
integrated gates, including bank-side PIM, logic control, 16-PCU simultaneous
issue, full system top, and 40-batch/320-result random backpressure stress.

## Reproduction

```bash
bash verification/groot_normalization/run_normalization_reset_contract_test.sh
bash verification/groot_normalization/run_normalization_special_values_test.sh
bash verification/groot_normalization/run_normalization_sky130_mapping.sh
bash rtl/run_full_pim_tests.sh
```

## Limits and deferred decisions

- Power/energy is not reported without VCD/SAIF activity and a documented toggle
  methodology.
- Pre-layout STA is not post-route signoff and does not include HBM2 PHY/vendor
  macros, extracted parasitics, CDC, DFT, or full-chip closure.
- No lane, PCU, FIFO, buffer, placement, or offload configuration is selected.
  Those remain dependent on final GR00T workload evidence.
