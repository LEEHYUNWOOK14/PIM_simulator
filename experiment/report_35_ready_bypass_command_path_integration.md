# 35차 실험 보고서: ready-bypass 실제 CommandQueue 통합

## 1. 실험 목적

34차 사전 통합 arbiter에서 선택한 ready-bypass 정책을 실제 simulator command 발행 경로에 연결한다. 정책 비활성 시 기존 동작을 보존하고, 활성 시 blocked logic command를 삭제하지 않은 채 뒤쪽 ready command를 탐색하도록 한다.

## 2. 통합 위치

Bank-side와 logic-side opcode는 `PIMRank`에서 route되지만, 여러 command 중 이번 cycle에 하나를 발행하는 실제 직렬화 지점은 `MemoryController::CommandQueue`다. 따라서 다음 경로로 통합했다.

```text
MemoryController
  → CommandQueue::process_command
    → Rank::canAcceptCommand
      → PIMRank::canAcceptLogicDieCommand
        → LogicDieScheduler::canAccept
```

`HIERARCHY_READY_BYPASS=false`이면 첫 predicate reject에서 기존처럼 반환한다. `true`이면 blocked packet을 queue에 남겨두고 뒤쪽 command를 계속 검사한다. 뒤쪽 검사는 counter를 바꾸지 않는 probe predicate를 사용한다.

## 3. 새 설정

```ini
HIERARCHY_READY_BYPASS=false
```

- `false`: 기존 strict command 발행 동작
- `true`: logic command가 not-ready이면 뒤쪽 ready command 발행 허용

기본값은 회귀 안전성을 위해 `false`다.

## 4. 재현 명령

```bash
bash experiment/run_hierarchy_ready_bypass_sweep.sh
```

기본 sweep은 bypass `false/true`와 queue depth `32/64/128`의 6개 실제 MobileNetV4 UIB 실행을 수행한다.

## 5. 결과

| Bypass | Depth | Blocked channel-cycle | Predicate reject | HOL cycle | 실제 bypass 발행 | 총 cycle |
|---|---:|---:|---:|---:|---:|---:|
| false | 32 | 7,513 | 7,513 | 0 | 0 | 214,228 |
| false | 64 | 211 | 211 | 0 | 0 | 214,228 |
| false | 128 | 0 | 0 | 0 | 0 | 214,228 |
| true | 32 | 7,513 | 7,513 | 0 | 0 | 214,228 |
| true | 64 | 211 | 211 | 0 | 0 | 214,228 |
| true | 128 | 0 | 0 | 0 | 0 | 214,228 |

6개 실행 모두 정확도 통과, incomplete expected mask 0, weight-buffer read miss 0이다.

## 6. 출력 예시와 주석

```text
hierarchy_ready_bypass[true]
command_predicate_reject_cycles[7513]
command_predicate_hol_cycles[0]
command_predicate_bypass_issues[0]
total_cycle[214228]
```

- `command_predicate_reject_cycles`: 첫 blocked logic command를 만난 channel-cycle 수다.
- `command_predicate_hol_cycles`: 그 순간 발행 가능한 뒤쪽 command가 존재한 cycle 수다.
- `command_predicate_bypass_issues`: 실제로 뒤쪽 command를 대신 발행한 횟수다.
- `bypass_issues=0`은 정책이 연결되지 않았다는 뜻이 아니다. 현재 UIB에는 predicate를 통과하는 뒤쪽 독립 command가 없다는 33차 결과와 일치한다.

## 7. 계측 정확성 수정

초기 활성 실행에서는 depth 32 blocked 값이 7,513에서 52,591로 증가했다. Bypass 탐색 중 만난 뒤쪽 not-ready packet마다 실제 predicate를 호출해 같은 channel-cycle을 여러 번 기록했기 때문이다.

수정된 규칙은 다음과 같다.

1. 첫 packet만 실제 predicate로 평가하고 거절 통계를 기록한다.
2. 같은 pop 호출의 뒤쪽 packet은 probe predicate로 평가한다.
3. Probe는 queue 상태와 stall counter를 변경하지 않는다.
4. 실제 발행 가능한 packet을 찾았을 때만 bypass issue를 1 증가시킨다.

수정 후 blocked 통계가 기존 `7,513/211/0`으로 복원됐다.

## 8. 분석

현재 UIB는 pointwise logic epoch와 후속 bank-side add/ReLU가 barrier로 구분돼 command queue 안에서 동시에 발행 가능한 상태가 아니다. 따라서 실제 ready-bypass 기회가 없다. 이는 정책 효과를 부정하는 결과가 아니라 현재 workload ordering의 특성을 보여준다.

정책 효과는 34차 동시 요청 microbenchmark에서 확인됐다. Strict round-robin의 15 idle cycle을 ready-bypass가 제거해 완료 cycle을 142에서 127로 줄였다. 실제 MobileNetV4에서 효과를 보려면 bank-side와 logic-side stage 사이의 barrier를 완화하거나 서로 다른 독립 block/channel의 요청을 겹치는 workload scheduler가 필요하다.

## 9. 설계 판단

- Ready-bypass 실제 발행 경로는 구현됐고 비활성 기본값에서 기존 동작을 보존한다.
- 활성화해도 현재 UIB의 정확도와 timing을 변경하지 않는다.
- RTL에서는 독립 bank/logic queue가 있으므로 34차 arbiter 정책을 직접 적용할 수 있다.
- Simulator에서 실제 성능 차이를 만들려면 workload-level overlap scheduler가 먼저 필요하다.

## 10. 다음 단계

다음은 서로 독립인 logic pointwise와 bank-side eltwise/depthwise stage를 다른 spatial tile에서 겹쳐 enqueue하는 overlap scheduler다. 이때 barrier 범위를 전체 epoch가 아니라 tensor dependency가 있는 tile로 좁히고 ready-bypass issue와 source별 wait를 실제 workload에서 측정한다.
