# 28차 실험 보고서: Online Expected Mask와 Stream EOS

## 1. 목적

사후 trace를 보지 않고도 각 broadcast mask의 마지막 참여 channel을 판정한다. Spatial workload schedule과 pointwise CRF 반복 구조를 이용해 stream별 마지막 command ordinal을 실행 전에 등록한다.

## 2. Command 수 계산

현재 pointwise GEMV microkernel에서 FP16 burst 기준 input tile 수를 `N`이라고 한다.

```text
even-bank commands = 64 x ceil(N / 2)
odd-bank commands  = N/2가 0이면 8, 아니면 64 x floor(N / 2)
commands/position  = even + odd
```

MobileNetV4 UIB:

| 계층 | Input tiles | Commands/position | Position-channel 실행 수 | 총 fanout |
|---|---:|---:|---:|---:|
| Expand 96→192 | 1 | 72 | 196×3=588 | 42,336 |
| Project 192→96 | 2 | 128 | 196×2=392 | 50,176 |

계산된 총 fanout은 실제 logic request와 일치한다.

## 3. Expected Mask 생성

각 spatial group이 담당하는 position 수를 계산한 후 다음 값을 epoch 시작 전에 등록한다.

```text
stream EOS ordinal = group position 수 x commands/position
expected mask(k)    = EOS ordinal이 k보다 큰 모든 stream
```

실제 command context의 stream-ID 집합이 expected channel mask와 정확히 같아지면 해당 queue entry를 즉시 완성 처리한다. 단순 fanout 크기 비교는 사용하지 않는다.

Stream ID는 simulator의 물리 rank stride와 동일하게 `channel * NUM_RANKS + rank`로 생성한다. 활성 rank 수를 stride로 사용하면 서로 다른 channel의 ID가 expected mask와 어긋난다.

## 4. 재실행 명령

```bash
DEPTH_LIST="64 128" \
RESULT_FILE=experiment/results/online_exact_mask_validation.csv \
bash experiment/run_broadcast_queue_depth_sweep.sh
```

## 5. 검증 결과

| 계층 | 사후 Trace peak | Online peak | Incomplete expected masks |
|---|---:|---:|---:|
| Expand | 1 | 1 | 0 |
| Project | 78 | 78 | 0 |

Online 판정과 사후 interval 분석이 두 epoch에서 완전히 일치했다. 따라서 EOS ordinal 계산과 expected fanout 생성이 현재 MobileNetV4 UIB 명령 구조를 정확히 표현한다.

## 6. Queue Depth 비교

| Depth | Online full 진입 | Trace-derived stall | Total cycle |
|---:|---:|---:|---:|
| 64 | 1 | 53 | 214,289 |
| 128 | 0 | 0 | 214,228 |

Depth 64에서는 project epoch가 한 번 full 상태에 진입한다. Depth 128에서는 online 및 trace 모델 모두 용량 초과가 없다.

모든 조건에서 다음 값이 유지됐다.

```text
outputs checked       = 18,816 / 18,816
broadcast fanout      = global requests = 92,512
dispatch/coalesced    = 1,616 / 90,896
weight-buffer misses  = 0
```

## 7. 현재 달성 범위

이번 구현으로 mask 완성 시점은 사후 trace가 아니라 실행 중 expected mask로 판정할 수 있다. 즉 workload scheduler와 broadcast coalescer 사이의 EOS metadata 경로가 simulator에 반영됐다.

다만 queue full 시 현재 command를 실제 MemoryController 입력에서 멈추는 ready/backpressure 배선은 아직 trace-derived stall 모델을 사용한다. Online completion과 online issue stall은 구분해야 한다.

## 8. 다음 단계

1. Scheduler에 `canAccept(context)` 또는 ready 신호를 추가한다.
2. 새 ordinal entry인데 queue가 full이면 PIM command issue를 보류한다.
3. 기존 mask를 완성하는 channel command는 full 상태에서도 허용해 deadlock을 방지한다.
4. 보류 명령을 재발행하고 실제 stall cycle을 계측한다.
5. Trace-derived stall과 online stall 결과를 비교한다.

이 ready/backpressure 연결은 `report_29_online_queue_backpressure.md`에서 완료하고 검증했다.
