# Thermal 파이프라인

## 목적

열은 하드웨어 비용 분석의 외부 참고사항이 아니라 다섯 번째 비용축이다. 동일 성능을 내더라도 온도상승이 크면 더 높은 열전도 TIM, 더 큰 heat spreader, 강한 냉각 및 throttling 여유가 필요하기 때문이다. 본 파이프라인은 온도 한계 통과 여부와 냉각 하드웨어 부담을 모두 계산한다.

## 입력

- `output/hbm2_thermal/reference/summary.json`: 3D finite-volume 기준 해석의 입력 전력과 최고온도
- `design/thermal/hbm2_thermal_config.json`: 적층, 재료, 격자 및 solver 설정
- `design/thermal/hbm2_boundary_conditions.json`: ambient와 top/bottom 냉각조건
- 각 비용 시나리오의 stack 수, die 수 및 추정 전력

현재 열 모델은 공개 물성 및 추정 형상을 사용하는 architectural reference model이다. 제조사 패키지로 보정한 signoff 모델이 아니다.

## 계산

기준 열해석에서 등가 열저항을 계산한다.

```text
Rth_reference = (Tpeak_reference - Tambient_reference) / Preference
```

각 시나리오는 전력과 적층 높이에 따른 상대 결합계수를 적용한다.

```text
height_factor = base + slope × dies / 8
deltaT_candidate = Rth_reference × Pcandidate × height_factor
Tpeak_candidate = Tambient + deltaT_candidate
thermal_headroom = Tlimit - Tpeak_candidate
thermal_burden = deltaT_candidate / (Tlimit - Tambient)
thermal_index = thermal_burden_candidate / thermal_burden_baseline
```

`thermal_index`가 1보다 크면 기준 8Hi보다 더 큰 냉각부담을 뜻한다. 이것은 냉각기 가격이 1:1로 증가한다는 뜻이 아니다.

## 전력 비용과의 차이

Energy index는 유용한 작업 하나에 소비한 전기에너지를 측정한다. Thermal index는 그 전력이 구조 안에서 만들어내는 온도상승과 냉각 하드웨어 부담을 측정한다. 두 값은 물리적으로 상관되어 있지만 같은 비용은 아니다. 통합 모델은 두 축을 모두 표시하고, 가중치 민감도를 통해 중복계상 위험을 드러낸다.

## 출력

- `thermal_metrics.json`
- `thermal_report.md`
- 최고온도, 온도상승, 열 여유, 등가 열저항
- 요구 냉각 conductance와 thermal burden/index
- thermal feasibility

## 검증

- 기준 시나리오 thermal index가 1
- 전력 0에서 온도상승 0
- 동일 냉각·전력 조건에서 stack-height penalty 증가 시 열부담 감소 불가
- 최고온도, ambient, limit 단위는 K
- 열 한계 초과 설계는 결과에서 삭제하지 않고 infeasible로 표시
- reference thermal solver의 물리 잔차·대칭·격자/시간 수렴 검증과 연결

## 한계

- 기본 적층 높이 보정식은 상세 시나리오별 3D 재해석을 대신하는 근사다.
- 최종 RTL 전력과 확정 floorplan이 나오면 각 시나리오를 3D solver로 다시 실행해야 한다.
- 실제 냉각기 BOM, junction specification 및 package thermal characterization 없이는 통화 단위 cooling cost를 산출하지 않는다.
