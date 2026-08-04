# 11차 기술 구현 보고서: 축소 UIB End-to-End 검증

## 1. 목적

이전 실험은 MobileNetV4 layer를 개별적으로 실행하고 계층 전환 비용을 계산했다. 이번 실험은 한 연산의 실제 출력값을 다음 연산 입력으로 넘겨, logic-die pointwise와 bank-side depthwise·residual·activation이 하나의 수치 연산 경로로 연결되는지 검증한다.

## 2. 축소 UIB 정의

시뮬레이션 시간을 줄이면서 경계 padding과 channel 변환을 모두 확인할 수 있도록 다음 블록을 사용했다.

```text
입력: 3×3×1 NHWC, 값 1~9
pointwise expand: 1→2 channel, weight [1, 2]
3×3 depthwise: 2 channel, 모든 weight 1, SAME padding
pointwise project: 2→1 channel, weight [1, 1]
residual add: project 결과 + 원본 입력
ReLU
```

연산 배치는 다음과 같다.

| 단계 | 위치 | 다음 단계 이동 |
|---|---|---|
| 입력 tensor | bank | bank→logic |
| pointwise expand | logic die | logic→bank |
| depthwise | bank side | bank→logic |
| pointwise project | logic die | logic→bank |
| residual add, ReLU | bank side | 없음 |

## 3. CPU Golden Model

`pointwiseReference()`는 NHWC 위치마다 output-channel-major weight matrix를 곱한다. depthwise 기준값은 기존 `depthwiseReference()`가 원본 좌표와 SAME padding을 직접 순회해 계산한다.

모든 depthwise weight가 1이므로 첫 channel의 3×3 합은 다음과 같다.

```text
12 21 16
27 45 33
24 39 28
```

expand의 두 번째 channel은 첫 channel의 2배이고 project에서 두 channel을 더하므로, project 결과는 위 값의 3배다. 원본 residual을 더한 최종 기대값은 다음과 같다.

```text
37 65 51
85 140 105
79 125 93
```

모든 값이 양수이므로 ReLU 후에도 동일하다. PIM readback의 9개 값이 이 결과와 전부 일치했다.

## 4. 새로 추가한 실행 연결

`PIMKernel::executePointwiseAndRead()`를 추가했다.

1. zero-padding된 GEMV weight와 입력을 적재한다.
2. GEMV를 실행한다.
3. 물리 출력 tile을 odd bank에서 읽는다.
4. 출력 channel별 `BurstType`의 FP16 partial sum을 reduction한다.
5. 논리 channel 수만 잘라 다음 NHWC tensor에 전달한다.

depthwise는 pointwise 출력으로 실제 tap plane을 만들고, 9 MUL과 8 ADD를 bank-side에서 수행한다. project 출력은 다시 padded ADD 입력으로 적재해 원본 residual과 더한 뒤 ReLU를 실행한다.

## 5. 발견하고 수정한 오류

### 5.1 Single-input-tile GEMV writeback

기존 MobileNetV4 pointwise smoke test는 cycle만 검사했기 때문에 출력값 오류를 발견하지 못했다. 입력이 물리 GEMV tile 하나일 때 최종 `GRFB_TO_BANK_` transaction이 아직 `MAC` command 상태에서 처리되면 column 0~7을 모두 `GRF_B[0]`으로 해석했다.

수정 후에는 command 종류보다 `GRFB_TO_BANK_` tag를 먼저 판별하고 다음과 같이 저장한다.

```text
column 0→GRF_B[0]
column 1→GRF_B[1]
...
column 7→GRF_B[7]
```

custom GEMV `[1,2,3]`과 세 output weight의 결과 `[1,2,6]`으로 검증했다. 기존 4096×1024 `gemv`와 `gemv_tree`도 계속 통과한다.

### 5.2 Hybrid register broadcast

hybrid 모드에서 WRIO 입력은 bank-side `GRF_A`에만 기록됐지만 MAC은 logic-side `GRF_A`를 읽고 있었다. 그 결과 logic pointwise 출력이 0이 되어 최종 결과가 residual 원본 `[1..9]`만 남았다.

수정 후 hybrid의 GRF/SRF broadcast와 GRF zeroize는 bank-side와 logic-die PIM block 모두에 적용된다. 실제 산술 명령은 기존 routing 정책에 따라 MAC은 logic die, MUL/ADD/ReLU는 bank side에서 실행된다.

## 6. 실행 방법

전체 모드 검증:

```bash
bash experiment/run_mobilenetv4_workload_checks.sh
```

현재 설정에서 축소 UIB만 실행:

```bash
./sim --gtest_filter='MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd'
```

전체 정확도 회귀:

```bash
./sim --gtest_filter='PIMKernelFixture.add:PIMKernelFixture.relu:PIMKernelFixture.mul:PIMKernelFixture.gemv:PIMKernelFixture.gemv_tree:MobileNetV4WorkloadTest.*'
```

## 7. 결과

bank-only 기준:

```text
MOBILENETV4_MINI_UIB_RESULT
elements[9] bank_side[1] logic_die[0]
transfer_bytes[0] transfer_cycles[0] total_cycle[66737]
```

hybrid 기준 (`NUM_LOGIC_PIM_UNITS=8`, `LOGIC_PIM_LATENCY=2`, `LOGIC_PIM_BW=64`):

```text
MOBILENETV4_MINI_UIB_RESULT
elements[9] bank_side[1] logic_die[1]
transfer_bytes[108] transfer_cycles[4] total_cycle[69631]
```

자동 모드 실험 결과:

```text
[1/4] workload/layout/accounting: 7 tests passed
[2/4] bank-only: 3 tests passed
[3/4] logic-only: 2 tests passed
[4/4] hybrid: 5 tests passed
```

전체 회귀 결과:

```text
[==========] 18 tests from 2 test suites ran.
[  PASSED  ] 18 tests.
```

축소 workload에서 hybrid가 bank-only보다 빠르지는 않다. 물리 tile이 4096×128로 고정되어 논리 1~2 channel 연산에도 큰 padding 비용이 발생하고, 현재 logic-die latency와 계층 전환 비용도 추가되기 때문이다. 이 결과는 기능 검증값이며 성능 우위를 주장하는 결과가 아니다.

## 8. 다음 작업

다음 단계는 같은 실행기를 MobileNetV4의 실제 `14×14×96→192→96` shape에 적용하되, 공간 위치 196개를 독립적으로 반복하는 방식의 실행 시간 문제를 해결하는 것이다. batch GEMV 또는 tensor-level pointwise 명령을 추가한 뒤 다음을 측정해야 한다.

- 전체 UIB cycle
- 유효 연산 대비 padded 연산 비율
- bank↔logic 실제 이동량
- 전체 tensor 전송과 partial-sum 전송의 차이
- logic PCU 수·latency·bandwidth 민감도
