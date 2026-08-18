# B2 residual congestion analysis

Generated: `2026-08-17T05:08:39Z`

This is a read-only analysis of the existing B2 route artifacts. No placement, global route, detailed route, CTS, or Phase 6 execution was started.

## Decision

- Phase 5: **ACCEPTED_WITH_RESIDUAL_CONGESTION**
- Phase 6: **BLOCKED_RESIDUAL_CONGESTION**
- Phase 6 `authorizes=[]`; `next_stage=null`.

B2 satisfies the Phase 5 contract because both residual congestion and overflow edges improve against frozen A. The strict Phase 6 zero-residual and zero-overflow requirements fail.

## Direct parser checks

- Parsed records: 181 (horizontal 141, vertical 40)
- Layers: met1 133, met2 40, met3 8
- Recomputed overflow edges/tracks: 39/40
- Prior summary said 37/38; it missed the two `capacity:9 usage:10` records because of string comparison.
- At capacity: 142; below capacity: 0; maximum congestion: 2
- CuGR iterative-RRR residual: 46
- Existing AWK summaries were not used; `overflow=max(usage-capacity,0)` was recomputed per record.

## Non-exclusive source attribution

| Category | All 181 | Overflow 39 | Overflow source occurrences |
| --- | --- | --- | --- |
| adapter/payload-store | 71 | 12 | 105 |
| scalar engine/scalar return | 89 | 15 | 187 |
| bank apply | 30 | 4 | 66 |
| bank reduction | 28 | 7 | 30 |
| replay | 20 | 5 | 9 |
| writeback | 14 | 2 | 10 |
| quad completion/context tag | 77 | 22 | 127 |
| clock/reset | 41 | 11 | 12 |
| top-level I/O/other | 107 | 28 | 355 |

Counts are non-exclusive; one window may contribute to multiple categories.

## Layer, source-quad, and spatial distribution

| Layer | All windows | Overflow windows |
| --- | --- | --- |
| met1 | 133 | 31 |
| met2 | 40 | 5 |
| met3 | 8 | 3 |

| Source quad | All windows | Overflow windows |
| --- | --- | --- |
| Q0 | 14 | 2 |
| Q1 | 25 | 4 |
| Q2 | 77 | 20 |
| Q3 | 56 | 14 |
| unassigned | 51 | 9 |

Source-quad counts are non-exclusive and are inferred from `g_quad[n]` hierarchy or packed-signal bit ranges.

| Exact spatial region | All windows | Overflow windows |
| --- | --- | --- |
| Q0_fence | 9 | 2 |
| Q1_fence | 21 | 2 |
| Q2_fence | 8 | 1 |
| Q3_fence | 11 | 3 |
| central_corridor | 132 | 31 |

Fence classification uses the exact B2 ODB coordinates recorded by placement: Q0 `(20.120,20.880)-(4265.444,4266.204)`, Q1 `(4772.176,20.880)-(9017.500,4266.204)`, Q2 `(20.120,4772.356)-(4265.444,9017.680)`, and Q3 `(4772.176,4772.356)-(9017.500,9017.680)`. The central corridor is the union of the exact horizontal and vertical gaps.

## Leading overflow hotspots

