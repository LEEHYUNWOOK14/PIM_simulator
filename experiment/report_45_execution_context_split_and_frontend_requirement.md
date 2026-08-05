# 실험 45: 실행 컨텍스트 분리 검증과 독립 logic frontend 요구사항

## 1. 실험 목적

Bank PCU와 logic PCU의 CRF, PC, jump/repeat 상태, PIM mode를 분리한 변경이
기존 실행을 보존하는지 확인하고, source queue 동시 실행 실패의 다음 원인을 찾는다.

## 2. 재현 명령

```bash
# 기존 경로 회귀: source queue 비활성
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
HIERARCHY_SOURCE_QUEUES=false \
bash experiment/run_shared_weight_fill_channel_sweep.sh

# bank/logic 동시 drain: source queue 활성
HIERARCHY_SOURCE_QUEUES=true \
bash experiment/run_hierarchy_shared_drain.sh
```

## 3. 결과

| 항목 | source queue OFF | source queue ON |
|---|---:|---:|
| 테스트 | ActualShapeUibRunsEndToEnd | BankDepthwiseStageAndLogicPointwiseShareDrain |
| 정확도 | 18,816개 통과 | 0/12, 실패 |
| 총/Drain cycle | 216,976 | 1,545 |
| Bank issue | 전체 UIB 통계 대상 아님 | 2,048 |
| Logic issue | 전체 UIB 통계 대상 아님 | 0 |
| Bank issue window | - | 1,739~2,351 |
| Logic issue window | - | 없음 |
| issue overlap | - | 0 |

Source queue ON에서 반환된 첫 값들은 `1, 2, 6, 4, 5, 15, ...`이고 기대값은
`25, 26, 78, 28, 29, 87, ...`이었다. 반환값은 마지막 입력 행이 아니라 이전 행의
결과이므로 stale readback으로 판정한다.

## 4. 상세 해석

### 4.1 컨텍스트 분리는 필요하지만 충분하지 않다

분리 전에는 logic 결과가 0으로 반환됐다. CRF/PC/mode 분리 후에는 과거 행의 결과가
반환되므로 logic 명령 스트림이 더 멀리 진행한 것은 맞다. 그러나 `logic_issues=0`인
상태에서 readback이 완료됐다. 따라서 결과 read가 실제 logic MAC 완료를 기다린다는
순서 보장이 없다.

### 4.2 남은 공유 상태

Logic 패킷도 `MemoryController::transactionQueue`, `CommandQueue`, 물리 `BankState`,
ACT/PRE 생성 경로를 그대로 사용한다. Source별 barrier/dependency만 분리하면 한쪽
명령의 ACT/PRE가 다른 쪽이 의존하는 열린 row를 바꾸거나, 뒤쪽 result read가 앞쪽
logic compute보다 먼저 발행될 수 있다.

### 4.3 다음 구현 판단

Logic-die 제어 패킷은 독립 command frontend와 가상 제어 상태를 사용해야 한다.
반면 일반 row의 weight/input/output 패킷은 실제 HBM 접근이므로 기존 물리 bank timing과
data bus를 공유해야 한다. 구체적인 분류와 불변조건은
`design/logic_command_frontend_contract.md`에 정의했다.

## 5. 출력 판독 방법

```text
HIERARCHY_SHARED_DRAIN_RESULT ...
logic_outputs_checked[12]
bank_issues[2048]
logic_issues[0]
pending_after_drain[0]
[  FAILED  ] ...
```

- `logic_outputs_checked[12]`: 비교한 원소 수이며 통과 개수가 아니다.
- `logic_issues[0]`: logic PCU가 실제 연산을 한 번도 발행하지 않았다는 뜻이다.
- `pending_after_drain[0]`: 큐가 비었다는 뜻일 뿐, 올바른 순서로 계산됐다는 뜻은 아니다.
- `[ FAILED ]`: 값 불일치와 logic issue 부재 때문에 기능 검증에 실패했다.

## 6. 결론

기존 source queue OFF 정확도는 보존됐다. Source queue ON 실패는 스케줄러 용량 문제가
아니라 독립 제어 경로가 없는 구조 문제다. 다음 단계는 logic 예약주소 제어와 일반 HBM
데이터 접근을 분류하고, logic 제어만 별도 frontend로 분리하는 것이다.
