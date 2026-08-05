# 57차 실험 보고서: 실행 문맥 분리와 출력 버퍼 통합

## 1. 목적

bank-side PIM과 logic-die PIM의 source queue를 분리할 때 PC, jump/repeat counter, PIM mode,
CRF, GRF가 서로 오염되지 않는지 확인한다. 동시에 56차의 실제 READ 완료 출력 버퍼와 유한
downstream drain 모델을 켜 전체 MobileNetV4 UIB에서 두 기능의 통합 동작을 검증한다.

## 2. 현재 분리된 실행 상태

| 위치 | Bank / Logic 분리 상태 |
|---|---|
| `PIMRank::PIMExecutionContext` | PC, jump/repeat 위치와 잔여 횟수, PIM mode, toggle, CRF exit 분리 |
| `crf`, `logicCrf` | 명령 프로그램 분리 |
| `pimBlocks`, `logicPimBlocks` | GRF/SRF와 연산 상태 분리 |
| `Rank::mode_`, `logicMode_` | HAB/SB/HAB_PIM mode 분리 |
| mode-register 진입 상태 | ABMR/SBMR 진행 상태 분리 |
| command packet | `LOGIC_DOMAIN_` tag로 실행 문맥 선택 |

## 3. 마이크로 실험

```bash
bash experiment/run_hierarchy_shared_drain.sh
HIERARCHY_SOURCE_QUEUES=true \
RESULT_FILE=experiment/results/hierarchy_shared_drain_source_queues_on.csv \
bash experiment/run_hierarchy_shared_drain.sh
```

| Source queue | 출력 검사 | Drain cycle | Bank issue | Logic issue | 겹치는 실행 창 |
|---|---:|---:|---:|---:|---:|
| OFF | 12 PASS | 1,942 | 2,048 | 288 | 0 |
| ON | 12 PASS | 1,425 | 2,048 | 288 | 57 cycles |

Source queue ON에서도 logic issue가 0으로 사라지지 않고 출력 12개가 모두 맞았다. 두 계층의
실행 문맥 분리가 마이크로 workload에서 기능적으로 동작하며, drain 시간은 517 cycles 감소했다.

## 4. 전체 UIB 실험 조건

두 실험은 `HIERARCHY_SOURCE_QUEUES`만 다르고 다음 조건은 동일하다.

```text
HIERARCHY_READY_BYPASS=true
LOGIC_EPOCH_RELEASE=true
LOGIC_ONLINE_QUEUE_BACKPRESSURE=true
LOGIC_BROADCAST_QUEUE_DEPTH=128
LOGIC_OUTPUT_BUFFER_ENABLE=true
LOGIC_OUTPUT_BUFFER_ENTRIES=2
LOGIC_OUTPUT_DRAIN_LATENCY=4
LOGIC_OUTPUT_DRAIN_BW=8
```

재현할 때는 `experiment/run_shared_weight_fill_channel_sweep.sh`에 다음 환경변수를 전달한다.
이 스크립트가 환경변수를 읽어 INI를 수정하고 종료 시 복원한다. `./sim` 앞에 환경변수만 붙이는
방식으로는 설정이 적용되지 않는다.

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

대조군은 위 명령의 `HIERARCHY_SOURCE_QUEUES=true`만 `false`로 바꾼다.

## 5. 전체 UIB 결과

| 항목 | Source OFF | Source ON | 변화 |
|---|---:|---:|---:|
| 출력 검사 | 18,816 PASS | 18,816 PASS | 정확도 유지 |
| Expand | 88,314 | 88,299 | -15 |
| Depthwise | 20,702 | 37,407 | +16,705 |
| Project | 103,396 | 103,385 | -11 |
| ADD | 1,662 | 3,750 | +2,088 |
| ReLU/read | 873 | 715 | -158 |
| 출력 버퍼 예약/퇴출 | 392/392 | 392/392 | 동일 |
| 출력 버퍼 포화 wall-cycle | 30,432 | 31,661 | +1,229 |
| 총 cycle | 214,947 | 233,556 | +18,609 (+8.66%) |

Source ON은 release mask `2 complete / 0 incomplete`, 출력 buffer peak 2, drain busy 8,624
cycles를 만족했다. 따라서 source context와 READ completion output path가 함께 동작한다.

## 6. 병목 진단

마이크로 실험에서는 source queue 분리가 overlap을 만들지만 전체 UIB에서는 8.66% 느려졌다.
증가분의 대부분은 Depthwise와 ADD 구간이다. Source ON에서 다음 write-completion barrier가 실제로
활성화되기 때문이다.

| Barrier 종류 | 완료 횟수 |
|---|---:|
| Ordered data | 784 |
| PIM mode | 1,568 |
| PIM control | 392 |
| PIM writeback | 392 |

이는 실행 문맥 분리 실패가 아니다. 계층별 queue가 독립적으로 진행할 때 데이터와 mode/control
명령의 선후 관계를 지키기 위해 삽입한 barrier 비용이다. 따라서 다음 최적화 대상은 context가
아니라 barrier 범위와 dependency token의 세분화다.

## 7. 다음 구현

1. 위치별 barrier 3,136회를 layer/tile dependency token으로 합칠 수 있는지 추적한다.
2. mode/control barrier와 실제 DATA write completion의 중복 대기를 분리한다.
3. Depthwise 16,705-cycle 증가분을 위치별 ordered/mode/control/writeback 대기로 분해한다.
4. 정확도와 epoch 순서를 유지한 상태에서 barrier coalescing을 실험한다.

