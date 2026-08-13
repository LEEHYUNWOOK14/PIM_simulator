# Thermal 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- 3D finite-volume reference solver의 기준 온도상승과 전력을 사용해 등가 열저항을 유도한다.
- 온도상승/허용 온도상승으로 냉각부담을 정의하고 baseline 대비 thermal cost index로 통합한다.
- 현재 결과는 비보정 architectural estimate이며 실제 냉각기 가격이나 signoff 온도가 아니다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=316.068, peak_temperature_rise_K=16.0684, temperature_limit_K=358.15, thermal_headroom_K=42.0816, equivalent_stack_thermal_resistance_K_W=4.6575, required_cooling_conductance_W_K=0.0593293, thermal_burden_ratio=0.276326, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=325.969, peak_temperature_rise_K=25.9691, temperature_limit_K=358.15, thermal_headroom_K=32.1809, equivalent_stack_thermal_resistance_K_W=5.64545, required_cooling_conductance_W_K=0.0791058, thermal_burden_ratio=0.446588, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_12hi_1stack|ambient_temperature_K=300, predicted_peak_temperature_K=338.142, peak_temperature_rise_K=38.1421, temperature_limit_K=358.15, thermal_headroom_K=20.0079, equivalent_stack_thermal_resistance_K_W=6.63341, required_cooling_conductance_W_K=0.0988822, thermal_burden_ratio=0.655926, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_2stack|ambient_temperature_K=300, predicted_peak_temperature_K=351.938, peak_temperature_rise_K=51.9382, temperature_limit_K=358.15, thermal_headroom_K=6.21183, equivalent_stack_thermal_resistance_K_W=5.64545, required_cooling_conductance_W_K=0.158212, thermal_burden_ratio=0.893176, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|
|hbm2_8hi_no_pim|ambient_temperature_K=300, predicted_peak_temperature_K=322.582, peak_temperature_rise_K=22.5818, temperature_limit_K=358.15, thermal_headroom_K=35.5682, equivalent_stack_thermal_resistance_K_W=5.64545, required_cooling_conductance_W_K=0.0687876, thermal_burden_ratio=0.388337, thermal_feasible=1, reference_solver=output/hbm2_thermal/reference/summary.json, evidence=derived from the uncalibrated architectural thermal reference model|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
