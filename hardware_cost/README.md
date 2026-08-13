# HBM2 PIM 하드웨어 비용 분석 파이프라인

## Current implementation status

Memory-bound adapter의 RTL 기능, timing/credit protocol, Yosys generic synthesis는 검증되었다. Generic synthesis는 1,644 cells로 lowering되었고 Yosys `check`는 0 problems이며 명백한 combinational loop나 unintended latch는 확인되지 않았다. 이는 RTL과 논리 합성 가능성의 증거이지 물리 구현 완료의 증거는 아니다.

현재 physical-feasibility 상태는 수동 문장으로 고정하지 않고 [자동 생성 보고서](../reports/hardware_cost_physical_feasibility/physical_feasibility_report.md)를 기준으로 한다. Pipeline은 adapter mapping, integrated PCU+adapter mapping/STA, coarse placement, global routing을 PF-0~PF-4로 분리하고, 서로 다른 mapped revision의 증거가 섞이지 않도록 source SHA-256과 revision coherence를 검사한다.

Sky130은 최종 공정 PPA를 예측하기 위한 것이 아니라 제안 RTL이 표준 셀로 매핑되고 실제 placement/global-routing flow를 통과할 수 있는지를 확인하기 위한 공개 공정 proxy로만 사용한다. 결과는 production-process PPA, timing closure 또는 sign-off evidence로 취급하지 않는다.

## 1. 목적과 설계 철학

이 디렉터리는 HBM2 PIM 구조의 전체 하드웨어 비용을 `area`, `package`, `yield`, `power_performance`, `thermal` 다섯 축으로 분석하고 마지막에 통합 비교 지표를 만든다. 열은 단순 통과 조건이 아니라 온도상승, 열저항, 열 여유와 냉각부담을 나타내는 독립 비용축이다. 목표는 제조사의 실제 판매가격을 맞히는 것이 아니라 설계 대안 사이의 비용·효율·위험 차이를 재현 가능하게 비교하는 것이다.

제조사 공개자료는 용량, 적층 수, 핀 속도, 대역폭, 전압, 일부 TSV/마이크로범프 수는 제공하지만 웨이퍼 가격, 결함밀도, 접합수율, 실제 다이 면적, 실제 PHY/TSV 좌표 및 제조원가는 공개하지 않는다. 따라서 결과는 다음 두 계층으로 분리한다.

1. `physical_metrics`: mm², 개수, W, GB/s, ns처럼 직접 해석 가능한 물리량
2. `normalized_indices`: 기준 설계를 1.0으로 둔 상대 비용·위험·효율 지수

통화 단위 비용은 사용자가 검증된 제조 데이터를 제공했을 때만 활성화한다. 기본 결과는 BOM 가격이나 견적이 아니며 `architectural_estimate_not_vendor_quote`로 표시한다.

## 2. 전체 데이터 흐름

```text
design/hbm2_architecture.json ─┬─> area
OpenROAD/Yosys report adapter ─┘

architecture + area ─────────────> package
area + package assumptions ──────> yield
thermal solver + power trace ─────> thermal
simulator/activity trace ─────────> power_performance

area/package/yield/power-performance/thermal
                  └──────────────> integration
                                      ├─ physical metrics
                                      ├─ normalized cost indices
                                      ├─ Pareto ranking
                                      └─ provenance/uncertainty report
```

각 파이프라인은 다른 파이프라인의 내부 구현이 아니라 JSON 결과 계약에만 의존한다. RTL이 수정 중이어도 synthetic 입력으로 실행할 수 있으며, 합성 결과가 생기면 area adapter만 교체한다.

## 3. 공통 입력 계약

모든 수치 입력은 다음 메타데이터를 가진다.

```json
{
  "value": 96.0,
  "unit": "mm^2",
  "classification": "illustrative",
  "source_id": "project_architecture_die_geometry",
  "confidence": "low",
  "uncertainty": {"distribution": "uniform", "min": 75.0, "max": 120.0}
}
```

