# Thermal 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- 3D finite-volume reference solver의 기준 온도상승과 전력을 사용해 등가 열저항을 유도한다.
- 온도상승/허용 온도상승으로 냉각부담을 정의하고 baseline 대비 thermal cost index로 통합한다.
- 현재 결과는 비보정 architectural estimate이며 실제 냉각기 가격이나 signoff 온도가 아니다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=306.506, peak_temperature_rise_K=6.50552, temperature_limit_K=358.15, thermal_headroom_K=51.6445, equivalent_stack_thermal_resistance_K_W=1.88566, required_cooling_conductance_W_K=0.0593293, thermal_burden_ratio=0.111875, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=310.514, peak_temperature_rise_K=10.514, temperature_limit_K=358.15, thermal_headroom_K=47.636, equivalent_stack_thermal_resistance_K_W=2.28564, required_cooling_conductance_W_K=0.0791058, thermal_burden_ratio=0.180808, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_12hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=315.442, peak_temperature_rise_K=15.4424, temperature_limit_K=358.15, thermal_headroom_K=42.7076, equivalent_stack_thermal_resistance_K_W=2.68563, required_cooling_conductance_W_K=0.0988822, thermal_burden_ratio=0.265561, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_2stack|ambient_temperature_K=300, predicted_peak_temperature_K=321.028, peak_temperature_rise_K=21.0279, temperature_limit_K=358.15, thermal_headroom_K=37.1221, equivalent_stack_thermal_resistance_K_W=2.28564, required_cooling_conductance_W_K=0.158212, thermal_burden_ratio=0.361615, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_no_pim|ambient_temperature_K=300, predicted_peak_temperature_K=309.143, peak_temperature_rise_K=9.14258, temperature_limit_K=358.15, thermal_headroom_K=49.0074, equivalent_stack_thermal_resistance_K_W=2.28564, required_cooling_conductance_W_K=0.0687876, thermal_burden_ratio=0.157224, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
