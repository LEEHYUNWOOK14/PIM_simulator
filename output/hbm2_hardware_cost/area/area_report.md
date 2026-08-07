# Area 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- footprint와 누적 실리콘 면적을 분리한다.
- PIM 추가 면적과 TSV KOZ 상한을 별도 보고한다.
- 방법론 근거는 cacti7/mcpat_hpca2009이며 현재 절대 면적은 project_cost_assumption/project_architecture다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|footprint_area_mm2=100.8, cumulative_silicon_mm2=484.8, logic_area_mm2=100.8, dram_silicon_mm2=384, pim_added_area_mm2=4.8, pim_area_overhead_ratio=0.05, tsv_koz_upper_bound_mm2=0.502655, usable_logic_area_mm2=92.2973, tsv_count_model=256|
|hbm2_8hi_1stack|footprint_area_mm2=100.8, cumulative_silicon_mm2=868.8, logic_area_mm2=100.8, dram_silicon_mm2=768, pim_added_area_mm2=4.8, pim_area_overhead_ratio=0.05, tsv_koz_upper_bound_mm2=1.00531, usable_logic_area_mm2=91.7947, tsv_count_model=512|
|hbm2_12hi_1stack|footprint_area_mm2=100.8, cumulative_silicon_mm2=1252.8, logic_area_mm2=100.8, dram_silicon_mm2=1152, pim_added_area_mm2=4.8, pim_area_overhead_ratio=0.05, tsv_koz_upper_bound_mm2=1.50796, usable_logic_area_mm2=91.292, tsv_count_model=768|
|hbm2_8hi_2stack|footprint_area_mm2=201.6, cumulative_silicon_mm2=1737.6, logic_area_mm2=201.6, dram_silicon_mm2=1536, pim_added_area_mm2=9.6, pim_area_overhead_ratio=0.05, tsv_koz_upper_bound_mm2=2.01062, usable_logic_area_mm2=183.589, tsv_count_model=1024|
|hbm2_8hi_no_pim|footprint_area_mm2=96, cumulative_silicon_mm2=864, logic_area_mm2=96, dram_silicon_mm2=768, pim_added_area_mm2=0, pim_area_overhead_ratio=0, tsv_koz_upper_bound_mm2=1.00531, usable_logic_area_mm2=86.9947, tsv_count_model=512|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
