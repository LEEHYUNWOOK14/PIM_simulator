# 66차 실험 보고서: Command issuability와 mode latency A/B

> **정정(71차):** 이 문서의 mode latency A/B cycle과 정확도 결과는 유효하지만 bank-state attempt/wall/blocked 수치는 speculative empty-bank PRECHARGE 계측이 포함돼 과대 측정됐다. 보정 결과와 최종 해석은 `experiment/report_71_speculative_precharge_metric_correction.md`를 따른다.

## 1. 목적

65차 실험의 reject attempt 수를 실제 지연 cycle로 오해하지 않도록 DRAM command 발행 실패 원인과 controller 무발행 channel-cycle을 계측한다. 동일한 Full MobileNetV4 UIB에서 mode transition latency 0/32를 비교해 mode FSM이 critical path에 미치는 영향을 측정한다.

## 2. 추가한 발행 실패 분류

`CommandQueue::isIssuable()`의 false 결과를 다음처럼 분리했다.

| 분류 | 의미 |
|---|---|
| `LOGIC_PCU_BUSY` | 전역 scheduler를 쓰지 않을 때 logic PCU가 busy다. |
| `MODE_BLOCKED` | ACT command가 현재 PIM mode에서 허용되지 않는다. |
| `BANK_STATE` | READ/WRITE/PRE에 필요한 idle 또는 active 상태가 아니다. |
| `TIMING` | `nextRead`, `nextWrite`, `nextActivate`, `nextPrecharge` 이전이다. |
| `ROW_MISMATCH` | 열린 row와 요청 row가 다르다. |
| `ROW_ACCESS_LIMIT` | 한 row의 최대 access 수에 도달했다. |
| `XAW_LIMIT` | activation window 제한에 걸렸다. |

각 원인은 세 수준으로 해석한다.

1. `attempts`: scheduler가 검사한 후보 command의 실패 횟수
2. `wall_cycles`: 해당 channel에서 그 원인이 한 번 이상 관찰된 cycle 수
3. `blocked_controller_cycles`: 그 원인이 관찰됐고 해당 channel controller가 최종적으로 아무 command도 발행하지 못한 cycle 수

여기서 wall/blocked 값은 64개 channel을 합산한 **channel-cycle**이다. 전체 workload의 단일 wall-clock cycle과 같지 않다.

## 3. 재현 명령

```bash
bash experiment/run_issuability_mode_latency_ab.sh
```

결과는 `experiment/results/issuability_mode_latency_ab.csv`에 저장되며 실험 종료 후 설정은 기본값으로 복구된다.

## 4. 정확성과 실행시간

| Mode latency | 출력 검증 | Total cycle | Latency 0 대비 |
|---:|---:|---:|---:|
| 0 | 18,816 PASS | 233,556 | 기준 |
| 32 | 18,816 PASS | 235,182 | +1,626 (+0.70%) |

Mode latency 32는 full UIB의 실제 critical path에 1,626 cycle을 추가한다. 1,943,168회의 reject attempt를 손실 cycle로 해석했을 때보다 실제 영향은 훨씬 작다.

## 5. Rank mode-ready 결과

| Mode latency | Rank mode reject attempts | Mode blocked controller channel-cycles | Logic queue blocked |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 32 | 1,943,168 | 160,451 | 0 |

160,451 channel-cycle이 실제 controller 무발행과 겹쳤지만 여러 channel에서 동시에 발생하므로 전체 실행시간 증가는 1,626 cycle이다. Broadcast queue는 두 조건 모두 병목이 아니다.

## 6. DRAM issuability 결과

| 원인 | Latency 0 attempts | Latency 32 attempts | Latency 0 blocked channel-cycles | Latency 32 blocked channel-cycles |
|---|---:|---:|---:|---:|
| Bank state | 588,102,982 | 596,010,320 | 14,358,548 | 14,462,890 |
| Timing | 31,212,598 | 31,160,783 | 2,328,951 | 2,332,601 |
| Row mismatch | 2,991,936 | 2,991,680 | 632,864 | 632,480 |
| Row access limit | 0 | 0 | 0 | 0 |
| XAW limit | 0 | 0 | 0 | 0 |
| Logic PCU busy | 0 | 0 | 0 | 0 |
| CommandQueue mode block | 0 | 0 | 0 | 0 |

Mode latency가 늘어나며 이후 DRAM command의 시간 위상이 이동해 bank-state와 timing 수치도 조금 변했다. 이 차이를 mode 비용과 독립적인 추가 병목으로 합산하면 안 된다.

## 7. 해석

1. Mode transition은 실제 성능에 영향을 주지만 full UIB 영향은 0.70%다.
2. Logic broadcast queue depth 128은 현재 workload에서 충분하다.
3. Bank-state blocked channel-cycle은 mode latency와 무관하게 가장 크다.
4. 각 channel의 bank-state 대기가 병렬로 겹치므로 합산 channel-cycle만으로 global critical path를 확정할 수 없다.
5. 현재 단계에서 mode FSM만 최적화해 얻을 수 있는 상한은 이 실험 조건에서 약 1,626 cycle이다.

## 8. RTL 의미

Logic-die PIM의 mode FSM은 bank/logic domain별로 독립 ready를 유지하는 현재 모델이 맞다. 다만 mode transition을 완전히 제거해도 개선폭이 0.70%이므로 RTL 설계의 주된 novelty를 mode 전환 최적화 하나에 두기에는 근거가 약하다.

더 큰 후보는 다음과 같다.

- bank-side operand staging과 logic-die command가 같은 DRAM bank state를 기다리는 구간
- ACT/PRE가 필요한 row 전환과 logic-die shared buffer fill의 결합
- channel별 대기가 모두 겹치지 못하고 마지막 channel이 stage 종료를 늦추는 tail latency

## 9. 다음 구현

MultiChannelMemorySystem에서 같은 simulator cycle의 64개 controller 상태를 모아 다음 값을 계측한다.

1. 하나 이상의 channel이 막힌 global cycle
2. 모든 active channel이 같은 원인으로 막힌 global cycle
3. stage 종료를 결정한 마지막 channel과 그 channel의 원인별 blocked cycle
4. Expand/project/bank-side stage별 bank-state와 timing 분포

이 계측으로 channel 합산량과 실제 critical path를 분리한 뒤, bank staging 경로 또는 logic-die frontend 중 다음 설계 변경 대상을 선택한다.

## 10. 결론

Mode latency 32의 실제 Full UIB 비용은 1,626 cycle, 0.70%로 측정됐다. 현재 더 큰 구조적 병목 후보는 bank-state 대기이지만, 64채널 병렬 실행에서 global critical path에 기여하는 부분을 추가로 분리해야 한다.
