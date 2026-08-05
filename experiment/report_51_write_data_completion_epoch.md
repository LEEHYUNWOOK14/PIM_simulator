# WRITE DATA completion 기반 epoch 보고서

## 1. 문제

기존 Source queue 구현은 WRITE command가 발행되는 순간 transaction을 epoch
outstanding에서 제거했다. 하지만 실제 WRITE data 전송은 `WL + BL/2` 뒤에 끝나므로,
BAR WRITE가 있어도 다음 epoch가 너무 일찍 열릴 수 있었다.

## 2. 수정

- READ는 기존처럼 command 수락 시 완료 처리한다.
- WRITE는 `outgoingDataPacket`의 burst가 끝나는 cycle에 완료 처리한다.
- BAR WRITE의 `logicEpochToIssue_` 또는 `bankEpochToIssue_`도 같은 DATA 완료 cycle에
  증가시킨다.
- Source queue OFF 경로는 변경하지 않는다.

이는 RTL 관점에서 `write_data_done → epoch_release` 의존성을 모델링한다.

## 3. 재현 명령

```bash
HIERARCHY_SOURCE_QUEUES=true bash experiment/run_hierarchy_shared_drain.sh
bash experiment/run_source_queue_stall_breakdown.sh
```

OFF 기준선은 다음과 같이 확인한다.

```bash
HIERARCHY_SOURCE_QUEUES=false bash experiment/run_hierarchy_shared_drain.sh
```

## 4. 결과

### 마이크로 회귀

| 조건 | 출력 | Cycle | Overlap window |
|---|---:|---:|---:|
| Source queue ON, command 완료 기준 | 12 PASS | 1,413 | 57 |
| Source queue ON, DATA 완료 기준 | 12 PASS | 1,425 | 57 |
| Source queue OFF | 12 PASS | 1,942 | 0 |

### 전체 MobileNetV4 UIB

| 항목 | DATA 완료 기준 |
|---|---:|
| 출력 | 18,816 PASS |
| Expand | 88,217 |
| Depthwise | 37,466 |
| Project | 117,559 |
| Add | 3,385 |
| ReLU | 715 |
| 총 cycle | 247,342 |

Command 완료 기준 239,421 cycles보다 7,921 cycles 증가했다. 초기 보수 정책의 단계값과
비교하면 Project가 `110,086 → 117,559`, 즉 7,473 cycles 증가해 대부분을 차지한다.

## 5. 해석

성능은 나빠졌지만 이 수정은 실제 WRITE 완료 전에 다음 epoch를 여는 낙관적 모델을
제거한다. 따라서 247,342 cycles를 앞으로의 정확한 Source queue ON 기준선으로 사용한다.

모든 WRITE barrier를 다시 command 기준으로 되돌리면 정확성 근거가 사라진다. 다음
최적화는 Project output tile의 producer-consumer 관계를 명시하고, 다음 epoch가 해당
output을 소비하지 않는 경우에만 비차단 배출을 허용해야 한다.

## 6. 다음 구현

1. 각 BAR에 tile ID와 dependency ID를 부여한다.
2. Project output WRITE를 `consumer-dependent`와 `drain-only`로 구분한다.
3. `drain-only` output은 DATA 전송을 계속 추적하되 compute epoch만 먼저 release한다.
4. mode/control/writeback BAR는 실제 DATA 완료까지 계속 닫아 둔다.
5. 18,816개 정확도와 Rank/data-bus 오류 없음 조건으로 전체 UIB를 재검증한다.
