# 42차 실험 보고서: Bank/logic co-pending drain과 독립 CRF

## 1. 실험 목적

Bank-side depthwise stage와 logic-die pointwise row를 동시에 pending 상태로 만들고 한 번의 simulator drain에서 처리한다. 이 보고서의 shared drain은 co-pending 기능 검증이며, 시간상 issue overlap 여부는 43차 보고서에서 별도로 계측한다.

## 2. Depthwise nonblocking stage

3×3 lowered depthwise는 다음 17개 의존 단계로 표현했다.

```text
MUL tap0,
MUL tap1, ADD tap1,
MUL tap2, ADD tap2,
...
MUL tap8, ADD tap8
```

새 API:

```cpp
auto handle = pim.beginDepthwiseLowered(...);
pim.enqueueDepthwiseStage(handle);

// 독립 logic-die transaction을 enqueue할 수 있는 구간

pim.waitDepthwiseStage(handle);
```

기존 `executeDepthwiseLowered`는 위 API를 17단계 모두 실행하는 blocking wrapper다.

## 3. 공동 drain에서 발견한 구조 결함

첫 구현에서는 bank depthwise가 CRF를 프로그램한 뒤 resident logic pointwise를 실행하자 logic 출력 12개가 모두 0이 됐다. 원인은 기존 simulator의 `PIMRank::crf`가 bank-side PIM과 logic-die PIM에 하나만 존재했기 때문이다.

이 결과는 단순 테스트 오류가 아니라 기존 simulator가 단일 PIM 계층을 전제로 했다는 직접 증거다. 설계 목표처럼 bank 인접 PCU와 logic-die PCU가 별도 하드웨어라면 CRF도 독립 상태여야 한다.

## 4. 수정 내용

- `PIMRank`에 `crf`와 `logicCrf`를 분리했다.
- Bank CRF program tag: `PROGRAM_BANK_CRF`
- Logic CRF program tag: `PROGRAM_LOGIC_CRF`
- Logic GEMV packet은 `MAC_`, `GRFB_TO_BANK_`, `RESET_GRF_B` 태그로 logic CRF를 decode한다.
- Bank MUL/ADD packet은 기존 bank CRF를 decode한다.
- Logic PCU와 bank PCU의 GRF/SRF 분리에 이어 command state도 분리됐다.

## 5. 재현 명령

```bash
bash experiment/run_hierarchy_shared_drain.sh
```

결과 CSV:

```text
experiment/results/hierarchy_shared_drain.csv
```

## 6. 결과

```text
bank_stages_enqueued  bank_stages_completed  logic_rows_enqueued  logic_outputs_checked  shared_drain_cycles  pending_after_drain
1                     1                      1                    12                     1942                 0
```

| 항목 | 결과 |
|---|---:|
| 동시에 pending한 bank stage | 1 |
| 동시에 pending한 logic row | 1 |
| 공동 drain 후 완료된 bank stage | 1 |
| 검증한 logic 출력 | 12개, 모두 통과 |
| 공동 drain 구간 | 1,942 cycle |
| drain 후 pending transaction | 0 |

이번 1,942 cycle은 co-pending drain 구간의 측정값이며 순차 대조군과의 speedup이 아니다. 후속 issue 계측에서는 bank와 logic window의 교집합이 0 cycle로 확인됐다.

## 7. 회귀 결과

- Depthwise layout/stride/bank simulator 테스트 4개 통과
- 전체 MobileNetV4 UIB 출력 18,816개 통과
- 전체 UIB 기존 cycle 214,228 유지
- Logic weight-buffer read miss 0 유지
- Logic release incomplete mask 0 유지

## 8. Packet-domain-aware ready probe

최초 공동 drain 구현 직후에는 `peekNextExecutableCommand`가 항상 bank CRF를 읽었다. 이를 packet tag 기반으로 수정해 logic packet은 `logicCrf`, bank packet은 `crf`를 사용한다. 따라서 online queue backpressure의 side-effect-free probe와 실제 `doPIM` decode가 같은 명령을 본다. 수정 후 공동 drain의 12개 출력과 1,942 cycle은 유지됐다.

## 9. 현재 한계

Bank와 logic transaction은 같은 drain에 들어갔지만 source별 issue cycle을 아직 직접 기록하지 않는다. 또한 공동 실행한 bank 작업은 depthwise 첫 MUL stage 하나이며 전체 17 stage와 여러 output row를 wavefront로 연결하지 않았다.

## 10. 다음 구현

1. Drain 구간의 bank/logic first issue, last completion, 동시 active cycle을 계측한다.
2. 17개 depthwise stage를 line-buffer output row token과 연결한다.
3. 순차 대조군과 공동 drain의 cycle을 같은 입력에서 비교한다.
4. 실제 MobileNetV4 14×14 UIB 행 wavefront로 확장한다.
