# 2차 실험 보고서

## 1. 목적

이 보고서는 bank-side PIM 기준으로 `RELU`, `MUL`, `GEMV_TREE` 연산이 현재 시뮬레이터에서 정상 동작하는지 확인한 결과를 정리한다.

이번 실험의 목적은 다음과 같다.

- `RELU` 경로가 정확한지 확인한다.
- `MUL` 경로가 정확한지 확인한다.
- `GEMV_TREE`에서 tree reduction과 누산 결과가 맞는지 확인한다.
- MobileNetV4로 확장하기 전에 기본 산술 및 reduction 경로를 기준선으로 확보한다.

## 2. 실험 대상

### 2.1 `PIMKernelFixture.relu`

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.relu`
- 목적: activation 경로의 정확도 확인

### 2.2 `PIMKernelFixture.mul`

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.mul`
- 목적: element-wise 산술 연산의 정확도 확인

### 2.3 `PIMKernelFixture.gemv_tree`

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.gemv_tree`
- 목적: tree reduction 기반 GEMV 경로의 정확도 확인

## 3. 실제 실행 결과

### 3.1 `PIMKernelFixture.relu`

실행 결과:

```text
passed : 1048576
failed : 0
[       OK ]
```

해석:

- 1,048,576개 요소가 모두 정답과 일치했다.
- `failed`가 0이므로 activation 경로는 정확도 기준에서 정상이다.
- `RELU`의 sign-bit 처리와 zero clamp가 기대대로 동작한다고 볼 수 있다.

### 3.2 `PIMKernelFixture.mul`

실행 결과:

```text
passed : 1048576
failed : 0
[       OK ]
```

해석:

- 1,048,576개 요소가 모두 정답과 일치했다.
- `MUL`의 element-wise 곱셈 경로가 정상이다.
- ADD보다 조금 더 복잡한 산술 연산도 현재 bank-side PIM에서 문제없이 동작한다.

### 3.3 `PIMKernelFixture.gemv_tree`

실행 결과:

```text
Weight data dimension : 4096x1024
Input data dimension : 1024
Output data dimension : 4096
passed : 4096
failed : 0
[       OK ]
```

해석:

- 출력 4096개가 모두 정답과 일치했다.
- tree reduction을 포함한 GEMV 경로가 정확도 기준에서 정상이다.
- 누산과 reduction 경로가 맞기 때문에, 이후 더 큰 projection 계열 연산으로 확장할 때 기준점으로 쓸 수 있다.

## 4. 분석

### 4.1 `RELU` 분석

1. `PIMKernelFixture.relu`를 실행했다.
2. `passed`가 1,048,576으로 나왔다.
   - 기대효과: activation 결과가 정답과 일치했음을 의미한다.
3. `failed`가 0으로 나왔다.
   - 기대효과: sign 처리와 clamp 로직이 정상임을 의미한다.
4. 결론적으로 `RELU`는 현재 bank-side PIM 경로에서 정상 동작한다.

### 4.2 `MUL` 분석

1. `PIMKernelFixture.mul`를 실행했다.
2. `passed`가 1,048,576으로 나왔다.
   - 기대효과: 곱셈 결과가 전부 정답과 일치했다는 뜻이다.
3. `failed`가 0으로 나왔다.
   - 기대효과: element-wise 산술 경로가 정상임을 의미한다.
4. 결론적으로 `MUL` 역시 현재 기준에서 정상 동작한다.

### 4.3 `GEMV_TREE` 분석

1. `PIMKernelFixture.gemv_tree`를 실행했다.
2. 입력과 가중치 차원은 `4096x1024`, `1024`, 출력은 `4096`으로 확인됐다.
   - 기대효과: GEMV가 정상적인 형태로 구성되었음을 의미한다.
3. `passed`가 4096, `failed`가 0이었다.
   - 기대효과: tree reduction 결과가 정답과 일치함을 의미한다.
4. 결론적으로 `GEMV_TREE`는 누산과 reduction을 포함한 경로에서도 정상이다.

## 5. 현재까지의 결론

- `RELU`는 정확도 기준에서 정상이다.
- `MUL`도 정확도 기준에서 정상이다.
- `GEMV_TREE`도 정확도 기준에서 정상이다.
- 따라서 현재 bank-side PIM 기본 연산군은 `ADD`, `RELU`, `MUL`, `GEMV`, `GEMV_TREE`까지 기능적으로 확보되었다.

## 6. 의미

이번 결과는 MobileNetV4 확장 전에 아주 중요하다.

- `RELU`는 activation 경로의 기준이 된다.
- `MUL`은 element-wise 산술 경로의 기준이 된다.
- `GEMV_TREE`는 projection과 partial sum/reduction 구조의 기준이 된다.

즉, bank-side PIM만으로도 현재 시뮬레이터가 기본 산술과 reduction을 정상 처리한다는 사실이 확인되었다.

## 7. 다음 단계

1. `PIMBenchFixture.relu`와 `PIMBenchFixture.mul`로 성능 수치를 확인한다.
2. `PIMBenchFixture.gemv` 결과와 이번 `GEMV_TREE` 결과를 함께 비교한다.
3. MobileNetV4의 `1x1 CONV`, `depthwise conv`, `residual add`, `activation`으로 확장한다.

## 8. 한 줄 요약

이번 실험에서는 `RELU`, `MUL`, `GEMV_TREE`가 모두 정확도 기준에서 통과했다.  
즉, 현재 bank-side PIM은 element-wise 연산과 tree reduction 경로를 안정적으로 수행한다.



