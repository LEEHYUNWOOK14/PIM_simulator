# 68차 실험 보고서: Global hierarchy predicate blocker 분석

> **정정(71차):** Epoch/barrier/write-bus 수치는 유효하지만 비교 대상인 bank-state 수치가 speculative PRECHARGE로 오염됐다. Bank-state와의 상대 비교 및 우선순위 결론은 71차 보고서로 대체한다.

## 1. 목적

67차에서 발견한 bank-state all-active cycle이 epoch, barrier, write-bus 조건과 얼마나 함께 나타나는지 확인하기 위해 hierarchy predicate도 controller 무발행 및 MultiChannel global 지표로 확장한다.

## 2. 계측 대상

| Predicate | 의미 |
|---|---|
| `EPOCH_MISMATCH` | packet epoch가 현재 발행해야 할 epoch와 다르다. |
| `BARRIER_OUTSTANDING` | barrier보다 앞선 transaction이 아직 완료되지 않았다. |
| `WRITE_BUS_BUSY` | write data bus 또는 예약된 write slot이 사용 중이다. |

실제 command가 발행된 cycle은 blocker로 세지 않는다. Controller가 아무 command도 발행하지 못한 cycle에 해당 predicate가 관찰된 경우만 집계한다.

## 3. 재현 명령

```bash
LATENCIES=32 bash experiment/run_issuability_mode_latency_ab.sh
```

결과는 `experiment/results/global_predicate_blocked_mode_latency_ab.csv`에 저장된다.

## 4. Full UIB 결과

설정은 HAB residency ON, mode latency 32, source queue ON, broadcast queue 128, output buffer 2 entries다.

| Global blocker | Any cycles | All-active cycles | Peak channels |
|---|---:|---:|---:|
| Epoch mismatch | 25,377 | 19,866 | 64 |
| Barrier outstanding | 22,565 | 15,718 | 64 |
| Write bus busy | 28,773 | 26,013 | 64 |
| Rank mode ready | 3,171 | 2,155 | 64 |
| Bank state | 224,126 | 219,645 | 64 |

출력 18,816개가 모두 통과했고 total cycle은 235,182다.

## 5. 해석

1. Hierarchy predicate 세 종류 모두 일부 global cycle에서 64개 채널을 동시에 막는다.
2. All-active 기준 최대 predicate는 write-bus busy 26,013 cycles다.
3. Bank-state all-active 219,645 cycles는 개별 hierarchy predicate보다 8배 이상 크다.
4. Mode ready의 all-active 2,155 cycles는 A/B에서 측정한 1,626 cycle 증가와 같은 규모다.
5. Epoch, barrier, write-bus cycle은 서로 중복될 수 있고 bank-state와도 중복될 수 있으므로 합산하면 안 된다.

## 6. 현재 설계 판단

현재 증거에서는 broadcast queue나 PCU compute busy보다 DRAM bank 상태와 operand staging 정렬이 더 큰 병목 후보다. Logic-die PIM을 추가해도 weight/activation 준비와 bank-side 연산이 기존 ACT/PRE/row 상태에 강하게 묶이면 logic PCU의 병렬성이 전체 cycle로 이어지지 않는다.

따라서 다음 설계 후보는 다음 순서로 검토한다.

1. Logic-die shared buffer fill/read를 bank execution row 상태와 분리
2. Operand staging 전용 transaction/command queue
3. Epoch barrier 범위를 전체 channel에서 실제 참여 channel 집합으로 축소
4. Write data bus와 logic-control/output network의 물리적 분리 여부 모델링

## 7. 아직 확정할 수 없는 것

Bank-state와 predicate의 교집합을 아직 직접 저장하지 않았기 때문에 bank-state 219,645 cycles 전부가 독립적인 손실이라고 주장할 수 없다. 같은 cycle에 발행 가능한 packet이 epoch mismatch로 거절되고 다른 packet이 bank-state에서 거절됐을 수 있다.

## 8. 다음 구현

다음 global 교집합을 직접 계측한다.

- Bank-state all-active이면서 hierarchy predicate가 하나도 없는 cycle
- Bank-state all-active과 epoch/barrier/write-bus가 공존한 cycle
- Issuability 실패가 없고 hierarchy predicate만 존재한 cycle
- Rank mode만 제거하면 발행 후보가 생기는 exclusive mode cycle

이 exclusive blocker 결과를 기준으로 첫 architecture 변경 실험을 선택한다.

## 9. 결론

Hierarchy predicate도 global stall을 만들지만 개별 규모는 bank-state 공존 cycle보다 훨씬 작다. 현재 가장 유력한 다음 설계 영역은 logic-die operand staging과 DRAM bank-state의 결합이며, 교집합 계측으로 이를 최종 확인한다.
