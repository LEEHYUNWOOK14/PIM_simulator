# Phase 5 B2 execution report

- Result: `PHASE5_PHYSICAL_PASS_WITH_RESIDUAL_CONGESTION`
- Variant: `logic_die_normalization_hbm_quad_local_b2_top`
- Cheap gate: all 9 `PASS`; authorization was limited to B2 placement/global-route.
- Phase 6: `BLOCKED`; no authorization emitted.

## B2 contract and cheap gates

The mapped audit passed all 20 checks. Four registered quad completion descriptors replace the central 16-bank tag consumer: the mapped PCU has zero internal sink pins on the 256-bit writeback-tag input, central completion is 64 tag bits plus 4 valid bits, and all 17 descriptor output bits are register-driven. Root reset fanout is four; the largest effective reset leaf has 13,671 sinks under the 20,000 limit.

All six actual workload profiles passed with zero C11 bit mismatches. Maximum absolute error was 0.015625 against the 0.025 threshold.

## Physical execution

The full ORFS placement flow was invoked once. Its first detailed placement ended with 18,167 overlaps. The expensive synthesis, floorplan, global placement, and resize stages were not rerun: the durable `3_4_place_resized.odb` checkpoint was respread and legalized. The final placement audit passed with four fences, 3,676,196 grouped instances, zero instances outside fences, zero unplaced instances, and zero legality violations.

Global-route was invoked exactly once after placement audit PASS. It completed in 25:51.58 with exit 0 and peak RSS 30,045,884 KiB. Iterative RRR retained 46 residual congestion units. The generated report contains 141 horizontal and 40 vertical congestion windows; this is Phase 5 evidence, not a Phase 6 release.

## Routed B versus B2

| metric | routed B | routed B2 | change |
|---|---:|---:|---:|
| RRR residual congestion | 3,323 | 46 | -98.62% |
| congestion report windows | 4,357 | 181 | -95.85% |
| `pcu_writeback_tag` sink fanout | 2,382 | 791 | -66.79% |
| `pcu_writeback_tag` max fanout | 21 | 8 | -61.90% |
| `pcu_writeback_tag` median HPWL | 1,040.333 um | 523.724 um | -49.66% |
| `pcu_writeback_tag` guide length | 493,322.4 um | 164,599.5 um | -66.64% |
| `pcu_writeback_tag` guide rectangles | 17,949 | 3,973 | -77.86% |

The new B2 `quad_completion` family is 68 nets (64 tag plus 4 valid), total sink fanout 455, max fanout 15, median/max HPWL 603.933/998.493 um, guide length 84,476.7 um, and zero congested guide rectangles.

## Frozen A and decision state

`rtl/logic_die_normalization_hbm_top.sv` remains clean in Git with SHA-256 `6d89452e0f13eef7fa215e636c39d666b9c72960159fb9087ded544171b17526`. Existing A/B evidence was read only.

Phase 6 remains blocked by `phase6_decision_gate.json`. The physical PASS and large congestion reduction do not authorize Phase 6; a separate review and an explicit Phase 6 decision gate PASS are still required.

## Artifact hashes

| artifact | SHA-256 |
|---|---|
| B2 route guide | `8e82c1596745db76905aea0d76f94bea1e10acde04cfdf7a1085e4044119e210` |
| B2 congestion report | `253455988e93e3e828e6887f24bdbd982c4f8965b5d8b619bbdd35166e5c9d56` |
| B2 routed ODB | `2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d` |
| B2 routed SDC | `54a5f6175459c327e0da0cdafc816c88f19b48ab9fffe727c377ea072c74b700` |
| B2 cheap-gate manifest | `490d63609b4a3177f5ef7e3ab9336d4a0972d3e28b927e4935da5d525c802e6a` |
| B2 routed tag/completion measurement | `a2323c83eb9e4b075cb37452ecfd44d2e5aa5454717e86788397bb40fd033f5f` |
