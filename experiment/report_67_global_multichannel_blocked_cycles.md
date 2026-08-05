# 67차 실험 보고서: 64채널 Global blocked cycle 분석

> **정정(71차):** Bank-state global 수치에는 queued request가 없는 idle bank의 speculative PRECHARGE 검사가 포함됐다. 해당 수치와 이를 이용한 병목 판단은 폐기하고 71차 보정 결과를 사용한다.

## 1. 목적

66차의 channel-cycle 합계는 여러 채널에서 동시에 발생한 대기를 중복 계산한다. 이번 실험은 같은 simulator cycle의 64개 controller 상태를 MultiChannelMemorySystem에서 합쳐 실제 global 진행성과의 관계를 측정한다.

## 2. Global 지표 정의

활성 채널은 해당 cycle update 후 `numOnTheFlyTransactions > 0`인 채널이다.

| 지표 | 의미 |
|---|---|
| `any_cycles` | 활성 채널 중 하나 이상에서 해당 원인이 관찰되고 그 controller가 command를 발행하지 못한 global cycle |
| `all_active_cycles` | 당시 모든 활성 채널에서 해당 원인이 관찰되고 command를 발행하지 못한 global cycle |
| `peak_channels` | 한 cycle에 동시에 해당 원인이 관찰된 최대 활성 채널 수 |

여러 후보 command를 검사하므로 서로 다른 원인의 cycle은 중복될 수 있다. 예를 들어 같은 cycle에 bank-state와 timing 거절이 모두 관찰될 수 있다.

## 3. 재현 명령

```bash
bash experiment/run_issuability_mode_latency_ab.sh
```

Global 결과는 `experiment/results/global_blocked_mode_latency_ab.csv`에 저장된다.

## 4. 결과

### Mode latency 0

| 원인 | Any cycles | All-active cycles | Peak channels |
|---|---:|---:|---:|
| Rank mode ready | 0 | 0 | 0 |
| Bank state | 221,726 | 218,988 | 64 |
| DRAM timing | 38,554 | 35,189 | 64 |
| Row mismatch | 9,954 | 9,862 | 64 |

Total cycle은 233,556이며 출력 18,816개가 모두 통과했다.

### Mode latency 32

| 원인 | Any cycles | All-active cycles | Peak channels |
|---|---:|---:|---:|
| Rank mode ready | 3,171 | 2,155 | 64 |
| Bank state | 224,126 | 219,645 | 64 |
| DRAM timing | 39,563 | 34,360 | 64 |
| Row mismatch | 9,969 | 9,854 | 64 |

Total cycle은 235,182이며 출력 18,816개가 모두 통과했다.

## 5. 해석

1. Mode latency 32는 3,171 global cycles에서 적어도 한 채널의 발행을 막았고, 2,155 cycles에는 당시 모든 활성 채널에서 관찰됐다.
2. 실제 total cycle 증가는 1,626 cycles다. Mode 대기 cycle 일부가 기존 DRAM 대기와 겹치거나 이후 command 위상을 바꾸기 때문이다.
3. Bank-state 대기는 latency 0에서도 all-active 218,988 cycles로 total cycle의 약 93.76%와 공존한다.
4. Peak가 64이므로 bank-state, timing, row mismatch 모두 일부 채널만의 tail 현상은 아니다.
5. Logic queue backpressure는 여전히 0이므로 현재 queue depth 128은 병목이 아니다.

## 6. 중요한 제한

`all_active_cycles`는 해당 원인이 모든 채널에서 **관찰됐다**는 뜻이지, 그 원인 하나만 제거하면 그 cycle에 반드시 command가 발행된다는 뜻은 아니다. CommandQueue에는 다음 hierarchy predicate가 추가로 존재한다.

- epoch mismatch
- barrier outstanding
- write bus busy
- Rank mode ready

한 cycle에 bank-state가 관찰되는 동시에 발행 가능한 다른 command가 epoch barrier에 막힐 수 있다. 따라서 bank-state는 현재 가장 강한 구조적 후보지만 아직 단일 root cause로 확정하지 않는다.

## 7. 설계 관점

현재 결과는 logic-die PCU 계산량보다 command/DRAM 상태 정렬이 더 중요한 후보임을 보여준다. 향후 RTL에서는 다음을 검토할 근거가 된다.

- Logic-die command frontend와 bank operand staging queue의 독립성
- Shared weight/activation buffer가 bank ACT/PRE 상태를 기다리지 않는 직접 경로
- Epoch barrier가 모든 채널의 mode/row 상태를 불필요하게 동기화하는지 여부
- 마지막 channel의 완료가 전체 stage barrier를 지연시키는 tail 처리

## 8. 다음 구현

Epoch mismatch, barrier outstanding, write bus busy, Rank mode-ready 각각에 대해 controller 무발행 여부를 cycle 단위로 기록한다. MultiChannel 계층에서는 다음을 추가한다.

1. Predicate별 any/all-active cycle
2. Bank-state와 predicate가 동시에 발생한 교집합 cycle
3. Issuable command가 하나도 없는 경우와 issuable하지만 predicate가 거절한 경우의 분리
4. 원인을 제거했을 때 실제 발행 가능성이 생기는 exclusive blocker cycle

## 9. 결론

Bank-state 대기는 Full UIB 실행 대부분의 global cycle에서 모든 활성 채널과 공존한다. 이는 강한 구조적 병목 후보지만 epoch/barrier/write-bus 조건과의 중복을 제거하기 전에는 단일 원인으로 확정할 수 없다. 다음 계측은 이 중복을 분해해 실제 설계 변경 대상을 결정한다.