| Index | Overflow | Layer | Region | bbox um | First source nets |
| --- | --- | --- | --- | --- | --- |
| 128 | 2 | met1 | Q1_fence | 7445.1,1414.5,7452.0,1421.4 | u_b2_implementation/reduction_data[565], u_b2_implementation/reduction_data[840], u_b2_implementation/u_pcu/u_quad_datapath/g_quad[1].u_bank_slice/g_bank[3].u_reduce/g_lane[1].um/_1768_ |
| 79 | 1 | met1 | central_corridor | 4919.7,4595.4,4926.6,4602.3 | u_b2_implementation/u_pcu/_0704_, u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0716_ |
| 54 | 1 | met1 | central_corridor | 4871.4,4271.1,4878.3,4278.0 | u_b2_implementation/adapter_error, u_b2_implementation/writeback_tag[109], u_b2_implementation/writeback_tag[111] |
| 93 | 1 | met1 | central_corridor | 4940.4,4692.0,4947.3,4698.9 | u_b2_implementation/u_pcu/_0721_, u_b2_implementation/u_pcu/_0743_, u_b2_implementation/u_pcu/_0746_ |
| 114 | 1 | met1 | central_corridor | 4988.7,4692.0,4995.6,4698.9 | u_b2_implementation/u_pcu/_1276_, u_b2_implementation/u_pcu/_1277_, u_b2_implementation/u_pcu/_1278_ |
| 97 | 1 | met1 | central_corridor | 4947.3,4664.4,4954.2,4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0728_, u_b2_implementation/u_pcu/_0732_ |
| 131 | 1 | met1 | Q1_fence | 7914.3,3505.2,7921.2,3512.1 | u_b2_implementation/u_pcu/u_quad_datapath/g_quad[1].u_bank_slice/g_bank[3].u_apply/g_lane[3].us/_00973_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[1].u_bank_slice/g_bank[3].u_apply/g_lane[3].us/_01162_, u_b2_implementation/u_pcu/u_quad_datapath/g_quad[1].u_bank_slice/g_bank[3].u_apply/g_lane[3].us/_01183_ |
| 16 | 1 | met1 | central_corridor | 4367.7,4271.1,4374.6,4278.0 | clk_i, u_b2_implementation/u_pcu/u_quad_datapath/scalar_inv[1], u_b2_implementation/u_pcu/u_quad_datapath/scalar_inv[3] |
| 72 | 1 | met1 | central_corridor | 4905.9,4650.6,4912.8,4657.5 | u_b2_implementation/u_pcu/_0707_, u_b2_implementation/u_pcu/_0709_, u_b2_implementation/u_pcu/_0725_ |
| 105 | 1 | met1 | central_corridor | 4961.1,4692.0,4968.0,4698.9 | u_b2_implementation/u_pcu/_0814_, u_b2_implementation/u_pcu/_0821_, u_b2_implementation/u_pcu/_0824_ |
| 118 | 1 | met1 | Q3_fence | 6210.0,7286.4,6216.9,7293.3 | u_b2_implementation/replay_x[1851], u_b2_implementation/replay_x[1852], u_b2_implementation/replay_x[1853] |
| 78 | 1 | met1 | central_corridor | 4912.8,4664.4,4919.7,4671.3 | u_b2_implementation/u_pcu/_0712_, u_b2_implementation/u_pcu/_0728_, u_b2_implementation/u_pcu/_0731_ |

## `pcu_writeback_tag` comparator-cone recurrence check

Conclusion: **NOT_RECURRED**.

The B2 report contains `pcu_writeback_tag` in 2 windows (1 overflow window) and 4 source occurrences. This residual presence is on the writeback/adapter path; it does not recreate the removed 16-bank central comparator sink cone.
The mapped assertion reports internal sink pins = 0 with result `PASS`. Routed measurements report fanout total 791, fanout max 8, median HPWL 523.7235000000001 um, and congested guide rectangles 0.

## Baseline comparison and Phase 5 contract

| Metric | Frozen A | B | B2 |
| --- | --- | --- | --- |
| rrr_residual | 1768 | 3323 | 46 |
| congestion_windows | 4463 | 4357 | 181 |
| overflow_edges | 1293 | 2413 | 39 |
| overflow_tracks | 1395 | 3146 | 40 |
| maximum_congestion | 4 | 5 | 2 |

Residual improves 97.4% vs A and 98.62% vs B. Overflow edges improve 96.98% vs A and 98.38% vs B.

## Strict Phase 6 gate

| Condition | Required | Actual | Result |
| --- | --- | --- | --- |
| residual_congestion_zero | 0 | 46 | FAIL |
| overflow_edges_zero | 0 | 39 | FAIL |
| input_artifact_hashes_match | True | True | PASS |
| explicit_phase6_pass | True | False | FAIL |

Phase 6 remains fail-closed because residual congestion is 46 rather than 0, overflow edges are 39 rather than 0, and there is no explicit Phase 6 PASS. Artifact hashes do match, but that condition alone cannot authorize release.

## Cheap next work without additional P&R

1. Review the 39 parsed overflow records by dominant category and exact bbox, starting with the single overflow-2 edge and the highest repeated source nets.
2. Use the existing routed measurements to compare fanout/HPWL/guide length for the leading adapter, scalar-return, bank-apply, and completion families; do not regenerate placement or routing.
3. Add a unit test for this direct parser and B2 hierarchy-aware classification so `g_quad[n].u_payload_store` cannot regress to `adapter_entries=0`.
4. Seal the four B2 route-artifact hashes together with this analysis and the Phase 5/6 decisions.

## Preservation

| Artifact | Hash matches | SHA-256 |
| --- | --- | --- |
| frozen_A_routed_odb | True | 964adc9cf68aceac1fd6686d7c586ffbd295ed9a35f6b54628ddf81981cbc5ad |
| quad_local_B_routed_odb | True | ab6cddf83dee124e9ae388b5cbe8c6fbda6665782870e1c4a57f83a83a174235 |
| quad_local_B2_routed_odb | True | 2c928b19ab5b1dcbcd89ec36d8d0b18963a8b03c9776ecc7325509332e98235d |

All three routed ODB hashes match their previously sealed values. Frozen A, B, B2 route artifacts and evidence inputs were not modified; only the requested analysis/decision outputs were written.
