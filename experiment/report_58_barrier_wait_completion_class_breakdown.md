# 58차 실험 보고서: Barrier 대기 completion class 분해

## 1. 목적

Source queue ON 전체 UIB의 18,609-cycle 증가 원인을 찾기 위해 barrier 개수뿐 아니라 실제
명령 발행 거절량을 completion class별로 분해한다. 안전한 coalescing 후보를 선택하기 위한
관측 단계이며, 이번 변경은 스케줄링 순서나 barrier 동작을 바꾸지 않는다.

## 2. 두 종류의 대기

| 카운터 | 의미 |
|---|---|
| `barrier_wait_*` | 현재 epoch의 barrier transaction이 같은 epoch의 이전 transaction 완료를 기다린 거절 횟수 |
| `epoch_wait_*` | 다음 epoch transaction이 이전 barrier 완료 및 epoch 증가를 기다린 거절 횟수 |

각 MemoryController에서 epoch를 만들 때 barrier가 된 마지막 transaction의
`WriteCompletionClass`를 저장한다. 다음 epoch가 막히면 현재 미완료 epoch의 barrier class에
거절을 귀속한다.

이 값은 command candidate probe 횟수의 영향을 받는 channel-level 거절량이다. 총 cycle에
직접 더하는 wall-time은 아니지만 동일 실행 안에서 병목 비율을 비교할 수 있다.

## 3. 재현 명령

```bash
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
RAW_FILL_CHANNELS=32 FILL_POLICY=row_interleaved \
BUFFER_WRITE_PORTS=0 BUFFER_WRITE_LATENCY=1 \
EPOCH_RELEASE=true ONLINE_QUEUE_BACKPRESSURE=true \
BROADCAST_QUEUE_DEPTH=128 HIERARCHY_READY_BYPASS=true \
HIERARCHY_SOURCE_QUEUES=true \
OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 정확도와 구조 검증

| 항목 | 결과 |
|---|---:|
| MobileNetV4 출력 | 18,816 PASS |
| Release masks | 2 complete / 0 incomplete |
| 출력 buffer 예약/퇴출 | 392 / 392 |
| 출력 buffer peak | 2 |
| 총 cycle | 233,556 |

## 5. 결과

| Completion class | Barrier 완료 | Barrier 자체 대기 | 다음 epoch 대기 | 합계 | 합계 비율 |
|---|---:|---:|---:|---:|---:|
| Ordered | 784 | 826,703 | 12,365,830 | 13,192,533 | 91.05% |
| PIM mode | 1,568 | 74,558 | 539,691 | 614,249 | 4.24% |
| PIM control | 392 | 0 | 108,135 | 108,135 | 0.75% |
| PIM writeback | 392 | 336,329 | 237,824 | 574,153 | 3.96% |
| 합계 | 3,136 | 1,237,590 | 13,251,480 | 14,489,070 | 100% |

분류 합계는 기존 `barrier_outstanding_rejects[1237590]` 및
`epoch_mismatch_rejects[13251480]`과 정확히 일치한다.

## 6. 해석

Barrier 횟수만 보면 PIM mode가 1,568회로 가장 많지만 실제 거절량은 전체의 4.24%다.
Ordered barrier는 784회뿐이지만 전체 거절량의 91.05%를 차지한다. 따라서 mode 전환을 먼저
coalescing하는 전략은 구현 위험에 비해 기대 효과가 작다.

Ordered class에는 다음과 같은 서로 다른 의존성이 섞여 있다.

1. `BANK_TO_GRF` 입력 read 완료 후 연산 명령
2. 두 번째 operand read 완료 후 ADD/MUL
3. `MAC_` 명령 반복 사이의 GRF input 교체
4. `PARK_IN/PARK_OUT` mode-register 접근 순서
5. 결과 readback 전에 writeback 완료를 보장하는 경계

이 의존성을 모두 한꺼번에 제거하면 정확도가 깨질 가능성이 높다. 다음에는 ordered barrier의
마지막 transaction tag를 기준으로 거절량을 세분화해야 한다.

## 7. 다음 단계

1. Ordered barrier를 `BANK_TO_GRF`, `ADD/MUL`, `MAC`, `PARK`, `OTHER`로 분류한다.
2. 각 tag의 barrier 자체/다음 epoch 거절량과 해당 stage를 연결한다.
3. 서로 다른 bank·channel에 있어 독립적인 barrier만 선택적으로 합친다.
4. 마이크로 정확도, 전체 UIB 18,816 출력, epoch complete mask를 모두 통과해야 coalescing을 유지한다.

## 8. 연산 tag 1차 분류

Barrier가 붙은 transaction tag를 `PARK`, `OPERAND_LOAD`, `ALU`, `MAC`, `OUTPUT`, `OTHER`로
분류했다. Pending queue에서 만들어진 barrier도 MemoryController 진입 시 epoch 메타데이터를
등록하도록 보완했다. 이 변경 전에는 pending barrier 정보가 누락되어 다음 epoch 대기가
부정확하게 `OTHER`로 귀속됐다.

| Tag class | Barrier 자체 대기 | 다음 epoch 대기 | 합계 | 비율 |
|---|---:|---:|---:|---:|
| PARK | 0 | 1,086,424 | 1,086,424 | 7.50% |
| Operand load | 174,620 | 1,025,396 | 1,200,016 | 8.28% |
| ALU | 154,496 | 182,528 | 337,024 | 2.33% |
| MAC | 308,358 | 1,322,391 | 1,630,749 | 11.25% |
| Output/writeback | 107,437 | 2,640,096 | 2,747,533 | 18.96% |
| Other | 492,679 | 6,994,645 | 7,487,324 | 51.68% |
| 합계 | 1,237,590 | 13,251,480 | 14,489,070 | 100% |

전체 정확도와 `total_cycle[233556]`은 계측 전후 동일하다. 다만 `OTHER`가 51.68%이므로 지금
특정 barrier를 제거하면 근거가 부족하다. `OTHER`에는 mode/control tag뿐 아니라 operation
이름이 비어 있는 ordered transaction이 포함될 수 있다. 다음 계측에서는 sequence/epoch suffix를
제거한 raw barrier operation tag를 집계해 `OTHER`를 실제 호출 지점까지 분해해야 한다.
