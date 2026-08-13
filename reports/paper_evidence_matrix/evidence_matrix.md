# Paper Claim Boundary and Evidence Matrix

Physical status: **FAIL**  
Routing claim allowed: **false**

The classification describes the evidence actually supporting each result. It is not a maturity ladder: modeled and estimated results remain distinct from RTL and implementation evidence.

| ID | Result | Class | Gate | Claim status |
|---|---|---|---|---|
| R-RTL-01 | HBM boundary-adapter behavior, protocol, and backpressure checks | `rtl_simulated` | PF-0 PASS | **SUPPORTED** |
| R-SYN-01 | Standalone adapter Sky130 mapping and constrained-path audit | `synthesized` | PF-1 PASS | **SUPPORTED** |
| R-SYN-02 | Integrated PCU plus adapter Sky130 mapping | `synthesized` | PF-2 PASS | **SUPPORTED** |
| R-PLC-01 | Integrated mapped-netlist legal coarse placement | `placed` | PF-3 PASS | **SUPPORTED** |
| R-RTE-01 | Global-routing feasibility | `placed` | PF-4 FAIL | **BLOCKED** |
| R-MOD-01 | Architectural latency, throughput, power, and thermal projections | `modeled` | n/a | **SUPPORTED** |
| R-EST-01 | Manufacturing, yield, geometry, and cost assumptions | `estimated` | n/a | **SUPPORTED** |
| R-ILL-01 | HBM2 package and floorplan visualizations | `illustrative` | n/a | **SUPPORTED** |

## Allowed wording and boundary

### R-RTL-01 — `rtl_simulated` / SUPPORTED

Allowed: The boundary adapter passed the reported RTL-level functional checks.

Boundary: This does not establish synthesis, timing closure, placement, or routing.

Evidence: `reports/groot_normalization/hbm_boundary_adapter/05_completion_audit.md`

### R-SYN-01 — `synthesized` / SUPPORTED

Allowed: The standalone adapter was synthesized and technology-mapped with the reported proxy area and constrained STA result.

Boundary: The 40 ns project timing target is not met; no timing-closure claim is allowed.

Evidence: `reports/groot_normalization/physical_feasibility/normalization_hbm_boundary_adapter_sky130_yosys.log`, `reports/groot_normalization/physical_feasibility/normalization_hbm_boundary_adapter_sky130_sta.log`

### R-SYN-02 — `synthesized` / SUPPORTED

Allowed: The integrated PCU plus adapter was synthesized and technology-mapped in the public Sky130 proxy flow.

Boundary: This is proxy technology mapping, not production-process PPA or timing closure.

Evidence: `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_sky130_yosys.log`, `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_sky130_sta.log`

### R-PLC-01 — `placed` / SUPPORTED

Allowed: The current mapped netlist reached legal coarse placement with zero final legalization violations.

Boundary: Legal placement does not establish routability, detailed-route completion, or signoff.

Evidence: `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v2_repair_legalize.log`

### R-RTE-01 — `placed` / BLOCKED

Allowed: The v4 full-net CUGR measurement produced a complete guide and congestion report, but residual severe congestion remains, the process did not emit a clean exit marker, and PF-4 failed.

Boundary: Routing feasibility remains unestablished; routability and congestion closure cannot be claimed, and RTL freeze remains blocked.

Evidence: `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v4_route.log`, `reports/groot_normalization/physical_feasibility/logic_die_normalization_hbm_top_v4.congestion.rpt`

### R-MOD-01 — `modeled` / SUPPORTED

Allowed: These values are outputs of the stated architectural models under their documented inputs.

Boundary: They are not RTL measurements, post-route results, or silicon measurements.

Evidence: `output/hbm2_hardware_cost/integrated_metrics.json`

### R-EST-01 — `estimated` / SUPPORTED

Allowed: These values are engineering estimates used for sensitivity analysis.

Boundary: They are not vendor disclosures, quotes, or measured manufacturing data.

Evidence: `hardware_cost/config.json`

### R-ILL-01 — `illustrative` / SUPPORTED

Allowed: The figures illustrate the modeled architecture and relative organization.

Boundary: Shape placement and dimensions do not establish a manufacturable layout or routed connectivity.

Evidence: `design/hbm2_architecture.json`

## PF-4 guardrail

PF-4 failed after a completed full-net global-route run because severe congestion remained. The paper may report the completed attempt and its measured congestion, but must not assert routability, routing feasibility, or congestion closure. Re-run this generator after routing evidence changes; the guard is derived from the physical-feasibility JSON rather than manually selected.
