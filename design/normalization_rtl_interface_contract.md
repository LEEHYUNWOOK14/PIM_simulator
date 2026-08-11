# Normalization RTL interface and numeric contract

## Scope

This contract covers the workload-independent normalization blocks under `rtl/`.
It does not select the final GR00T lane count, PCU count, queue depth, placement,
or offload policy.

## Ready/valid contract

- A transfer occurs only on a rising edge where both `valid` and `ready` are 1.
- A producer may assert `valid` before `ready` and must hold valid and payload
  stable until transfer. This is legal backpressure, not a protocol error.
- A response producer holds `result_valid`, tag, payload, and last until the
  consumer accepts the response.
- `begin` or `config` establishes one active tag context. Data without an active
  context, a mismatched tag, a zero element/vector count, a duplicate bank
  partial, or an unexpected bank mask is a protocol/context error.
- Reset is active-low and asynchronous in the current blocks. Reset clears
  active/valid/error control state. Payload state is not evidence of validity
  unless its valid bit is set.
- Error outputs are one-cycle event pulses unless a module explicitly documents
  sticky behaviour.

## Numeric formats

`DATA_FORMAT=0` means IEEE binary16 (FP16). `DATA_FORMAT=1` means BF16. The
selection is compile-time in the bank local reducer and bank apply block, so a
16-bit BF16 payload cannot silently enter FP16 arithmetic in those blocks.

Both arithmetic paths use round-to-nearest, ties-to-even and preserve signed
zero, subnormal, infinity, and canonical quiet-NaN behaviour. The BF16 primitive
reference test compares 20,256 deterministic edge/random operand pairs against
an independent Python float32/BF16 rounding model.

Current bit-exact stages:

- FP16/BF16 primitive add and multiply against their format reference.
- Bank SUM/SUMSQ accumulation against the same sequential rounding order.
- Bank affine normalization apply against the same non-fused operation order.

Approximate stages:

- FP16 LUT256 reciprocal square root uses the error limits in
  `reports/groot_normalization/04_phase4_rsqrt_accuracy_report.md`.
- End-to-end normalization comparisons must use a tolerance because reduction,
  variance, reciprocal square root, and affine steps round independently.

## Explicit limits

- BF16 currently covers arithmetic primitives, bank local reduction, and bank
  apply. The logic scalar engine, RSQRT RTL, vector reducers, and hierarchical
  top remain FP16-only. BF16 full-top support is therefore not claimed.
- FP16 and BF16 operations are not fused FMA operations.
- NaN payload propagation is not preserved; invalid/NaN operations return the
  canonical quiet NaN (`0x7e00` FP16, `0x7fc0` BF16).
- The DRAM array is behavioural. No HBM2 PHY, vendor macro, CDC/DFT, full-chip
  STA, or tape-out signoff claim follows from this contract.
