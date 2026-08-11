# Missing manufacturer and signoff data

This checklist separates data that can be estimated during architecture exploration from data needed
before a placement can be promoted to a physical recommendation.

| Priority | Required data | Current substitute | Affected outputs | Acceptance evidence |
|---|---|---|---|---|
| P0 | Timing-closed stabilized RTL netlist and routed GDS | reduced block, -35.650 ns slack | hard gate, delay, area, congestion | setup/hold clean OpenSTA reports and DRC-clean route |
| P0 | HBM PHY/TSV/microbump pin map and keep-out rules | representative geometry A1 | feasible region, TSV distance/count/KOZ | vendor package design kit or approved floorplan |
| P0 | Block-level dynamic/leakage power under GR00T | 0.10/0.01 W assumptions | thermal, reliability, IR drop, operating cost | SAIF/VCD-annotated power report with corner and activity coverage |
| P0 | Package stackup and cooling boundary | compact vertical conductance A3/A5 | absolute peak/mean temperature and gradient | material/thickness table plus calibrated 3D thermal result |
| P1 | Actual GR00T command/address/timestamp trace | 333-call synthetic profile replay | channel balance, PCU utilization, bandwidth and queue | trace from production command generator with coverage statement |
| P1 | Per-layer extracted RC and routed nets | SKY130HD platform RC proxy | placement-dependent latency/power | SPEF/parasitic extraction from target process and route |
| P1 | Power-grid and PHY/CTS reserved regions | area fractions A1 | placement feasibility and congestion | DEF/blockage map and PG/CTS implementation reports |
| P1 | Temperature and voltage limits by corner | 95 C and 1.8 V assumptions | hard thermal/reliability/IR gates | technology/library/package limits with operating corner |
| P2 | Wafer price, mask/NRE and defect-density model | placeholder A6 | logic-die cost range | foundry quote or approved internal cost range |
| P2 | HBM known-good-die and stack assembly yield | 0.95/0.90 assumptions | package yield and cost | vendor yield range and test escape assumptions |
| P2 | HBM DRAM die, test and package costs | explicitly excluded | complete unit cost | supplier/package quote with volume and date |
| P2 | TIM/lid/interposer material distributions | broad low/base/high A5 | uncertainty interval | vendor datasheets and lot/temperature-dependent properties |

## Promotion rule

A provisional coordinate must not be written into the final KLayout package configuration until all P0
items are available, the robustness gate passes, and `signoff_hard_constraint_feasible_count` is nonzero.
P1 data is required for an engineering recommendation. P2 data is required for a defensible absolute
cost claim; without it, only sensitivity and partial cost ranges may be reported.