허용 `classification`은 `standard`, `manufacturer_public`, `measured_public`, `open_source_model`, `project_config`, `rtl_derived`, `derived`, `literature_estimate`, `estimated`, `illustrative`다. 출처 없는 값은 `estimated` 또는 `illustrative`만 허용한다.

`hardware_cost/sources.json`이 출처의 단일 기준이다. 각 항목은 URL/DOI, 문서명, 발행기관, 접근일, 사용한 주장, 모델에 반영한 변수, 한계를 기록한다. 식의 근거와 수치의 근거는 별도로 기록한다. 예를 들어 Poisson 수율식의 근거가 있어도 결함밀도 값까지 공개 근거가 생기는 것은 아니다.

## 4. 통합 방법

다섯 비용축은 차원이 다르므로 임의로 더하지 않는다. 먼저 각 축을 기준 설계로 정규화한다.

```text
area_index       = candidate_area_metric / baseline_area_metric
package_index    = candidate_package_metric / baseline_package_metric
yield_cost_index = baseline_good_stack_yield / candidate_good_stack_yield
energy_index     = candidate_energy_per_work / baseline_energy_per_work
thermal_index    = candidate_cooling_burden / baseline_cooling_burden
```

사용자가 명시한 가중치가 있을 때만 가중 기하평균을 계산한다.

```text
combined_cost_index = exp(Σ w_i × ln(index_i)),  Σw_i=1
```

기하평균을 쓰는 이유는 각 축이 비율 척도이고, 한 축의 매우 큰 악화를 다른 축의 단순 차감으로 상쇄하지 않기 위해서다. 기본 가중치는 판단을 숨기지 않도록 동일 가중치이며, 모든 개별 지수를 함께 보고한다. 성능은 비용과 섞기 전에 별도 분모로 둔다.

```text
performance_per_cost = normalized_performance / combined_cost_index
```

가중 순위 외에 Pareto frontier를 반드시 제공한다. 이는 가중치 선택에 의해 유리한 설계가 바뀌는 문제를 드러낸다.

## 5. 디렉터리

- `area/README.md`: 로직·메모리·TSV KOZ 면적
- `package/README.md`: interposer·범프·TSV·배선·적층 복잡도
- `yield/README.md`: 다이·TSV·접합·조립 수율과 known-good-die
- `power_performance/README.md`: 전력, 에너지/비트, 대역폭, 지연, PIM 처리량
- `thermal/README.md`: 3D 온도, 열저항, 열 여유, 냉각부담
- `integration/README.md`: 5축 정규화, 가중치, Pareto, 불확실성 전파
- `sources.json`: 출처와 적용 주장
- `config.json`: 기준 설계, 추정 범위, 가중치

## 6. 해석 제한

- HBM2 호환 인터페이스 모델이지 제조사 내부 레이아웃 복제물이 아니다.
- 공개되지 않은 제조수율과 가격은 범위 분석 대상이다.
- OpenROAD 면적은 사용한 표준셀 라이브러리/공정에 종속되며 DRAM 공정 면적과 직접 합산할 때 분류를 유지해야 한다.
- thermal solver의 synthetic power는 측정 전력이 아니다.
- 상대 지수가 1.2라고 해서 실제 가격이 정확히 20% 비싸다는 의미는 아니다.

## 7. 실행 및 완료 기준

최종 진입점은 다음을 순서대로 수행한다.

```powershell
.\tools\run_hbm2_hardware_cost_analysis.ps1
```

완료 조건은 스키마 검증, 다섯 분석 결과, 통합 결과, sensitivity/Monte Carlo 결과, 출처 완전성 검사, 기준/4Hi/12Hi/multi-stack 시나리오, thermal solver 검증, 단위 테스트 및 기존 RTL 회귀가 모두 통과하는 것이다.

## 8. Lightweight Physical Feasibility Gate

