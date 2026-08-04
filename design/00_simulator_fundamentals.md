# 0번. 시뮬레이터 기초정리

## 1. 목적

이 문서는 지금 시뮬레이터에서 먼저 무엇을 검증해야 하는지 정리한 출발점이다.

우선 목표는 다음 두 가지다.

1. 현재 시뮬레이터로 가능한 bank-side PIM 연산부터 검증한다.
2. MobileNetV4를 나중에 얹기 위한 기준 문서를 하나로 묶어둔다.

## 2. 읽는 법

이 문서는 다음 순서로 읽으면 된다.

1. 3절에서 현재 시뮬레이터가 가능한 연산을 확인한다.
2. 4절에서 MobileNetV4를 위한 bank-side 우선 검증 순서를 본다.
3. 5절에서 시뮬레이터 수정 항목표와 연결할 기준을 잡는다.
4. 6절에서 블록별 PIM 배치 방향을 본다.

## 3. 현재 시뮬레이터에서 가능한 bank-side PIM 연산

현재 코드 기준으로 바로 확인 가능한 연산은 아래와 같다.

| 연산 | 현재 상태 | 관련 파일 | 비고 |
|---|---|---|---|
| `ADD` | 가능 | `src/tests/KernelTestCases.cpp`, `src/tests/PIMKernel.cpp`, `src/PIMBlock.cpp` | element-wise 확인용 |
| `MUL` | 가능 | `src/tests/KernelTestCases.cpp`, `src/tests/PIMKernel.cpp`, `src/PIMBlock.cpp` | element-wise 확인용 |
| `RELU` | 가능 | `src/tests/KernelTestCases.cpp`, `src/tests/PIMKernel.cpp`, `src/PIMBlock.cpp` | activation 확인용 |
| `GEMV` | 가능 | `src/tests/KernelTestCases.cpp`, `src/tests/PIMKernel.cpp`, `src/PIMCmdGen.cpp` | bank-side 연산 검증과 확장 기준 |
| `GEMV_TREE` | 가능 | `src/tests/KernelTestCases.cpp`, `src/tests/PIMKernel.cpp` | tree reduction 포함 |

## 4. MobileNetV4에서 먼저 확인할 bank-side 검증 순서

MobileNetV4 전체를 바로 돌리기보다, bank-side 연산부터 검증하는 순서가 맞다.

### 4.1 1차 검증 대상

| 우선순위 | 연산 | 이유 |
|---|---|---|
| 1 | `ADD` | residual merge에 바로 연결 가능 |
| 2 | `RELU` | activation 경로 확인이 쉬움 |
| 3 | `MUL` | element-wise 연산 검증 |
| 4 | `GEMV` | later conv-like 확장의 기준 |
| 5 | `GEMV_TREE` | reduction 경로 검증 |

### 4.2 왜 이 순서인가

- `ADD`, `RELU`, `MUL`은 구조가 단순해서 bank-side PIM의 정확도를 먼저 확인하기 좋다.
- `GEMV`는 추후 `1x1 CONV`나 projection 계열 확장의 기준이 된다.
- `GEMV_TREE`는 reduction과 누산 경로를 보여주므로 후속 logic-die PIM과도 연결하기 쉽다.

## 5. 시뮬레이터 수정 항목과 연결되는 기준

이 문서는 아래 수정 항목표와 연결된다.

- [시뮬레이터 수정 항목표](./simulator_modification_items.md)
- [MobileNetV4 연산 처리 기능표](./mobilenetv4_operation_mapping.md)
- [MobileNetV4 블록별 PIM 배치표](./mobilenetv4_blockwise_pim_placement.md)

bank-side 검증이 끝나면 다음 단계로는 다음 수정이 필요하다.

1. 연산 타겟 분리
2. logic-die PIM 계층 추가
3. MobileNetV4 연산의 블록 단위 매핑

## 6. MobileNetV4 블록별 방향성

| 블록 | 우선 위치 | 이유 |
|---|---|---|
| `Residual Path` | `BANK_SIDE_PIM` | element-wise라 가장 먼저 붙이기 좋음 |
| `Activation Path` | `BANK_SIDE_PIM` | `RELU` 검증 결과를 재사용 가능 |
| `Depthwise Separable Stage` | `BANK_SIDE_PIM` 우선 | locality가 높음 |
| `Pointwise Projection Stage` | `LOGIC_DIE_PIM` | 1x1 conv와 누산이 핵심 |
| `Inverted Bottleneck` | `HYBRID` | bank-side와 logic-die 성격이 섞임 |
| `Universal Inverted Bottleneck` | `HYBRID` | 블록 내부 분할이 필요함 |
| `Stem Conv` | `LOGIC_DIE_PIM` | 입력부에서 채널 확장과 MAC 비중이 큼 |
| `Classifier Head` | `HOST` | 초기에는 host fallback이 안전함 |

## 7. 바로 실행해볼 테스트

```bash
./sim --gtest_filter=PIMKernelFixture.add
./sim --gtest_filter=PIMKernelFixture.relu
./sim --gtest_filter=PIMKernelFixture.mul
./sim --gtest_filter=PIMKernelFixture.gemv
./sim --gtest_filter=PIMKernelFixture.gemv_tree
```

## 8. 결론

지금 단계에서는 MobileNetV4 전체를 한 번에 돌리기보다, 현재 시뮬레이터에서 가능한 bank-side PIM 연산부터 안정적으로 검증하는 것이 맞다.  
그 결과를 바탕으로 `1x1 CONV`, `depthwise conv`, `residual`, `activation`을 차례대로 확장해야 한다.
