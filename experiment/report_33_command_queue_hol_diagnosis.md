# 33차 실험 보고서: online queue와 command queue HOL 진단

## 1. 실험 목적

Broadcast-mask queue가 full일 때 선택된 logic 명령의 정지가 같은 MemoryController queue에 있는 다른 독립 명령까지 막는 head-of-line(HOL) blocking을 만드는지 확인한다.

## 2. 코드에서 확인한 발행 규칙

`CommandQueue::process_command`는 다음 순서로 동작한다.

1. DRAM timing상 발행 가능한 command를 찾는다.
2. 앞선 동일 주소 command 또는 barrier가 있는지 확인한다.
3. online issue predicate로 logic queue가 command를 받을 수 있는지 확인한다.
4. predicate가 거절하면 뒤쪽 command와 다른 rank를 더 탐색하지 않고 즉시 반환한다.

따라서 구조적으로 HOL 가능성은 있다. 다만 실제 HOL이라고 판단하려면 거절 순간에 다른 발행 가능 command가 실제로 존재해야 한다.

## 3. 계측 정의

| 통계 | 정의 |
|---|---|
| `command_predicate_reject_cycles` | 선택 command가 online predicate에서 거절된 channel-cycle 합 |
| `command_predicate_hol_cycles` | 거절 순간 발행 가능한 대체 command가 하나 이상 존재했던 channel-cycle 합 |
| `command_predicate_hol_candidates` | 위 순간에 발견한 대체 command 수의 누적 |
| `command_predicate_hol_max_candidates` | 한 번의 거절에서 발견한 최대 대체 command 수 |

대체 command는 다음 조건을 모두 만족해야 한다.

- 현재 DRAM timing상 발행 가능
- 앞선 동일 rank/bank/row/column 의존성 없음
- 앞선 barrier 없음
- 부작용 없는 probe predicate 통과

이번 통계는 queue에 이미 들어 있는 READ/WRITE/PIM command만 센다. Queue 탐색 후 동적으로 생성할 수 있는 ACTIVATE/PRECHARGE 기회는 포함하지 않는다.

## 4. 계측 부작용 수정

초기 구현에서는 진단용 후보 탐색도 기존 `canAcceptCommand`를 호출했다. 이 함수는 이름과 달리 거절 시 scheduler stall 통계를 기록하므로, 관찰만 한 후보까지 blocked channel-cycle에 포함됐다.

이를 다음 두 경로로 분리했다.

```text
issue predicate: canAcceptCommand(packet, true)
probe predicate: canAcceptCommand(packet, false)
```

수정 후 기존 기준값 `7,513/211/0`이 복원됐다. RTL의 `ready` 확인과 성능 카운터 갱신도 같은 방식으로 분리해야 한다.

## 5. 재현 명령

```bash
DEPTH_LIST="32 64 128" \
ONLINE_QUEUE_BACKPRESSURE=true \
RESULT_FILE=experiment/results/command_queue_hol_depth_sweep.csv \
bash experiment/run_broadcast_queue_depth_sweep.sh
```

## 6. 결과

| Depth | Predicate reject | Blocked wall-cycle | HOL cycle | HOL 후보 누적 | 최대 후보 | 총 cycle |
|---:|---:|---:|---:|---:|---:|---:|
| 32 | 7,513 | 291 | 0 | 0 | 0 | 214,228 |
| 64 | 211 | 53 | 0 | 0 | 0 | 214,228 |
| 128 | 0 | 0 | 0 | 0 | 0 | 214,228 |

모든 실행에서 정확도 통과, incomplete expected mask 0, weight-buffer read miss 0을 유지했다.

## 7. 출력 예시와 해석

```text
logic_online_issue_blocked_channel_cycles[7513]
command_predicate_reject_cycles[7513]
command_predicate_hol_cycles[0]
command_predicate_hol_candidates[0]
command_predicate_hol_max_candidates[0]
```

`online_issue_blocked_channel_cycles`와 `command_predicate_reject_cycles`가 같으므로 실제 queue-full 거절이 CommandQueue 발행 단계에서 빠짐없이 관측됐다. HOL 값 0은 거절이 없었다는 뜻이 아니라, 거절 당시 우회 발행할 수 있는 독립 queued command가 없었다는 뜻이다.

## 8. 분석

현재 MobileNetV4 UIB에서는 command-level HOL이 관측되지 않았다. 원인은 다음 세 가지가 함께 작용한 결과다.

1. 같은 pointwise epoch의 command가 강한 순서와 주소 의존성을 가진다.
2. barrier 앞뒤 command는 scheduler가 의도적으로 재정렬하지 않는다.
3. queue-full 구간에 발행 가능한 bank-side 독립 command가 같은 rank queue에 동시에 존재하지 않는다.

따라서 현재 total cycle이 depth 64에서도 유지된 이유를 HOL 우회 실행으로 설명할 수 없다. 앞선 보고서에서 확인한 것처럼 queue 정지가 logic PCU busy 시간에 완전히 숨겨졌기 때문이다.

## 9. 설계 판단

- 기존 조기 반환 정책은 현재 workload에서는 성능 손실을 만들지 않았다.
- 그렇다고 조기 반환을 RTL 정책으로 확정하면 안 된다. 다른 workload나 bank/logic 동시 실행에서는 독립 command가 존재할 수 있다.
- Arbitration RTL은 `ready=0`인 logic command를 보존하면서 다른 bank-side queue를 선택할 수 있는 구조가 바람직하다.
- 성능 counter를 갱신하는 `ready` 평가와 관찰 전용 probe는 반드시 분리한다.

## 10. 다음 단계

다음은 bank-side와 logic-side command를 같은 시간 구간에 의도적으로 주입하는 arbitration microbenchmark를 만든다. 이 workload에서 priority, round-robin, logic-ready bypass 정책을 비교해 실제 HOL과 starvation을 측정한다.
