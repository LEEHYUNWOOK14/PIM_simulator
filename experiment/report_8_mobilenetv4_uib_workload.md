# 8차 실험 보고서: MobileNetV4 Conv-S UIB workload 연결

## 1. 목적

MobileNetV4의 실제 블록 shape를 현재 PIM 커널 입력으로 변환하고, bank-side와 logic-die가 함께 사용되는 계층형 실행 경로를 확인한다.

## 2. 모델 구조 출처

- MobileNetV4 논문: https://arxiv.org/abs/2404.10518
- TensorFlow Model Garden 공식 block spec: https://github.com/tensorflow/models/blob/master/official/vision/modeling/backbones/mobilenet.py
- 사용한 spec: `MNV4ConvSmall_BLOCK_SPECS`

공식 spec에서 28px stage 뒤의 첫 UIB는 start depthwise 5x5, middle depthwise 5x5 downsampling, stride 2, output channel 96, expand ratio 3.0으로 정의된다. 이어지는 IB는 middle depthwise 3x3, stride 1, output channel 96, expand ratio 2.0이다.

연산의 bank-side/logic-die 배치는 공식 MobileNetV4 설계가 아니라 본 프로젝트의 설계 해석이다.

## 3. 추가된 workload 형식

입력 manifest:

```text
data/mobilenetv4/conv_small_uib14.csv
```

주요 필드는 layer 이름, block, op, 높이, 너비, 입출력 channel, kernel, stride, placement, source다.

lowering 규칙은 다음과 같다.

| 원본 연산 | 시뮬레이터 표현 | 상태 |
|---|---|---|
| 1x1 pointwise convolution | 공간 위치마다 GEMV | 실행 가능 |
| Residual Add | 64채널 PIM granularity로 padding한 ADD | 실행 가능 |
| ReLU | 64채널 PIM granularity로 padding한 ReLU | 실행 가능 |
| Depthwise convolution | tap별 bank-side MUL 후 ADD 누산 | 기능 baseline 실행 가능 |

depthwise를 dense GEMV로 바꾸지 않고, 미리 정렬된 tap plane을 기존 bank-side `MUL + ADD`로 처리한다. 3x3은 9회 MUL과 8회 ADD가 필요하며 tap 사이의 CRF/mode 경계를 보장하기 위해 각 단계를 완료한 뒤 다음 tap을 실행한다.

현재 64채널 GEMV의 물리 타일은 입력 128 elements, 출력 4096 channels 단위다. 따라서 논리 `192x64` pointwise는 안전한 메모리 접근을 위해 물리 `4096x128` weight tile로 zero-padding한다.

## 4. 실행 명령

```bash
bash experiment/run_mobilenetv4_workload_checks.sh
```

스크립트는 bank-only, logic-only, hybrid 설정을 순서대로 적용하고 종료 시 원래 설정 파일을 복원한다.

## 5. 실행 결과

| 모드 | Layer | 실행 위치 | Cycle | 결과 |
|---|---|---|---:|---|
| bank-only | `uib14_extra_expand`, GEMV 192x64 | bank-side | 2,618 | 통과 |
| bank-only | `uib14_ib_relu`, 18,816 elements | bank-side | 892 | 통과 |
| bank-only | `uib14_ib_middle_dw`, 3x3 depthwise | bank-side | 19,109 | 전체 출력 정확도 통과 |
| logic-only | `uib14_extra_expand`, GEMV 192x64 | logic-die | 2,766 | 통과 |
| hybrid | `uib14_extra_expand`, GEMV 192x64 | logic-die | 2,766 | 통과 |
| hybrid | `uib14_ib_relu`, 18,816 elements | bank-side | 892 | 통과 |
| hybrid | `uib14_ib_middle_dw`, 3x3 depthwise | bank-side | 19,109 | 전체 출력 정확도 통과 |

logic-die/hybrid 조건은 `NUM_LOGIC_PIM_UNITS=8`, `LOGIC_PIM_LATENCY=2`, `LOGIC_PIM_BW=64 byte/cycle`을 사용했다.

## 6. 출력 해석

```text
MOBILENETV4_LAYER_RESULT name[uib14_extra_expand]
kernel[GEMV] input_dim[64] output_dim[192]
padded_input_dim[128] padded_output_dim[4096]
spatial_invocations[784] single_invocation_cycle[2766]
```

- `input_dim[64]`, `output_dim[192]`: expand ratio 3.0을 적용한 pointwise projection이다.
- `padded_input_dim[128]`, `padded_output_dim[4096]`: 현재 64채널 GEMV 하드웨어 mapping에 필요한 물리 tile이다.
- `spatial_invocations[784]`: 28x28 공간 위치 각각에서 같은 GEMV가 필요하다는 뜻이다.
- `single_invocation_cycle`: 한 위치에 대한 smoke 실행 cycle이다. 784를 단순 곱한 값은 전체 layer의 정확한 cycle로 사용하지 않는다.

```text
MOBILENETV4_LAYER_RESULT name[uib14_ib_relu]
logical_elements[18816] padded_elements[131072] cycle[892]
```

- 논리 tensor는 `14x14x96 = 18,816 elements`다.
- 현재 64채널 PIM element-wise 실행 단위는 `131,072 elements`이므로 padding이 발생한다.
- 이 차이는 작은 MobileNet tensor에서 현재 고정 64채널 mapping의 활용률이 낮을 수 있음을 보여준다.

## 7. 검증된 사실과 미검증 항목

검증 완료:

- 공식 Conv-S UIB shape를 manifest로 읽을 수 있다.
- pointwise를 GEMV shape와 공간 반복 수로 변환할 수 있다.
- ReLU의 논리 크기와 물리 padding 크기를 구분할 수 있다.
- hybrid에서 pointwise MAC은 logic-die로, ReLU는 bank-side로 분리된다.

아직 미검증:

- 실제 image tensor에서 tap plane을 생성하는 bank-local halo/shift layout
- 공간 위치 784개를 포함한 전체 layer cycle
- UIB 전체 연산 사이의 tensor residency와 중간 데이터 이동량
- padding을 줄이는 channel/tensor mapping

## 8. 다음 기술 작업

다음 작업은 실제 image tensor에서 tap plane을 만드는 halo/shift data layout을 구현하는 것이다. 이후 UIB 한 블록을 `logic pointwise -> bank depthwise -> logic projection -> bank residual/activation` 순서로 연결하고, 단계 사이의 이동 byte를 계측해야 한다.