하드웨어 비용 파이프라인 v2는 `physical_feasibility`를 revision snapshot의 필수 1급 객체로 취급한다. PF-0 RTL feasibility, PF-1 adapter standalone technology mapping/STA, PF-2 PCU+adapter integrated mapping/STA, PF-3 coarse legal placement, PF-4 global routing/congestion을 서로 분리해 판정한다. 증거가 없거나 실행 중이면 수치를 추정하지 않고 `PENDING`/`null`로 유지한다.

```powershell
.\tools\run_hardware_cost_physical_feasibility.ps1
```

기존 증거를 수집하는 대신 integrated placement, STA, global routing까지 재실행하려면 다음을 사용한다. 3M-cell 이상 설계를 처리하므로 충분한 WSL 메모리와 실행 시간이 필요하다.

```powershell
.\tools\run_hardware_cost_physical_feasibility.ps1 -RunPhysicalFlow
```

동일 WSL에서 다른 OpenROAD placement/routing 작업과 동시에 실행하지 않는다. PF-4 전용 runner는 메모리 증가를 제한하기 위해 1 thread, 1 congestion iteration을 사용하고, 5,000 terminal을 넘는 clock/reset/constant net만 명시적 예외로 허용한다. 일반 datapath net이 skip되면 PF-4는 PASS하지 않는다.

현재 증거를 재생성하는 원본 flow는 다음과 같다. 이 명령은 EDA 환경이 준비된 WSL에서 별도로 실행하며, 비용 파이프라인 runner는 기존 산출물을 읽고 해시를 고정할 뿐 장시간 flow를 암묵적으로 재실행하지 않는다.

```bash
verification/groot_normalization/run_normalization_adapter_sky130_feasibility.sh
verification/groot_normalization/run_normalization_hbm_top_sky130_mapping.sh
tools/run_hardware_cost_integrated_placement.sh
tools/run_hardware_cost_integrated_sta.sh
verification/groot_normalization/run_normalization_hbm_v4_route.sh
```

이 gate는 Sky130 standard-cell 기반의 경량 구현 가능성 검사다. CTS, detailed route, extraction, timing closure, IR/EM, DRC/LVS, power, thermal, 제조 가능성 및 silicon signoff를 주장하지 않는다. `production_signoff`는 항상 `NOT_TARGETED`이며, PF-0~PF-4 PASS, 설명되지 않은 unconstrained path 부재, routing overflow 부재를 만족해야 `rtl_freeze_allowed=true`가 된다. 프로젝트 reference timing은 위험 지표로 보고하지만 target clock closure는 이 gate의 필수 조건이 아니다.

현재 adapter의 `x_word_q`, `affine_word_q`, `wb_word_q`는 총 12,288 logical bit의 standard-cell register로 내려간다. 별도 SRAM macro가 추론되지 않았으므로 buffer 구현 위험을 `HIGH`로 표시한다. Buffer 면적은 매핑된 DFF 1개의 cell area × 12,288 bit로 계산한 storage-cell-only 값이며, 관련 mux/control, clock tree, placement whitespace와 routing area는 포함하지 않는다.

Generic synthesis에서 기록된 145,852 wire bits는 16-bank wide datapath의 연결 압력을 알리는 구조적 경고로 유지한다. 이 값은 실제 routing congestion의 직접 측정치가 아니며, congestion 판정에는 PF-4 global-route report만 사용한다.

현재 authoritative global-route 측정은 v4다. 565개 `cmd_*`/`read_*` 경계 핀을 logic-die 내부 met5 landing-pad grid로 분산하고 signal met1-met5, clock met2-met5를 사용했다. v2의 residual congestion 1,600,437은 v4에서 2,620으로 감소했지만 0이 아니며, 상세 congestion violation 5,998개와 최대 local overuse 5가 남아 PF-4는 FAIL이다. v4는 완전한 guide와 congestion report를 생성했지만 launcher 종료 전에 clean exit marker를 남기지 못했으므로 이 제한도 별도로 기록한다.
