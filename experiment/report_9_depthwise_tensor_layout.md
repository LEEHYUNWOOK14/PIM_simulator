# 9차 기술 구현 보고서: 실제 Depthwise 텐서 배치

## 1. 목표

MobileNetV4 depthwise convolution을 단순히 모든 입력과 가중치가 1인 경우로만 확인하지 않고, 실제 NHWC 영상 텐서의 공간 위치와 경계 패딩을 bank-side PIM 입력으로 변환하여 검증한다.

## 2. 구현 내용

`MobileNetV4Workload::makeDepthwiseTapLayout()`을 추가했다. 입력은 NHWC 순서이며, 다음 절차로 변환한다.

1. 출력 높이와 너비를 `ceil(input / stride)`로 계산한다.
2. TensorFlow의 `SAME` 방식에 맞춰 위쪽과 왼쪽 padding을 계산한다.
3. 각 kernel tap마다 출력 위치 수만큼의 input tap plane을 만든다.
4. 영상 바깥을 참조하는 위치에는 0을 넣는다.
5. `kernel x kernel x channel` 가중치를 각 출력 공간 위치에 반복 배치한다.
6. 생성된 각 tap plane을 기존 bank-side `MUL + ADD` 명령에 전달한다.

CPU 기준 계산 함수 `depthwiseReference()`도 별도로 추가했다. 이 함수는 tap plane을 누산하지 않고 원본 NHWC 좌표를 직접 순회하므로, 변환 코드와 같은 오류를 공유하지 않도록 했다.

## 3. 검증 항목

| 테스트 | 확인 내용 | 결과 |
|---|---|---|
| `DepthwiseSamePaddingTapLayout` | 3x3 입력, 3x3 kernel, stride 1의 네 모서리와 중앙 | 통과 |
| `DepthwiseSamePaddingStrideTwo` | 4x4 입력에서 비대칭 SAME padding과 stride 2 | 통과 |
| `DepthwiseTapLayoutRunsOnBankSidePim` | 실제 tap plane 적재, 9 MUL, 8 ADD, readback, CPU 결과 비교 | 통과 |
| 기존 PIM 및 MobileNetV4 회귀 테스트 | 기존 기능의 회귀 여부 | 13/13 통과 |

3x3 입력이 1부터 9이고 모든 kernel 가중치가 1일 때 stride 1 출력은 다음과 같다.

```text
12 21 16
27 45 33
24 39 28
```

가장자리 값이 중앙보다 작은 이유는 `SAME` padding으로 영상 바깥의 입력이 0이기 때문이다.

## 4. 재현 명령

WSL 터미널에서 저장소 루트로 이동한 뒤 실행한다.

```bash
scons -j4
./sim --gtest_filter='MobileNetV4WorkloadTest.DepthwiseSamePaddingTapLayout:MobileNetV4WorkloadTest.DepthwiseSamePaddingStrideTwo:MobileNetV4WorkloadTest.DepthwiseTapLayoutRunsOnBankSidePim'
```

전체 회귀 테스트는 다음 명령으로 실행한다.

```bash
./sim --gtest_filter='PIMKernelFixture.add:PIMKernelFixture.relu:PIMKernelFixture.mul:PIMKernelFixture.gemv:PIMKernelFixture.gemv_tree:MobileNetV4WorkloadTest.*'
```

정상이라면 마지막에 아래와 같이 표시된다.

```text
[==========] 13 tests from 2 test suites ran.
[  PASSED  ] 13 tests.
```

## 5. 발견한 구현상 주의점

`preloadNoReplacement()`가 만든 메모리 transaction은 즉시 모두 처리되지 않는다. 따라서 transaction이 참조하는 `NumpyBurstType`을 지역 반복 변수로 만들면 실행 전에 메모리가 해제되어 비정상 종료할 수 있다. 구현에서는 모든 tap buffer를 `vector<NumpyBurstType>`에 보관해 `runPIM()`과 readback이 끝날 때까지 수명을 유지했다.

현재 64채널 element-wise 명령은 131,072 FP16 element 단위로 실행된다. 작은 논리 텐서도 이 크기로 zero-padding하므로 기능은 정확하지만 활용률은 낮다. 이 낭비는 이후 channel/tensor mapping 개선의 정량 평가 항목이다.

## 6. 다음 기술 작업

다음 구현 대상은 UIB 한 블록의 단계 연결이다.

```text
logic-die pointwise expand
-> bank-side depthwise
-> logic-die pointwise project
-> bank-side residual/activation
```

AI가 구현할 부분은 단계별 실행기, 중간 tensor 형상 검사, bank-to-logic 및 logic-to-bank 이동 byte/cycle 계측이다. 연구자가 결정해야 할 부분은 어떤 중간 데이터를 bank에 유지할지, logic die로 보낼 전송 단위가 전체 tensor인지 partial sum인지, 그리고 비교 시 적용할 logic PCU 자원 예산이다.
