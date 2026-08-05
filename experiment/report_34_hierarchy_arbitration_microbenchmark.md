# 34차 실험 보고서: 계층형 PIM 공유 arbiter 정책 비교

## 1. 실험 목적

Bank-side PIM과 logic-die PIM이 공유 interconnect 또는 service port에 동시에 요청을 보낼 때 사용할 arbitration 정책을 비교한다. 기존 simulator에는 두 요청원을 독립 queue로 표현하는 arbiter가 없으므로, RTL 경계와 대응되는 cycle 모델을 먼저 구현했다.

## 2. 구현 구조

`HierarchyPIMArbiter`는 다음 요소를 가진다.

- Bank-side request queue
- Logic-die request queue
- 한 번에 한 요청을 처리하는 공유 service port
- 요청별 arrival cycle과 service cycle
- source별 누적/최대 wait cycle
- ready bypass와 arbitration stall 통계

비교 정책은 다음 네 가지다.

| 정책 | 선택 규칙 |
|---|---|
| Bank priority | Bank가 준비됐으면 항상 먼저 선택 |
| Logic priority | Logic이 준비됐으면 항상 먼저 선택 |
| Strict round-robin | 직전 선택의 반대편을 선택하며 해당 source가 not-ready이면 대기 |
| Ready-bypass | Round-robin 우선순위를 유지하되 우선 source가 not-ready이면 반대편을 선택 |

## 3. Microbenchmark

Cycle 0에 bank 요청 64개와 logic 요청 64개를 동시에 넣는다. 모든 요청의 service time은 1 cycle이고 bank는 항상 ready다. Logic은 broadcast queue backpressure를 모사하기 위해 cycle 0~15에서 `ready=0`, cycle 16부터 `ready=1`이다.

이 trace는 실제 MobileNetV4 실행을 재생한 것이 아니라 arbitration 규칙 자체를 분리 검증하는 합성 trace다. 실제 PIMRank 통합은 다음 구현 단계다.

## 4. 재현 명령

```bash
bash experiment/run_hierarchy_arbitration_microbenchmark.sh
```

단위 테스트 전체는 다음처럼 실행한다.

```bash
./sim --gtest_filter='HierarchyPIMArbiterTest.*'
```

## 5. 결과

| 정책 | 완료 cycle | Bank 누적 대기 | Logic 누적 대기 | Bank 최대 대기 | Logic 최대 대기 | Bypass | Stall |
|---|---:|---:|---:|---:|---:|---:|---:|
| Bank priority | 127 | 2,016 | 6,112 | 63 | 127 | 0 | 0 |
| Logic priority | 127 | 5,088 | 3,040 | 127 | 79 | 0 | 0 |
| Strict round-robin | 142 | 4,977 | 5,056 | 141 | 142 | 0 | 15 |
| Ready-bypass | 127 | 3,192 | 4,936 | 111 | 127 | 15 | 0 |

네 정책 모두 bank와 logic 요청을 각각 64개씩 손실 없이 완료했다. Arbiter 단위 테스트 4개도 모두 통과했다.

## 6. 출력 예시와 주석

```text
HIERARCHY_ARBITRATION_RESULT
policy[ready_bypass]
completion_cycle[127]
bank_wait_cycles[3192]
logic_wait_cycles[4936]
bank_max_wait[111]
logic_max_wait[127]
ready_bypasses[15]
arbitration_stall_cycles[0]
```

- `completion_cycle`: 마지막 요청이 발행된 cycle이다. Cycle 0부터 시작하므로 128개 요청을 빈 cycle 없이 처리하면 127이다.
- `*_wait_cycles`: 각 source 요청의 `issue - arrival` 누적값이다.
- `*_max_wait`: 해당 source에서 가장 오래 기다린 요청의 대기시간이다.
- `ready_bypasses`: 원래 우선 source가 요청은 있지만 not-ready여서 반대 source를 발행한 횟수다.
- `arbitration_stall_cycles`: 처리할 요청이 있는데 정책 때문에 아무것도 발행하지 못한 cycle이다.

## 7. 분석

### 7.1 Strict round-robin은 ready를 고려하지 않으면 포트를 낭비한다

첫 bank 요청을 발행한 뒤 logic 차례가 되지만 logic은 cycle 16까지 not-ready다. Strict 정책은 bank 요청이 남아 있는데도 15 cycle을 쉬어 완료시간이 127에서 142로 증가했다.

### 7.2 Fixed priority는 빠르지만 반대편 starvation 위험이 있다

Bank priority는 모든 bank 요청을 먼저 처리해 logic 최대 대기가 127 cycle이다. Logic priority는 logic이 ready가 된 뒤 logic 요청을 몰아서 처리해 bank 최대 대기가 127 cycle이다. 유한 trace에서는 모두 끝나지만 우선 source 요청이 계속 유입되면 반대편 대기가 제한되지 않는다.

### 7.3 Ready-bypass가 현재 기본 후보다

Ready-bypass는 15개의 idle slot을 bank 요청으로 채워 priority 정책과 같은 127 cycle에 완료했다. Logic이 ready가 된 뒤에는 round-robin으로 돌아가므로 고정 priority보다 장기 공정성을 설명하기 쉽다.

## 8. RTL 요구사항

1. Bank와 logic 요청은 독립 valid/ready queue로 분리한다.
2. Arbiter는 마지막으로 grant한 source를 기억하는 1-bit 상태를 가진다.
3. 기본 선택은 마지막 source의 반대편이다.
4. 우선 source의 `valid=1, ready=0`이면 반대 source의 `valid && ready`를 확인해 우회한다.
5. 우회해도 막힌 요청을 dequeue하지 않는다.
6. Source별 issued count, total wait, max wait, bypass, idle-while-valid counter를 제공한다.
7. 장기 starvation 방지를 위해 이후 age threshold 또는 bounded-wait override를 추가 검증한다.

## 9. 현재 한계

이 arbiter는 독립적으로 검증됐지만 아직 `PIMRank`와 `LogicDieScheduler`의 실제 command 발행 경로에는 연결되지 않았다. 또한 bank와 logic이 공유하는 실제 물리 자원이 command port인지 hierarchy interconnect인지 연구자가 확정해야 한다. 연결 위치에 따라 service time과 ready 정의가 달라진다.

## 10. 다음 단계

`PIMRank`에서 opcode route 결과를 bank request와 logic request로 만들고 `HierarchyPIMArbiter`에 제출한다. 기존 동작 보존을 위한 bypass-off 모드와 ready-bypass 모드를 실제 MobileNetV4 UIB에서 비교한 뒤 source별 wait 통계를 출력한다.
