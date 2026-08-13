# Phase 6 — Production Replay/Write-back Gate 보고서

## 상태

**SKIPPED BY DESIGN — architecture decision `NO-GO`**

Phase 6 진입 조건은 Phase 5가 `GO` 또는 `CONDITIONAL GO`일 때만 production activation replay 및 DRAM write-back RTL을 구현하는 것이다. Phase 5의 결정은 `NO-GO`이므로 이 단계에서는 production RTL을 추가하거나 기존 interface를 확대하지 않았다.

## 진입 조건 실패 근거

1. 정확도: 현재 hierarchical BF16 RTL은 기존 `max_abs <= 0.025` 기준을 6개 대표 profile 중 1개에서만 통과했다.
2. 성능: RTX 4060 measured/projected 3.121 ms 대비 hierarchical 40 MHz model은 21.225 ms, speedup 0.147×다.
3. break-even: modeled latency break-even은 275.0 MHz이며 현재 timing evidence보다 높다.
4. replay/write-back: production 구현은 없으며, 낙관적인 각각 1 cycle/bank-vector 비용을 이미 모델에 넣어도 불리하다. 비용을 0으로 둬도 17.019 ms다.
5. 비용 근거: comparable activity-calibrated energy 및 complete physical area가 없다.

따라서 불리한 architecture를 production 수준으로 확장하면 목표 문서의 gate를 위반하고, 정확도 문제를 고착하며, 추가 RTL 규모만 증가시킨다.

## 이번 단계에서 하지 않은 작업

- tag/address 기반 production replay buffer 추가
- DRAM read/replay/write-back scheduler 추가
- multi-vector packet-identity completion tracker 확장
- gamma/beta preload 및 reuse scheduler 추가
- DRAM acceptance/response 기반 row completion 연결
- production path 합성/STA/PPA 주장

기존 workload-independent foundation RTL과 Phase 3/4의 검증용 trace mapping/testbench는 보존한다. 검증 testbench는 production replay/write-back 구현으로 간주하지 않는다.

## 재개 조건

다음 순서로 gate를 다시 열어야 한다.

1. BF16 local/global accumulation과 affine 내부 precision을 확장한다.
2. pretrained action-head representative trace에서 6/6 정확도 기준을 통과한다.
3. 통합 reducer/apply 경로를 최소 modeled break-even 부근에서 timing-close하거나, 병렬화로 동등한 latency를 입증한다.
4. production replay/write-back을 구현하기 전 cycle-accurate buffer/DRAM model로 비용을 좁힌다.
5. energy 또는 area 우위가 핵심 주장이라면 representative switching activity와 동일 공정 조건의 비교 결과를 확보한다.

그 후 Phase 5를 다시 계산해 `GO` 또는 명시적 조건을 가진 `CONDITIONAL GO`가 나올 때만 Phase 6 RTL 구현을 시작한다.

## Gate 산출물

- `reports/groot_normalization/results/actual_groot/architecture_comparison/decision_gate.json`
- `reports/groot_normalization/actual_workload_validation/33_phase4_actual_trace_accuracy_report.md`
- `reports/groot_normalization/actual_workload_validation/34_phase5_actual_traffic_architecture_comparison.md`

이 보고서의 완료 의미는 production RTL 완료가 아니라, 목표 문서가 요구한 **NO-GO 시 근거 없는 RTL 확장을 중단하고 원인과 재개 조건을 기록**했다는 뜻이다.
