# Yield 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 계산 논리
- negative-binomial die yield와 bond/TSV group/assembly yield를 곱한다.
- 식과 분해 근거는 negative_binomial_yield/xu_3d_yield_review/stacked_memory_yield_2012다.
- 모든 기본 수율 숫자는 project_cost_assumption이며 제조사 공개 수율이 아니다.

## 시나리오 결과

|Scenario|핵심 결과|
|---|---|
|hbm2_4hi_1stack|logic_die_yield=0.82274, dram_die_yield=0.909831, bond_chain_yield=0.98015, tsv_group_yield=0.995, assembly_yield=0.99, good_system_yield=0.544323, expected_attempts_per_good_system=1.83714, yield_model=negative_binomial, kgd_assumption=individual die yield retained explicitly; no perfect KGD claim|
|hbm2_8hi_1stack|logic_die_yield=0.82274, dram_die_yield=0.909831, bond_chain_yield=0.960693, tsv_group_yield=0.995, assembly_yield=0.99, good_system_yield=0.365589, expected_attempts_per_good_system=2.73531, yield_model=negative_binomial, kgd_assumption=individual die yield retained explicitly; no perfect KGD claim|
|hbm2_12hi_1stack|logic_die_yield=0.82274, dram_die_yield=0.909831, bond_chain_yield=0.941623, tsv_group_yield=0.995, assembly_yield=0.99, good_system_yield=0.245544, expected_attempts_per_good_system=4.0726, yield_model=negative_binomial, kgd_assumption=individual die yield retained explicitly; no perfect KGD claim|
|hbm2_8hi_2stack|logic_die_yield=0.82274, dram_die_yield=0.909831, bond_chain_yield=0.922931, tsv_group_yield=0.990025, assembly_yield=0.9801, good_system_yield=0.133655, expected_attempts_per_good_system=7.48195, yield_model=negative_binomial, kgd_assumption=individual die yield retained explicitly; no perfect KGD claim|
|hbm2_8hi_no_pim|logic_die_yield=0.830185, dram_die_yield=0.909831, bond_chain_yield=0.960693, tsv_group_yield=0.995, assembly_yield=0.99, good_system_yield=0.368897, expected_attempts_per_good_system=2.71078, yield_model=negative_binomial, kgd_assumption=individual die yield retained explicitly; no perfect KGD claim|

입력 분류와 범위는 `hardware_cost/config.json`, 출처는 `hardware_cost/sources.json`, 적용 논리는 `hardware_cost/RESEARCH_BASIS.md`에 있다.
