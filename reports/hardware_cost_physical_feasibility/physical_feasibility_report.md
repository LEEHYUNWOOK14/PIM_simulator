# Hardware-cost Physical Feasibility Gate

Overall status: **FAIL**  
RTL freeze allowed: **false**  
Production signoff: **NOT_TARGETED**

| Gate | Status | Criterion |
|---|---|---|
| PF-0 | PASS | RTL behavior, protocol, backpressure, and generic structural checks pass. |
| PF-1 | PASS | Standalone adapter maps to Sky130 and exposes a constrained STA path with no unconstrained paths. |
| PF-2 | PASS | Integrated PCU plus adapter maps and has an integrated constrained-path audit. |
| PF-3 | PASS | Coarse detailed placement from the current mapped netlist converges to zero legalization violations. |
| PF-4 | FAIL | Global routing completes with a guide, congestion report, and zero overflow. |

## Quantitative evidence

| Metric | Adapter | Integrated PCU + adapter |
|---|---:|---:|
| Mapped cells | 58201 | 3322275 |
| Mapped area (um^2) | 621866.4192 | 26863932.140799 |
| Sequential area (um^2) | 366326.336 | 7946371.2 |
| Critical path (ns) | 874.66 | 896.68 |
| Captured STA period (ns) | 1000.0 | 1000.0 |
| Captured STA worst slack (ns) | 123.34 | 103.19 |
| Project reference period (ns) | 40.0 | 40.0 |
| Meets project reference | False | False |
| Unconstrained paths | 0 | 0 |

- Legal placement: True; final violations: 0; core area: 81163882.6 um^2; utilization: 37.5%.
- Global routing revision: v4; completed measurement: True; clean exit: None; OpenROAD exit code: unavailable; signal layers: met1-met5; iterations: 1.
- Global routing overflow: 5998; max layer usage: unavailable%; routed nets: unavailable; maximum observed fanout: 315739.
- CUGR congestion remaining: 2620; detailed violations captured: 5998; maximum local overuse: 5.
- Prior-route comparison: {'revision': 'v2', 'congestion_remaining': 1600437, 'congestion_violation_count': 20000, 'residual_reduction_pct': 99.83629471200679}.
- Captured congestion hotspot categories: {'adapter_buffer': 316, 'bank_interface': 4080, 'clock': 1427, 'pcu_apply': 3340, 'pcu_reduction': 587, 'wide_mux_select': 1331}; top bank source mentions: [{'bank': 7, 'source_net_mentions': 5237}, {'bank': 3, 'source_net_mentions': 4362}, {'bank': 13, 'source_net_mentions': 4234}, {'bank': 9, 'source_net_mentions': 4158}, {'bank': 15, 'source_net_mentions': 4118}, {'bank': 6, 'source_net_mentions': 3497}, {'bank': 0, 'source_net_mentions': 3395}, {'bank': 8, 'source_net_mentions': 2983}]; top 500 um tiles: [{'x_min_um': 8500, 'y_min_um': 2000, 'violation_blocks': 1634}, {'x_min_um': 8500, 'y_min_um': 1500, 'violation_blocks': 513}, {'x_min_um': 8000, 'y_min_um': 2000, 'violation_blocks': 433}, {'x_min_um': 4000, 'y_min_um': 3500, 'violation_blocks': 290}, {'x_min_um': 3500, 'y_min_um': 3500, 'violation_blocks': 250}, {'x_min_um': 4500, 'y_min_um': 4500, 'violation_blocks': 147}, {'x_min_um': 4000, 'y_min_um': 4500, 'violation_blocks': 139}, {'x_min_um': 8000, 'y_min_um': 1500, 'violation_blocks': 114}].
- Logic-die proxy budget: 91800000.0 um^2; mapped utilization: 29.264%; placed-footprint utilization: 88.414%.
- Buffer implementation: 12288 logical bits lowered to 12288 standard-cell registers; storage-cell-only area 307494.912 um^2 (49.447% of adapter mapped area).
- Coarse fanout/wire repair: 78087 inserted buffers across 13897 nets; area increase 3.1%; remaining slew/fanout/capacitance violations 13992/3235/657.
- Generic connectivity baseline: 145,852 wire bits. This is a structural pressure indicator, not a direct congestion measurement.

## Freeze blockers

- Global routing completed but severe congestion remains (2620 reported residual; 5998 detailed violations captured).
- The latest route measurement produced a complete guide/congestion report but did not emit a clean OpenROAD exit code.

## Non-gating risks

- Standalone adapter misses the 40 ns project reference: critical path 874.66 ns. Timing closure is outside this gate.
- Integrated PCU+adapter misses the 40 ns project reference: critical path 896.68 ns. Timing closure is outside this gate.
- Coarse repair leaves 13992 slew, 3235 fanout, and 657 capacitance violations; closure is outside this gate.
- The documented 145,852 generic wire bits indicate wide-datapath connectivity pressure, but are not a direct routing-congestion measurement.

## Claim boundary

Lightweight Sky130 technology-mapping and legal coarse placement only. Global-routing feasibility remains unestablished until PF-4 passes; this is not CTS, detailed route, extraction, IR/EM, DRC/LVS, power, thermal, or silicon signoff.
