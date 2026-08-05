# 29차 실험 보고서: Online Queue Ready와 Backpressure

## 1. 목적

Queue full을 실제 command issue 단계에 연결한다. 사후 trace stall을 더하지 않고 MemoryController가 logic command를 내보내기 전에 scheduler ready를 확인한다.

## 2. 연결 경로

```text
LogicDieScheduler::canAccept
  -> PIMRank::canAcceptLogicDieCommand
  -> Rank::canAcceptCommand
  -> CommandQueue::pop(issuePredicate)
  -> MemoryController command issue
```

`PIMRank`는 CRF의 현재 PC와 JUMP 상태를 복사해 다음 실행 명령을 side effect 없이 미리 해독한다. 따라서 ready 확인은 실제 PC, ordinal, jump counter를 변경하지 않는다.

## 3. Deadlock 방지 규칙

```text
기존에 열린 mask key 요청 : queue full이어도 accept
새 mask key 요청           : open entries가 depth 이상이면 reject
```

모든 요청을 막으면 기존 mask를 완성할 다른 channel도 정지하므로 교착된다. 새 entry만 막으면 느린 channel이 기존 entry를 채운 뒤 공간을 해제할 수 있다.

## 4. 설정

```ini
LOGIC_EPOCH_RELEASE=true
LOGIC_BROADCAST_QUEUE_DEPTH=64
LOGIC_ONLINE_QUEUE_BACKPRESSURE=true
```

Online 모드에서는 기존 trace-derived `applyBroadcastQueueDepth` stall을 적용하지 않는다.

## 5. 재실행 명령

```bash
DEPTH_LIST="32 64 128" \
ONLINE_QUEUE_BACKPRESSURE=true \
RESULT_FILE=experiment/results/online_backpressure_depth_sweep.csv \
bash experiment/run_broadcast_queue_depth_sweep.sh
```

## 6. 결과

| Depth | Project trace peak | Online peak | Blocked channel-cycles | Incomplete masks | Total cycle |
|---:|---:|---:|---:|---:|---:|
| 32 | 32 | 32 | 7,513 | 0 | 214,228 |
| 64 | 64 | 64 | 211 | 0 | 214,228 |
| 128 | 78 | 78 | 0 | 0 | 214,228 |

Online backpressure가 켜지면 실제 명령 도착 trace 자체가 depth 이하로 제한되므로 사후 trace peak도 32/64로 바뀐다. Depth 128은 원래 peak 78보다 커 backpressure가 발생하지 않는다.

## 7. Blocked Channel-cycle 해석

`blocked channel-cycles`는 각 HBM channel의 MemoryController가 issue를 시도했지만 ready가 false였던 횟수의 합이다. 여러 channel이 같은 global cycle에 동시에 막힐 수 있으므로 wall-clock cycle과 같지 않다.

Depth 32와 64에서 blocked channel-cycle이 발생했지만 total cycle이 증가하지 않았다. Logic PCU 및 다른 channel 작업과 겹치면서 command issue 지연이 critical path 밖에서 흡수됐다는 뜻이다. Queue 용량이 작아도 공짜라는 뜻은 아니며, channel별 utilization과 critical-path 위치를 추가로 봐야 한다.

## 8. 검증 불변식

모든 depth에서 다음 조건이 유지됐다.

```text
outputs checked              = 18,816 / 18,816
incomplete expected masks    = 0
broadcast fanout             = 92,512
global dispatch/coalesced    = 1,616 / 90,896
weight-buffer read misses    = 0
trace-derived stall          = 0
```

Scheduler/weight-buffer 단위 테스트 12개도 통과했다. 여기에는 queue full 시 기존 mask는 허용하고 새 mask는 거절하는 테스트가 포함된다.

## 9. 현재 설계 판단

- 128 entries는 backpressure가 없는 보수적 후보다.
- 64 entries는 211 blocked channel-cycles가 있지만 현재 UIB total cycle에는 영향이 없다.
- 32 entries는 7,513 blocked channel-cycles로 pressure가 크게 증가한다.
- 면적 절감을 주장하려면 64-entry 후보를 다른 workload와 channel utilization까지 검증해야 한다.

## 10. 다음 단계

1. Channel별 blocked cycles와 issue count를 출력한다.
2. Block 시점이 logic scheduler busy 구간과 얼마나 겹치는지 계산한다.
3. 64-entry queue가 MobileNetV4 외 pointwise shape에서도 critical path를 늘리지 않는지 확인한다.
