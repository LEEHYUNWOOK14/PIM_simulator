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
selection is compile-time in bank scalar/vector reducers, bank apply, logic
scalar/reduction engines, and the hierarchical datapath. The full system exposes
the equivalent `NORMALIZATION_DATA_FORMAT` parameter. A context cannot switch
format at run time, so a 16-bit BF16 payload cannot silently select FP16
arithmetic inside a configured build.

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

Accuracy gates are format-specific: scalar LUT256 maximum relative error must
remain at or below 1% for both FP16 and BF16, while normalization output maximum
absolute error must remain at or below 0.025 against the canonical FP32 model.
Observed baseline maxima and candidate-specific limits are recorded in
`reports/groot_normalization/04_phase4_rsqrt_accuracy_report.md`; bit-exact RTL
stages are not evaluated with these looser tolerances.

## Explicit limits

- BF16 covers arithmetic primitives, local/vector reduction, scalar finalize,
  LUT256 RSQRT, affine apply, reduction engine, hierarchical datapath, and the
  normalization path selected in `full_pim_system_top`. The full system uses a
  compile-time format rather than mixed FP16/BF16 contexts.
- FP16 and BF16 operations are not fused FMA operations.
- NaN payload propagation is not preserved; invalid/NaN operations return the
  canonical quiet NaN (`0x7e00` FP16, `0x7fc0` BF16).
- The DRAM array is behavioural. No HBM2 PHY, vendor macro, CDC/DFT, full-chip
  STA, or tape-out signoff claim follows from this contract.
