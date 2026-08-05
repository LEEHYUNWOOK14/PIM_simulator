# 59차 실험 보고서: Raw barrier dependency 진단

## 1. 목적

58차 연산군 분류에서 `OTHER`가 51.68%였던 원인을 실제 operation tag까지 분해한다. Barrier를
무작정 제거하지 않고 데이터 의존 경계와 제어 경계를 구분해 다음 구조 변경 대상을 결정한다.

## 2. 구현

Barrier tag에서 다음 메타데이터를 제거한 operation 이름을 epoch별로 저장했다.

```text
LOGIC_DOMAIN_ / BANK_DOMAIN_
LOGIC_SEQ_n / BANK_SEQ_n
LOGIC_EPOCH_n / BANK_EPOCH_n
BAR
```

64개 MemoryController의 raw-tag map을 `PIMKernel`에서 합산해 전체 UIB 결과 행에 출력한다.

또한 `preloadNoReplacement()`의 tag 없는 write를 `PRELOAD_DATA`로 명명했다. 주소, 데이터,
source domain과 ordering은 바뀌지 않는다.

## 3. Barrier 대상 선택 점검

기존 `MemorySystem::addBarrier()`는 pending queue가 존재해도 controller에 빈 슬롯이 보이면
controller queue의 마지막 transaction에 barrier를 붙일 수 있었다. 논리적으로 더 최신인 pending
transaction이 있으면 항상 pending의 마지막 항목에 barrier를 붙이도록 수정했다.

이번 MobileNetV4 UIB에서는 수정 전후 정확도, 거절량, 총 233,556 cycles가 같았다. 따라서 이번
workload의 측정값에는 영향이 없었지만, controller slot이 barrier 호출 직전에 열리는 다른 trace의
ordering 오류를 예방한다.

## 4. 검증 조건

```text
HIERARCHY_SOURCE_QUEUES=true
LOGIC_OUTPUT_BUFFER_ENABLE=true
LOGIC_OUTPUT_BUFFER_ENTRIES=2
LOGIC_OUTPUT_DRAIN_LATENCY=4
LOGIC_OUTPUT_DRAIN_BW=8
```

| 항목 | 결과 |
|---|---:|
| MobileNetV4 출력 | 18,816 PASS |
| Barrier 자체 거절 합계 | 1,237,590 |
| 다음 epoch 거절 합계 | 13,251,480 |
| 총 cycle | 233,556 |

Raw tag 합계는 기존 총계와 정확히 일치하며 `EMPTY`와 `MISSING_METADATA`는 0이다.

## 5. 주요 결과

| Raw dependency | Barrier 자체 | 다음 epoch | 합계 | 의미 |
|---|---:|---:|---:|---|
| `PRELOAD_DATA` | 81,792 | 2,866,304 | 2,948,096 | Depthwise/ADD 입력 write 완료 대기 |
| `output` | 107,437 | 2,640,096 | 2,747,533 | Pointwise 결과 READ 완료 대기 |
| Mode 전환 3종 합계 | 74,558 | 2,922,921 | 2,997,479 | SB/HAB/HAB_PIM 전환 |
| `MAC` | 308,358 | 1,322,391 | 1,630,749 | GRF input과 MAC 실행 순서 |
| PARK IN/OUT 합계 | 0 | 1,086,424 | 1,086,424 | reserved-row mode 진입/해제 |
| `WRIO_TO_GRF` | 86,044 | 908,852 | 994,896 | Pointwise input upload 완료 |
| `GRFB_TO_BANK` | 85,001 | 604,856 | 689,857 | GEMV 결과 writeback |
| `GRF_TO_BANK` | 239,296 | 350,080 | 589,376 | Eltwise 결과 writeback |

Mode 전환 3종은 `END_HAB_TO_SB`, `END_SB_TO_HAB`, `PIM`을 합산했다.

## 6. 설계 판단

가장 큰 `PRELOAD_DATA`와 `output` 경계는 실제 producer-consumer 의존성이다. 이를 단순히
coalescing하거나 제거하면 다음 연산이 입력 write 또는 결과 readback보다 먼저 실행될 수 있다.

따라서 안전한 다음 후보는 다음 두 방향이다.

1. **Tile completion token:** 전체 preload/output epoch를 기다리지 않고 소비할 tile 범위가 완료된
   순간 해당 bank/logic 연산을 release한다.
2. **Mode residency:** 같은 logic pointwise 세션 동안 HAB 또는 HAB_PIM 상태를 유지해 위치마다
   반복되는 mode 전환을 줄인다.

Mode 전환 경계는 약 2.997M reject로 크지만, PC reset이 `HAB -> HAB_PIM` 전환에 결합되어 있다.
Mode write만 제거하면 position별 PC reset이 사라지므로 별도 `RESET_PC` token 또는 context reset
명령을 먼저 모델링해야 한다.

## 7. 다음 구현 순서

1. Logic execution context에 명시적 `resetProgramCounter()` 동작을 추가한다.
2. Position 사이에서 HAB residency를 유지하면서 PC만 reset하는 실험 설정을 만든다.
3. 기존 mode 전환과 resident mode를 A/B 비교한다.
4. 출력 18,816, release mask 완결, source queue 마이크로 정확도를 모두 통과한 뒤 유지한다.
5. 이후 preload/output 전체 barrier를 tile completion token으로 세분화한다.

