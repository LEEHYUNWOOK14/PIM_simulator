# WBQ 3_4 Steiner alpha experiment and post-GDS decision record

## Status and claim boundary

The current `routing_alpha=0.0` run is an experiment, not the final WBQ
physical-design policy.  It has two purposes:

1. Prove whether the `alpha=0.3` Prim-Dijkstra path causes the long
   `repair_design` stalls.
2. Produce a complete reference result that can be compared with a later
   policy-preserving implementation.

Do not accept the global-alpha result as the final implementation solely
because it completes.  If post-placement, route, or final-GDS quality is worse,
the policy must be corrected and the flow must restart at 3_4.  Changing alpha
changes Steiner topology, buffer locations/counts, cell sizing, and placement;
editing only a downstream result is not valid.

The active experiment was launched as the user systemd service
`wbq-phase3-repair-guarded-v3.service` at 2026-08-14T08:28:25Z.  Phase 4 is
blocked by `reports/final_integrated_gds_execution/CLI_OWNS_PHASE4` and must
remain blocked until the 3_4 result is classified.

## Evidence

The placed 3_3 ODB contains 4,063,775 repair driver vertices.  Direct
Prim-Dijkstra reproduction isolated the pathological nets:

- `clk_i`: 318,060 placed points; `alpha=0.3` exceeded the 180-second limit.
- `rst_ni`: 318,060 placed points; `alpha=0.3` exceeded the 180-second limit.
- Internal control nets with roughly 2,000-6,100 terminals completed in
  17-18 seconds including ODB load.
- `clk_i` with `alpha=0.0` completed Steiner construction in 4.133 seconds.
- `rst_ni` with `alpha=0.0` completed Steiner construction in 4.027 seconds.
- Placement parasitic estimation fell from 925 seconds to 189-190 seconds when
  the pathological Prim-Dijkstra route was avoided.

Compact measurements are stored in `diagnostic_summary.tsv`.  Raw logs remain
under `../wbq_pd_net_diagnostics/` and `../wbq_stt_guard_validation/`; they are
intentionally not committed because the two alpha-zero tree dumps are about
33 MB each.

## Root cause

OpenROAD stores a per-net alpha policy against the original `dbNet`.  The
initial net tree can therefore use `alpha=0` for clock/reset while ordinary
nets retain `alpha=0.3`.  During repair, however,
`makeBufferedNetSteinerOverBnets(root, sinks)` constructs anonymous buffered
subtrees without the original `dbNet`.  Those calls fall back to the global
alpha.  A net-specific Tcl guard improved the first tree but did not cover the
anonymous subtrees; multi-minute stalls reappeared around repair iteration
2,739,000.

The global-alpha experiment avoids both the original-net and anonymous-subtree
Prim-Dijkstra paths.  It is a diagnostic baseline, not proof that alpha zero
has acceptable QoR for ordinary nets.

## Preferred long-term correction

Preserve the original repair transaction's routing policy explicitly:

```text
subtree_alpha = original_net_alpha

clk_i (0.0)
  +-- buffered subtree A (0.0)
  +-- buffered subtree B (0.0)

ordinary net (0.3)
  +-- buffered subtree (0.3)
```

Capture the effective alpha while the original `dbNet` is available, then pass
the value through every buffered-tree construction and recursive repair call.
Do not infer the policy from generated net names and do not query a newly
created buffer-output `dbNet`, because either approach can silently return the
global default.

A suitable interface direction is:

```cpp
makeBufferedNetSteinerOverBnets(root, sinks, routing_alpha);
```

or a small immutable repair context containing `routing_alpha`.  A global
mutable "current alpha" is unsafe for reentrancy and future parallelism.

## Post-GDS comparison gate

Compare the global-alpha reference with the inherited-alpha 3_4 rerun using
the same netlist, SDC, floorplan, tool revision, and metric definitions.

Required gates:

- 3_4 repair completes without timeout or buffer-limit termination.
- Slew, capacitance, and fanout violations do not regress.
- Detailed placement legalizes with zero remaining violations.
- Buffer count, resized-cell count, and area growth stay inside the declared
  research envelope.
- Runtime remains bounded and reproducible.

Comparison metrics:

- inserted buffers, resized cells, repaired nets, and area growth;
- placement HPWL and displacement;
- global-route congestion and unrouted/overflow metrics;
- pre-CTS WNS/TNS as provisional comparisons, not signoff claims;
- routed timing, DRC, and final-GDS geometry checks.

If inherited alpha is acceptable, it becomes the preferred policy.  Only if a
small set of nets still has inadequate runtime or QoR should candidate alpha
evaluation (`0.0`, `0.1`, `0.2`, `0.3`) be added for those nets.  Timing and
electrical constraints should reject candidates first; wirelength, congestion,
and runtime should rank the survivors.

## Reproduction files

- `verification/groot_normalization/diagnose_wbq_stt_net.tcl`: isolated
  selectable-alpha tree benchmark.
- `verification/groot_normalization/check_wbq_pre_resize_steiner_guard.tcl`:
  ODB smoke test for a resize hook.
- `verification/groot_normalization/wbq_pre_resize_steiner_guard_v3.tcl`:
  process-scoped global-alpha experimental hook.
- `verification/groot_normalization/run_normalization_hbm_wbq_repair_guarded_v3.sh`:
  preserves previous attempts and launches only stage 3_4.

## Decision rule

The global-alpha result may be used as the final result only after it passes
the above gates and shows no material QoR loss against the inherited-alpha
result.  Otherwise implement alpha inheritance and rerun from 3_4 before
continuing the accepted final-GDS lineage.
