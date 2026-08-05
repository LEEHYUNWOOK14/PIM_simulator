# 71차 실험 보고서: Speculative PRECHARGE 계측 정정

## 1. 발견한 문제

Bank-state raw tag histogram에서 `EMPTY`가 14,462,890 channel-cycles로 기존 bank-state blocked controller 합계와 정확히 같았다.

원인은 `CommandQueue::process_precharge()`가 실제 queued request가 없는 idle bank에도 합성 PRECHARGE packet을 만들어 `isIssuable()`을 시험하는 동작이었다. 이 packet은 스케줄러가 bank를 순회하기 위한 내부 probe이며 실제 workload command가 아니다.

## 2. 수정

Simulation scheduling 동작은 변경하지 않았다. 다음 조건에서만 PRECHARGE reject 통계를 기록하도록 수정했다.

```cpp
isIssuable(packet, !prechargeTag.empty())
```

`prechargeTag`가 비어 있으면 해당 bank를 요구하는 queued request가 없으므로 metric에서 제외한다. 실제 다른 row를 요구하는 packet이 있으면 tag가 전달되고 기존처럼 기록된다.

## 3. 회귀 검증

보정 후에도 다음 결과가 그대로 유지됐다.

- 출력 18,816개 PASS
- Total cycle 235,182
- Mode latency 32
- Modeled writes 220,342
- Fill completion 3,584

따라서 수정은 simulator 동작이 아니라 관측 지표만 바로잡았다.

## 4. 보정된 Global 결과

| 원인 | Any cycles | All-active cycles |
|---|---:|---:|
| Hierarchy union | 46,967 | 41,359 |
| Bank state | 43,348 | 37,685 |
| DRAM timing | 21,779 | 16,708 |
| Row mismatch | 9,969 | 9,854 |
| Rank mode | 3,171 | 2,155 |

## 5. 보정된 Exclusive 결과

| 지표 | Cycle |
|---|---:|
| Bank all, hierarchy 없음 | 1,420 |
| Bank all, hierarchy 공존 | 36,265 |
| Bank-state only | 0 |
| Hierarchy all, issuability 문제 없음 | 2,314 |
| Bank/hierarchy 모두 all-active | 36,265 |

기존 `bank_state_only=175229`는 완전히 사라졌다. 실제 bank-state all-active의 96.24%는 hierarchy blocker와 공존한다.

## 6. 보정된 Stage 결과

| Stage | Stage cycles | Bank-state only | Bank all-active | Hierarchy all-active |
|---|---:|---:|---:|---:|
| Expand | 88,345 | 0 | 3,605 | 3,849 |
| Depthwise | 38,884 | 0 | 27,559 | 30,173 |
| Project | 103,431 | 0 | 3,117 | 3,800 |
| Add | 3,715 | 0 | 2,955 | 3,106 |
| ReLU/readback | 807 | 0 | 449 | 431 |

Hierarchy all-active의 약 72.95%가 depthwise stage에 집중된다. Pointwise expand/project는 cycle이 길지만 all-active blocker가 각각 3,849/3,800 cycles에 불과해 주로 command throughput과 logic service work가 실행시간을 결정한다.

## 7. Direct staging 실험 재해석

Direct staging의 다음 결과는 여전히 유효하다.

- Fill ACT 1,120 -> 0
- Fill completion 3,584 유지
- Total cycle 235,182 -> 235,130
- 출력 18,816개 PASS

다만 direct staging을 선택한 근거였던 bank-state-only 병목은 계측 오류였다. 52-cycle 개선은 실제 기능 효과지만 architecture 우선순위의 중심 근거로 사용할 정도로 크지 않다. 기능은 기본 OFF인 선택적 실험 옵션으로 유지한다.

## 8. 새 우선순위

1. Depthwise의 epoch/barrier/write-bus all-active 교집합 분해
2. Pointwise는 blocker 제거보다 command throughput과 logic service/dispatch 구조 분석
3. Add/ReLU는 전체 비중이 작으므로 후순위
4. Direct staging은 RTL 선택 옵션으로 유지하되 주 성능 주장에서는 제외

## 9. 결론

기존 대규모 bank-state-only 병목은 simulator 내부 speculative PRECHARGE probe가 만든 계측 오염이었다. 보정 후 실제 global 병목은 hierarchy predicate와 bank-state의 공존이며, stage 기준으로는 depthwise가 가장 큰 all-active 정지 구간을 만든다.
