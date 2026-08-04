# 12차 기술 구현 보고서: 실제 MobileNetV4 UIB Shape 검증

## 1. 목적

MobileNetV4 Conv-S의 실제 IB shape인 `14×14×96→192→96`을 사용해 다음 계층형 연산을 하나의 수치 경로로 검증한다.

```text
logic-die pointwise expand
→ bank-side 3×3 depthwise
→ logic-die pointwise project
→ bank-side residual add
→ bank-side ReLU
```

축소 예제가 아니라 실제 spatial/channel 크기를 사용하며, 최종 18,816개 FP16 출력을 CPU 기대값과 비교한다.

## 2. Batch Pointwise 구현

기존 방식은 14×14의 196개 위치마다 GEMV를 별도로 초기화했다. 새 `executePointwiseBatchAndRead()`는 다음 방식으로 처리한다.

1. pointwise weight를 한 번 적재한다.
2. 196개 NHWC 위치를 GEMV batch 입력으로 패킹한다.
3. PIM mode와 CRF를 한 번 설정하고 batch 전체를 실행한다.
4. batch `b`의 결과는 기본 output column에서 `b×8`만큼 떨어진 위치에서 읽는다.
5. 각 batch의 output-channel mapping은 같은 channel·bank·PIM-block 순서로 다시 시작한다.

논리 출력 channel이 8의 배수가 아니어도 `readResult()`는 GRF 8개 단위로 접근한다. 따라서 물리 read buffer는 `ceil(logical_output/8)×8`개로 할당하고 논리 출력만 반환한다. 이 보정 전에는 3-output 테스트에서 8개 read pointer를 3개 buffer에 기록해 memory-controller transaction 오류가 발생했다.

## 3. 실제 Shape Pointwise 검증

IB expand 조건:

```text
positions: 14×14 = 196
logical input: 96
logical output: 192
physical input: 128
physical output: 4096
```

입력과 논리 weight를 모두 1로 설정했으므로 모든 출력의 CPU 기대값은 96이다. 총 `196×192=37,632`개 출력을 검사했고 모두 일치했다.

```text
MOBILENETV4_BATCH_POINTWISE_RESULT
name[uib14_ib_expand]
positions[196] input_channels[96] output_channels[192]
outputs_checked[37632]
```

측정 cycle:

| 모드 | Cycle | 정확도 |
|---|---:|---|
| bank-only | 120,164 | 37,632/37,632 |
| logic-only | 150,998 | 37,632/37,632 |
| hybrid의 logic pointwise | 150,998 | 37,632/37,632 |

기존 단일 위치 smoke cycle `2,618`을 196번 단순 곱하면 `513,128 cycle`이다. batch 경로의 `120,164 cycle`은 weight 적재와 mode 전환을 공유해 이 단순 반복 추정보다 약 4.27배 작다. 두 값의 실행 구조가 다르므로 이것은 batch 최적화 효과를 설명하는 참고 비교이며 독립적인 하드웨어 speed-up 비교는 아니다.

## 4. 실제 UIB 정확도 입력

overflow 없이 channel 연결과 공간 경계를 모두 검증하도록 다음 deterministic weight를 사용했다.

- 입력 `14×14×96`: 모두 1
- expand `96→192`: output `o`가 input `o mod 96` 하나만 선택
- depthwise 3×3: 모든 channel과 tap의 weight가 1
- project `192→96`: output `o`가 expanded channel `o` 하나만 선택
- residual: 원래 입력 1을 더함
- ReLU: 모든 결과가 양수이므로 값 유지

최종 위치별 기대값:

| 공간 위치 | 유효 depthwise 입력 | Residual 후 값 |
|---|---:|---:|
| 네 모서리 | 4 | 5 |
| 모서리를 제외한 테두리 | 6 | 7 |
| 내부 | 9 | 10 |

96개 channel 전체에서 이 패턴을 검사해 최종 `14×14×96=18,816`개 출력이 모두 일치했다.

## 5. 계층 전송량

