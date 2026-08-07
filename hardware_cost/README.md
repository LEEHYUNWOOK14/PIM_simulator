# HBM2 PIM 하드웨어 비용 분석 파이프라인

## 1. 목적과 설계 철학

이 디렉터리는 HBM2 PIM 구조의 열전달 이외 하드웨어 비용을 `area`, `package`, `yield`, `power_performance` 네 축으로 분석하고, 마지막에 통합 비교 지표를 만든다. 목표는 제조사의 실제 판매가격을 맞히는 것이 아니라 설계 대안 사이의 비용·효율·위험 차이를 재현 가능하게 비교하는 것이다.

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
thermal power + simulator trace ─> power_performance

area/package/yield/power-performance
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

네 비용축은 차원이 다르므로 임의로 더하지 않는다. 먼저 각 축을 기준 설계로 정규화한다.

```text
area_index       = candidate_area_metric / baseline_area_metric
package_index    = candidate_package_metric / baseline_package_metric
yield_cost_index = baseline_good_stack_yield / candidate_good_stack_yield
energy_index     = candidate_energy_per_work / baseline_energy_per_work
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
- `integration/README.md`: 정규화, 가중치, Pareto, 불확실성 전파
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

완료 조건은 스키마 검증, 네 분석 결과, 통합 결과, sensitivity/Monte Carlo 결과, 출처 완전성 검사, 기준/4Hi/12Hi/multi-stack 시나리오, 단위 테스트 및 기존 RTL 회귀가 모두 통과하는 것이다.
