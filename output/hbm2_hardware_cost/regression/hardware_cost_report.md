# HBM2 PIM 전체 하드웨어 비용 분석 보고서

> Architectural relative cost model; not a vendor quote, manufacturing yield disclosure, or signoff result.

## 설계 비교

|설계|Area|Package|Yield|Energy|Thermal|통합 cost|성능|성능/비용|열|용량|종합 feasible|Pareto|
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|---|
|hbm2_4hi_1stack|0.558|0.725|0.672|0.750|0.619|0.661|1.000|1.513|True|False|False|False|
|hbm2_8hi_1stack|1.000|1.000|1.000|1.000|1.000|1.000|1.000|1.000|True|True|True|True|
|hbm2_12hi_1stack|1.442|1.275|1.489|1.250|1.469|1.381|1.000|0.724|True|True|True|False|
|hbm2_8hi_2stack|2.000|2.000|2.735|1.000|2.000|1.854|2.000|1.079|True|True|True|True|
|hbm2_8hi_no_pim|0.994|1.000|0.991|1.565|0.870|1.061|0.556|0.524|True|True|True|True|

## 해석 근거와 한계

- Area는 누적 실리콘 면적, PIM 추가 면적 및 TSV KOZ 상한을 분리한다. 방법 근거: `cacti7`, `mcpat_hpca2009`.
- Package는 interposer, microbump, TSV, 접합면, routing proxy를 사용한다. 공개 규모 교차검증: `samsung_flashbolt_hbm2e`, `skhynix_hbm2_tsv`.
- Yield는 negative-binomial die yield와 die/bond/TSV/assembly 분해를 사용한다. 식/구조 근거: `negative_binomial_yield`, `xu_3d_yield_review`, `stacked_memory_yield_2012`.
- Power/performance는 1024-bit × 2.4 Gbps = 307.2 GB/s/stack을 상한 검증점으로 사용한다: `samsung_aquabolt_hbm2`. 실제 utilization, PIM speedup, power는 추정 범위다.
- Thermal은 3D reference solver의 온도상승/전력으로 등가 열저항을 구하고 허용 온도상승 대비 냉각부담을 다섯 번째 비용축으로 사용한다: `project_thermal`.
- 통합값은 5개 축의 동일 가중 기하평균이라는 프로젝트 정책이며 제조사 가격식이 아니다. 전력과 열은 결합되어 있으므로 개별 지수도 함께 해석한다.

전체 서지정보와 각 주장의 적용 범위는 `hardware_cost/sources.json`을 참조한다.