hybrid에서만 다음 전송을 계측한다.

| 전환 | Byte |
|---|---:|
| bank→logic expand 입력, 14×14×96 FP16 | 37,632 |
| logic→bank depthwise 입력, 14×14×192 FP16 | 75,264 |
| bank→logic project 입력, 14×14×192 FP16 | 75,264 |
| logic→bank residual 입력, 14×14×96 FP16 | 37,632 |
| 합계 | 225,792 |

64 B/cycle 가정에서 총 3,528 cycle이다. bank-only baseline은 logic die를 사용하지 않으므로 전송 횟수·byte·cycle이 모두 0이다.

## 6. Bank와 Hybrid 비교

실험 설정:

```text
NUM_LOGIC_PIM_UNITS=8
LOGIC_PIM_LATENCY=2
LOGIC_PIM_BW=64 byte/cycle
hierarchy interconnect bandwidth=64 byte/cycle
```

결과:

| 모드 | 최종 출력 검사 | 계층 전송 | 총 Cycle |
|---|---:|---:|---:|
| bank-only | 18,816/18,816 | 0 B, 0 cycle | 346,600 |
| hybrid | 18,816/18,816 | 225,792 B, 3,528 cycle | 436,861 |

현재 가정에서 hybrid는 bank-only보다 약 26.0% 느리고, bank-only/hybrid 속도비는 약 0.793이다. 즉 기능적으로는 계층형 실행이 정확하지만 현재 자원·mapping으로는 성능 이득이 없다.

## 7. 병목 해석

현재 물리 tile 대비 논리 연산 활용률은 다음과 같다.

| 연산 | 논리 크기 | 물리 크기 | 활용률 |
|---|---:|---:|---:|
| expand GEMV | 192×96 | 4096×128 | 약 3.52% |
| project GEMV | 96×192 | 4096×256 | 약 1.76% |
| depthwise elementwise plane | 37,632 | 131,072 | 약 28.71% |
| residual/ReLU | 18,816 | 131,072 | 약 14.36% |

logic die가 느린 가장 큰 이유는 실제 MobileNetV4 channel 수에 비해 현재 GEMV output tile 4096이 지나치게 크고, logic command마다 설정한 service latency와 내부 burst transfer 비용이 추가되기 때문이다. 계층 전송 3,528 cycle만 제거해도 전체 90,261-cycle 차이를 설명할 수 없으므로 핵심 병목은 logic MAC 경로와 낮은 tile 활용률이다.

## 8. 재현 방법

실제 shape의 bank/hybrid 비교는 약 2분이 걸린다.

```bash
bash experiment/run_actual_uib_checks.sh
```

빠른 기본 연산·모드 검증:

```bash
bash experiment/run_mobilenetv4_workload_checks.sh
```

전체 회귀:

```bash
./sim --gtest_filter='PIMKernelFixture.add:PIMKernelFixture.relu:PIMKernelFixture.mul:PIMKernelFixture.gemv:PIMKernelFixture.gemv_tree:MobileNetV4WorkloadTest.*'
```

전체 회귀 결과:

```text
[==========] 21 tests from 2 test suites ran.
[  PASSED  ] 21 tests.
```

## 9. 다음 실험

다음 기술 작업은 logic 자원과 mapping을 바꾸는 sweep이다.

1. `NUM_LOGIC_PIM_UNITS`, `LOGIC_PIM_LATENCY`, `LOGIC_PIM_BW`를 변화시킨다.
2. hierarchy bandwidth를 별도 변화시킨다.
3. output tile을 4096 그대로 사용하는 baseline과 96/192 channel에 맞춘 compact mapping 모델을 비교한다.
4. 전체 tensor 전송과 bank partial-sum 전송을 비교한다.
5. 어떤 조건에서 hybrid cycle이 bank-only 346,600보다 작아지는지 crossover point를 찾는다.

compact mapping과 partial-sum protocol의 구조 정의는 연구자의 설계 선택이며, simulator sweep·검증·결과 수집은 기술 구현 영역이다.
