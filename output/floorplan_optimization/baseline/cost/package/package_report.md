# Package 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- interposer, microbump, TSV, 접합면, routing demand를 독립 proxy로 정규화한다.
- 공개 교차검증은 samsung_flashbolt_hbm2e/skhynix_hbm2_tsv이며 가중치는 견적식이 아닌 프로젝트 정책이다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|microbump_count_model=3072, signal_tsv_count_model=256, bond_interfaces=4, interposer_area_mm2=152.25, package_footprint_mm2=192, stack_height_without_lid_mm=0.348, routing_demand_bit_equivalent=1024, package_complexity_index=0.725|
|hbm2_8hi_1stack|microbump_count_model=6144, signal_tsv_count_model=512, bond_interfaces=8, interposer_area_mm2=152.25, package_footprint_mm2=192, stack_height_without_lid_mm=0.596, routing_demand_bit_equivalent=1024, package_complexity_index=1|
|hbm2_12hi_1stack|microbump_count_model=9216, signal_tsv_count_model=768, bond_interfaces=12, interposer_area_mm2=152.25, package_footprint_mm2=192, stack_height_without_lid_mm=0.844, routing_demand_bit_equivalent=1024, package_complexity_index=1.275|
|hbm2_8hi_2stack|microbump_count_model=12288, signal_tsv_count_model=1024, bond_interfaces=16, interposer_area_mm2=304.5, package_footprint_mm2=384, stack_height_without_lid_mm=0.596, routing_demand_bit_equivalent=2048, package_complexity_index=2|
|hbm2_8hi_no_pim|microbump_count_model=6144, signal_tsv_count_model=512, bond_interfaces=8, interposer_area_mm2=152.25, package_footprint_mm2=192, stack_height_without_lid_mm=0.596, routing_demand_bit_equivalent=1024, package_complexity_index=1|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
