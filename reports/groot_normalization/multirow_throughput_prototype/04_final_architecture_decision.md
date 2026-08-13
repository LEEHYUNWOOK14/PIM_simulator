# Final Architecture Decision

## Decision: NO-GO

parameterized RTL prototype은 정확도와 core cycle을 크게 개선했지만 actual traffic과 current mapped clock에서 GPU를 이기지 못한다.

### Winner

```text
8 lanes per bank
4 scalar NR2 engines
2-context ping-pong local reducer
tagged multi-row metadata table
reduce/scalar/apply overlap
```

### End-to-end result

| metric | result |
|---|---:|
| weighted calls | 269 |
| weighted RTL cycles | 262,232 |
| component-bound clock | 35.88MHz |
| core latency | 7.308ms |
| on-die link | 0.040ms |
| hierarchical latency | **7.348ms** |
| measured GPU | **3.121ms** |
| speedup vs GPU | **0.425x** |
| logical traffic | 130,969,088B |
| component-sum area lower bound | 21.52mm² |

GPU break-even은 약 85.1MHz, production gate 1.3x는 약 111.1MHz가 필요하다. 현재 35.9MHz와 차이가 너무 크다.

## 냉정한 해석

- multi-row overlap은 성공했다: serial C11 대비 대표 trace cycle 7.95x 감소.
- 4→8 lanes는 유효하다.
- 8→16 lanes는 실패한 방향이다: cycle 이득보다 timing/area 손실이 크다.
- scalar 4개 이상은 현재 workload에서 무효다.
- full-top mapping조차 현재 flat flow에서 완료되지 않아 component bound보다 실제 PPA가 좋아질 근거가 없다.
- 따라서 production replay/DRAM write-back RTL을 진행하면 안 된다.

## 다음 기술적 선택지

현재 구조를 계속한다면 lane 복제가 아니라 다음 중 하나가 필요하다.

1. FP32 multiplier/add pipeline을 재설계해 full top 85MHz 이상, 안전하게는 111MHz 이상 달성
2. apply arithmetic를 공유/시간다중화하지 않으면서 8-lane routing fanout을 줄이는 physical hierarchy
3. normalization 단독 offload가 아니라 인접 GR00T 연산과 fusion해 GPU launch/traffic 비용까지 제거
4. 더 최신 공정/하드 macro 전제로 PPA 모델을 재수립

1.3x gate와 full-top PPA를 만족하기 전에는 production RTL 단계로 승격하지 않는다.

## Evidence

- `reports/groot_normalization/results/multirow_sky130/component_metrics.csv`
- `reports/groot_normalization/results/multirow_architecture_comparison/lane_dse.csv`
- `reports/groot_normalization/results/multirow_architecture_comparison/winner_profile_cycles.csv`
- `reports/groot_normalization/results/multirow_architecture_comparison/winner_decision.json`

