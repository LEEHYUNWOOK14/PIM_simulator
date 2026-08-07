# Power / Performance 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- 1024 bit × 2.4 Gbps를 307.2 GB/s 공개 상한과 교차검증한다.
- 방법론은 roofline_berkeley, 제품 사양은 samsung_aquabolt_hbm2에 근거한다.
- utilization, PIM speedup, power multiplier는 project_cost_assumption이다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|capacity_GB=4, required_capacity_GB=8, capacity_feasible=0, theoretical_bandwidth_GBs=307.2, achieved_bandwidth_GBs=215.04, bandwidth_utilization=0.7, normalized_useful_performance=387.072, estimated_power_W=3.45, energy_per_GB_work_J=0.00891307, io_energy_per_transferred_bit_pJ=2.00544, pim_speedup_assumption=1.8, predicted_peak_temperature_K=306.506, thermal_limit_K=358.15, thermal_feasible=1, power_evidence=architectural/synthetic unless replaced by activity or measurement|
|hbm2_8hi_1stack|capacity_GB=8, required_capacity_GB=8, capacity_feasible=1, theoretical_bandwidth_GBs=307.2, achieved_bandwidth_GBs=215.04, bandwidth_utilization=0.7, normalized_useful_performance=387.072, estimated_power_W=4.6, energy_per_GB_work_J=0.0118841, io_energy_per_transferred_bit_pJ=2.67392, pim_speedup_assumption=1.8, predicted_peak_temperature_K=310.514, thermal_limit_K=358.15, thermal_feasible=1, power_evidence=architectural/synthetic unless replaced by activity or measurement|
|hbm2_12hi_1stack|capacity_GB=12, required_capacity_GB=8, capacity_feasible=1, theoretical_bandwidth_GBs=307.2, achieved_bandwidth_GBs=215.04, bandwidth_utilization=0.7, normalized_useful_performance=387.072, estimated_power_W=5.75, energy_per_GB_work_J=0.0148551, io_energy_per_transferred_bit_pJ=3.3424, pim_speedup_assumption=1.8, predicted_peak_temperature_K=315.442, thermal_limit_K=358.15, thermal_feasible=1, power_evidence=architectural/synthetic unless replaced by activity or measurement|
|hbm2_8hi_2stack|capacity_GB=16, required_capacity_GB=8, capacity_feasible=1, theoretical_bandwidth_GBs=614.4, achieved_bandwidth_GBs=430.08, bandwidth_utilization=0.7, normalized_useful_performance=774.144, estimated_power_W=9.2, energy_per_GB_work_J=0.0118841, io_energy_per_transferred_bit_pJ=2.67392, pim_speedup_assumption=1.8, predicted_peak_temperature_K=321.028, thermal_limit_K=358.15, thermal_feasible=1, power_evidence=architectural/synthetic unless replaced by activity or measurement|
|hbm2_8hi_no_pim|capacity_GB=8, required_capacity_GB=8, capacity_feasible=1, theoretical_bandwidth_GBs=307.2, achieved_bandwidth_GBs=215.04, bandwidth_utilization=0.7, normalized_useful_performance=215.04, estimated_power_W=4, energy_per_GB_work_J=0.0186012, io_energy_per_transferred_bit_pJ=2.32515, pim_speedup_assumption=1, predicted_peak_temperature_K=309.143, thermal_limit_K=358.15, thermal_feasible=1, power_evidence=architectural/synthetic unless replaced by activity or measurement|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
