# 하드웨어 비용 모델의 선행연구 및 출처 적용 보고서

## 출처 사용 원칙

본 보고서는 세 종류의 주장을 구분한다.

1. **공개 사실**: 제조사나 표준기관이 공개한 인터페이스·제품 사양
2. **모델 방법론**: 논문이나 공개 도구가 정당화하는 식과 분해 방식
3. **프로젝트 가정**: 공개되지 않은 수치에 대해 설계공간 탐색을 위해 둔 범위

방법론 출처가 프로젝트 기본 숫자를 보증한다고 해석하지 않는다. 예컨대 negative-binomial 수율식은 선행연구에 근거하지만 `D0=0.1/cm²`는 제조사 공개값이 아니라 프로젝트의 illustrative 입력이다. 이 구분은 `hardware_cost/sources.json`과 `hardware_cost/config.json`에 기계 판독 가능하게 기록된다.

## Area 비용의 근거

CACTI 7.0은 cache/embedded DRAM/commodity DRAM에 대해 access time, power, cycle time 및 area를 함께 모델링하고 multi-bank, 3D memory, off-chip I/O까지 다룬다 (`cacti7`). McPAT은 architecture-level power, area, timing을 통합해 설계공간을 평가하는 방법론을 제시한다 (`mcpat_hpca2009`).

따라서 본 모델은 다음을 비용 proxy로 채택한다.

- 누적 실리콘 면적: 제조되어야 하는 실리콘 자원
- footprint 면적: 패키지 평면 점유
- PIM 추가 면적: baseline 대비 logic overhead
- TSV KOZ: TSV가 논리 배치에 주는 면적 상한

단, CACTI/McPAT을 실행하지 않은 값에는 해당 도구의 출처를 붙이지 않는다. 현재 4.8 mm² PIM 기본값은 `project_cost_assumption`이며 향후 Yosys/OpenROAD/CACTI 결과로 교체해야 한다.

## Package 비용의 근거

Samsung Aquabolt HBM2는 2.4 Gbps/pin, 1.2 V, 307 GB/s/stack을 공개한다 (`samsung_aquabolt_hbm2`). SK hynix는 HBM2가 4Hi/8Hi, 1,024 data pins, 1.6–2.4 Gbps/pin, 204–307 GB/s/stack 범위임을 설명하고 TSV pitch/diameter/aspect ratio, die thinning과 assembly yield 유지가 확장 난제라고 밝힌다 (`skhynix_hbm2_tsv`). Samsung HBM2E Flashbolt의 8-die 및 40,000개 이상 연결 언급은 적층 연결 규모가 비용 항목이어야 함을 보여주는 교차검증점이다 (`samsung_flashbolt_hbm2e`). HBM2E 수치를 HBM2의 정확한 좌표/개수로 복사하지 않는다.

이에 따라 interposer area, model TSV count, microbump count, bond interfaces, routing demand를 서로 분리한다. 기본 가중합은 견적식이 아니라 상대 제조복잡도 proxy다.

## Yield 비용의 근거

Negative-binomial 모델은 결함밀도의 clustering을 허용하며 다음 식을 사용한다 (`negative_binomial_yield`).

```text
Y = (1 + D0 A / alpha)^(-alpha)
```

ASP-DAC의 3D stacked IC yield review는 known-good-die, pre-bond testing, TSV redundancy, bonding 및 TSV yield를 별도 문제로 다룬다 (`xu_3d_yield_review`). Stacked memory 연구 역시 stacked-die yield와 interconnect yield를 함께 고려해야 함을 설명한다 (`stacked_memory_yield_2012`). 그래서 본 모델은 die, bond, TSV group, assembly 확률을 곱하되 각각을 출력한다.

제조사의 `D0`, `alpha`, bond yield, TSV yield는 공개되지 않았다. 기본값 전체는 `project_cost_assumption`이며 P5/P50/P95 민감도 분석 이외의 실제 수율 주장에 사용할 수 없다.

## Power/Performance 비용의 근거

이론 대역폭은 공개 인터페이스 사양으로 직접 검산한다.

```text
1024 bit / 8 × 2.4 Gbit/s = 307.2 GB/s per stack
```

이는 Samsung 공개 307 GB/s와 일치한다 (`samsung_aquabolt_hbm2`). 실제 성능은 이론 대역폭이 아니라 utilization과 workload 특성에 좌우된다. Roofline 연구는 operational intensity, compute ceiling, memory-bandwidth ceiling을 분리하는 방법을 제공한다 (`roofline_berkeley`). Samsung의 HBM-PIM 공개는 PIM이 실제 연구/제품 방향임을 뒷받침하지만, 제조사의 워크로드 결과를 본 RTL의 성능값으로 복사하지 않는다 (`samsung_hbm_pim`). 현재 speedup 1.8과 utilization 0.7은 프로젝트 가정이다.

## 통합 지표의 근거와 정책성

Area, package, yield cost, energy는 단위가 달라 직접 합산할 수 없다. 각 항목을 baseline 비율로 만든 후 가중 기하평균한다. 이는 비율 척도의 균형을 위한 **프로젝트 의사결정 규칙**이며 특정 논문이나 제조사의 가격 공식이 아니다. 결과는 개별 지수, 물리량, Pareto frontier와 함께만 해석한다.

## 공개정보로 확정할 수 없는 항목

- 실제 HBM2 DRAM/logic die 면적과 GDS
- TSV 및 microbump의 정확한 signal/power 좌표
- 웨이퍼 가격, 결함밀도, die/bond/TSV/assembly yield
- PHY와 bank peripheral 면적
- 제조 테스트 시간과 KGD escape rate
- 고객별 HBM 가격 및 OSAT/파운드리 견적

이 항목은 향후 NDA/vendor/측정 자료가 들어와야 absolute cost 모델로 승격할 수 있다. 현재 결과는 상대 아키텍처 분석이다.
