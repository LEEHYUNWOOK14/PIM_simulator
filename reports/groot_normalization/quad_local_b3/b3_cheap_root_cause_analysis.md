# B2 cheap root-cause analysis and B3 ECO selection

Generated: `2026-08-17T07:20:01.768184+00:00`

All evidence comes from existing B2 reports, mapped netlist, route log, and routed-family measurements. No placement or routing was run.

## Verdict

- B2 residual: 46
- Actual numeric overflow: 39 edges / 40 tracks
- Central corridor: 31 / 39 overflow windows
- met1: 31 / 39 overflow windows
- 38 edges have overflow 1 and one Q1 bank-reduction edge has overflow 2.
- The B2 global route used one configured congestion iteration and stopped at residual 46.
- Therefore a bounded route-effort ECO is selected before another functional RTL change.

## Repeated overflow source ranking

| source | windows | overflow contribution | mapped/routed evidence | fanout | HPWL um | guide um |
|---|---:|---:|---|---:|---:|---:|
| `clk_i` | 11 | 11 | named RTL/mapped net | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[36]` | 7 | 7 | routed `quad_completion` family | 14 | 974.418 | 2960.100 |
| `u_b2_implementation/u_pcu/_0732_` | 7 | 7 | mapped inverter of `quad_completion_tag[35]` | - | - | - |
| `u_b2_implementation/u_pcu/_0712_` | 6 | 6 | mapped inverter of `quad_completion_tag[54]` | - | - | - |
| `u_b2_implementation/u_pcu/net427143` | 6 | 6 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/net427122` | 6 | 6 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[40]` | 5 | 5 | routed `quad_completion` family | 11 | 917.038 | 2007.900 |
| `u_b2_implementation/u_pcu/quad_completion_tag[34]` | 5 | 5 | routed `quad_completion` family | 9 | 885.366 | 1518.000 |
| `u_b2_implementation/u_pcu/net427141` | 5 | 5 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/net427153` | 5 | 5 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/net427120` | 5 | 5 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/net427132` | 5 | 5 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/_1339_` | 5 | 5 | mapped synthetic PCU/leaf logic; category from co-resident named nets | - | - | - |
| `u_b2_implementation/u_pcu/_0731_` | 4 | 4 | mapped inverter of `quad_completion_tag[36]` | - | - | - |
| `u_b2_implementation/u_pcu/_1506_` | 4 | 4 | mapped synthetic PCU/leaf logic; category from co-resident named nets | - | - | - |
| `u_b2_implementation/u_pcu/_1536_` | 4 | 4 | mapped synthetic PCU/leaf logic; category from co-resident named nets | - | - | - |
| `u_b2_implementation/u_pcu/ctx_valid_q[2]` | 4 | 4 | named RTL/mapped net | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[35]` | 4 | 4 | routed `quad_completion` family | 9 | 957.586 | 1794.000 |
| `u_b2_implementation/u_pcu/net427147` | 4 | 4 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/_0741_` | 4 | 4 | mapped inverter of `quad_completion_tag[26]` | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[54]` | 4 | 4 | routed `quad_completion` family | 11 | 247.238 | 986.700 |
| `u_b2_implementation/u_pcu/_0740_` | 4 | 4 | mapped inverter of `quad_completion_tag[27]` | - | - | - |
| `u_b2_implementation/u_pcu/ctx_tag_q[2][6]` | 3 | 3 | named RTL/mapped net | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[46]` | 3 | 3 | routed `quad_completion` family | 14 | 901.415 | 2380.500 |
| `u_b2_implementation/u_pcu/_0742_` | 3 | 3 | mapped inverter of `quad_completion_tag[24]` | - | - | - |
| `u_b2_implementation/u_pcu/net427121` | 3 | 3 | post-map repair fragment; owning hierarchy/category retained | - | - | - |
| `u_b2_implementation/u_pcu/_0709_` | 3 | 3 | mapped inverter of `quad_completion_tag[56]` | - | - | - |
| `u_b2_implementation/u_pcu/_0744_` | 3 | 3 | mapped inverter of `quad_completion_tag[22]` | - | - | - |
| `u_b2_implementation/u_pcu/_0745_` | 3 | 3 | mapped inverter of `quad_completion_tag[20]` | - | - | - |
| `u_b2_implementation/u_pcu/_0746_` | 3 | 3 | mapped inverter of `quad_completion_tag[19]` | - | - | - |
| `u_b2_implementation/u_pcu/quad_completion_tag[42]` | 3 | 3 | routed `quad_completion` family | 10 | 909.683 | 2001.000 |
| `u_b2_implementation/u_pcu/net427128` | 3 | 3 | post-map repair fragment; owning hierarchy/category retained | - | - | - |

## `clk_i`

- Appears in 11 overflow windows.
- The route log explicitly skipped it with 319254 terminals.
- Decision: `CO_RESIDENT_SKIPPED_NET`, not the routed cause of the 39 overflow edges.

## Existing routed-family evidence

| family | nets | fanout total/max | HPWL median/max um | guide length um | congested guide rectangles |
|---|---:|---:|---:|---:|---:|
| `context_tag` | 640 | 1897/11 | 13.166/143.824 | 62445.000 | 0 |
| `pcu_writeback_tag` | 256 | 791/8 | 523.724/1259.261 | 164599.500 | 0 |
| `quad_completion` | 68 | 455/15 | 603.933/998.493 | 84476.700 | 0 |
| `writeback_tag` | 256 | 642/3 | 169.272/1086.877 | 98394.000 | 0 |

## Selected B3 ECO

**SELECT_B3_ROUTE_EFFORT_ECO**

B3 preserves the B2 RTL/netlist behavior and four-fence geometry, creates a new variant/output directory, reruns all nine cheap gates, produces one new incremental placement checkpoint from the read-only B2 placed ODB, and invokes CUGR exactly once with ten congestion iterations. This changes routing effort, not arithmetic, protocol, tag-completion behavior, or the frozen B2 artifacts.

If B3 remains nonzero, it is sealed without rerouting and a separately justified B4 placement/RTL ECO is required.

## Current authorization

`authorizes=[]`; `next_stage=B3_IMPLEMENTATION_AND_CHEAP_GATES`. Placement is not authorized until the fresh B3 cheap manifest passes 9/9.
