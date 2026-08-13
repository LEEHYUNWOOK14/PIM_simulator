# Phase 6 — 열·배선·비용 다목적 구조 비교

## 통합 결과

기존 `output/hbm2_hardware_cost/design_comparison.csv`의 `hbm2_8hi_1stack` cost revision을 모든 coordinate 후보의 공통 제조 구조로 재사용했다. die area, stack 수, TSV 320개, micro-bump 320개, keep-out 4.11775 mm², routing corridor 13.44 mm²가 모든 후보에서 같으므로 좌표 차이로 발생하는 OpenROAD route wirelength와 overflow만 incremental structural-cost proxy에 반영했다.

```text
candidate cost proxy
 = 0.80 × fixed HBM2 8Hi architectural cost index
 + 0.15 × (candidate route wirelength / manual route wirelength)
 + 0.05 × (1 + candidate overflow / maximum candidate overflow)
```

이 식은 제조사 견적이 아닌 명시적인 normalized proxy다. fixed/route/overflow weight를 각각 0.70–0.90, 잔여값, 0–0.10으로 변화시킨 9개 민감도 조합도 출력했다.

| 후보 | Ref. peak (°C) | OpenROAD WL (µm) | Overflow | Cost proxy | 해석 |
|---|---:|---:|---:|---:|---|
| manual_baseline | 38.552 | 59,781.6 | 0 | 1.0000 | clean-overflow 기준선 |
| wirelength_first | 40.585 | 56,297.1 | 0 | 0.9913 | cost/routing 우선, 가장 뜨거움 |
| thermal_first | 37.808 | 58,567.2 | 225 | 1.0284 | 가장 낮은 온도, overflow 있음 |
| balanced | 39.096 | 55,827.9 | 358 | 1.0401 | 최저 WL, 최대 overflow |
| cost_first | 39.096 | 55,827.9 | 358 | 1.0401 | balanced와 동일 좌표 alias |

네 목적축(온도, wirelength, overflow, cost proxy)을 동시에 최소화하면 고유 좌표 후보 네 개가 모두 non-dominated다. 이는 결론 실패가 아니라 실제 trade-off다. cost weight sensitivity winner는 wirelength 5/9, balanced 3/9, manual 1/9다.

## 조건부 추천

- `thermal_first`: reference solver와 3D-ICE가 모두 최저온도로 평가한 **thermal shortlist**다. 후보 macro global route overflow 225가 있으므로 그대로 production 배치로 승격할 수 없다.
- `wirelength_first`: overflow 0, cost proxy 최저인 **routing/cost shortlist**다. reference peak가 baseline보다 2.03 °C 높아 thermal budget 확인이 필요하다.
- `manual_baseline`: overflow 0이며 온도가 wirelength 후보보다 낮은 **conservative fallback**이다.
- `balanced/cost_first`: route WL은 최저지만 overflow 358로 현재 physical proxy에서 오히려 혼잡하다. congestion-aware 재최적화 전에는 production 후보로 권하지 않는다.

따라서 단일 우승안을 강제하지 않고 `thermal_first`와 `wirelength_first`, 그리고 fallback `manual_baseline`을 공동 후보로 유지한다. 현재 RTL global route 자체도 slack `-45.853 ns`이고 detailed route가 실패했으며 후보 macro에는 STA/IR model이 없으므로 최종 배치는 모두 `provisional recommendation`이다.

## 산출물

- `output/floorplan_optimization/candidate_comparison.csv`
- `output/floorplan_optimization/cost_thermal_pareto.csv`
- `output/floorplan_optimization/cost_weight_sensitivity.csv`
- 기존 cost revision: `output/hbm2_hardware_cost/`

모든 행에는 physical/thermal/cost evidence class와 `signoff=NO`가 기록돼 있다.
