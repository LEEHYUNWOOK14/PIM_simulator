# 5차 실험 보고서

## 1. 목적

이 보고서는 `GEMV`와 `GEMV_TREE` 연산이 현재 시뮬레이터에서 정확하게 동작하는지 확인한 결과를 정리한다.

이번 실험의 목적은 다음과 같다.

- `GEMV` 기본 경로가 정상인지 확인한다.
- `GEMV_TREE`에서 tree reduction과 누산 결과가 맞는지 확인한다.
- MobileNetV4로 넘어가기 전에 projection 계열 연산의 기준선을 확보한다.
- 나중에 설계를 바꾸기 전에 현재 구조가 어디까지 맞는지 분명히 남긴다.

## 2. 다시 실행할 때 쓰는 터미널 프롬프트

아래 명령을 그대로 다시 붙여넣으면 같은 실험을 다시 돌릴 수 있다.

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMKernelFixture.gemv
./sim --gtest_filter=PIMKernelFixture.gemv_tree
```

## 3. 실험 대상

### 3.1 `PIMKernelFixture.gemv`

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.gemv`
- 목적: GEMV 기본 경로의 정확도 확인

### 3.2 `PIMKernelFixture.gemv_tree`

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.gemv_tree`
- 목적: tree reduction 기반 GEMV 경로의 정확도 확인

## 4. 실제 실행 결과

### 4.1 `PIMKernelFixture.gemv`

실행 결과:

```text
Note: Google Test filter = PIMKernelFixture.gemv
[==========] Running 1 test from 1 test suite.
[ RUN      ] PIMKernelFixture.gemv
>>PIM Kernel Accuraccy Test
  Weight data dimension : 4096x1024
  Input data dimension : 1024
  Output data dimension : 4096

> Test Result
  simulated output comparison via pre-calculated values
> passed : 4096
> failed : 0
[       OK ] PIMKernelFixture.gemv (1884 ms)
```

해석:

- 출력 4096개가 모두 정답과 일치했다.
- `failed`가 0이므로 GEMV 기본 경로는 정확도 기준에서 정상이다.
- 입력과 가중치 차원도 기대한 구조와 일치한다.

### 4.2 `PIMKernelFixture.gemv_tree`

실행 결과:

```text
Note: Google Test filter = PIMKernelFixture.gemv_tree
[==========] Running 1 test from 1 test suite.
[ RUN      ] PIMKernelFixture.gemv_tree
>>PIM Kernel Accuraccy Test
  Weight data dimension : 4096x1024
  Input data dimension : 1024
  Output data dimension : 4096

> Test Result
  simulated output comparison via pre-calculated values
> passed : 4096
> failed : 0
[       OK ] PIMKernelFixture.gemv_tree (2168 ms)
```

해석:

- 출력 4096개가 모두 정답과 일치했다.
- `failed`가 0이므로 tree reduction 기반 GEMV도 정확도 기준에서 정상이다.
- 일반 GEMV와 tree GEMV가 둘 다 맞으므로 reduction 경로까지 현재 시뮬레이터가 받아낸다.

## 5. 출력 설명

### 5.1 공통 출력 형식

1. `Note: Google Test filter = ...`
   - 지금 어떤 테스트만 골라서 실행했는지 보여준다.
2. `[==========] Running 1 test from 1 test suite.`
   - 전체 테스트 중 1개만 돌고 있다는 뜻이다.
3. `[ RUN      ] ...`
   - 실제 테스트가 시작되었다는 뜻이다.
4. `>>PIM Kernel Accuraccy Test`
   - 정확도 검사 구간이 시작되었다는 뜻이다.
5. `Weight data dimension`, `Input data dimension`, `Output data dimension`
   - 연산에 사용된 텐서 크기를 보여준다.
6. `simulated output comparison via pre-calculated values`
   - 미리 계산된 정답과 시뮬레이션 결과를 비교한다는 뜻이다.
7. `passed`, `failed`
   - 정답과 맞은 개수와 틀린 개수를 보여준다.
8. `[       OK ]`
   - 테스트가 성공적으로 끝났다는 뜻이다.

### 5.2 `passed`와 `failed` 해석

- `passed : 4096`
  - 출력 4096개가 모두 정답과 일치했다는 뜻이다.
- `failed : 0`
  - 틀린 출력이 하나도 없다는 뜻이다.

즉, 이 결과는 “대충 돌아간다”가 아니라 “출력값이 기준 정답과 일치한다”는 의미다.

## 6. 분석

### 6.1 `GEMV` 분석

1. `PIMKernelFixture.gemv`를 실행했다.
2. 입력은 `1024`, 가중치는 `4096x1024`, 출력은 `4096`으로 나왔다.
   - 기대효과: GEMV가 정상적인 행렬-벡터 형태로 구성되었음을 의미한다.
3. `passed`가 4096, `failed`가 0이었다.
   - 기대효과: 모든 출력 채널이 정답과 일치했음을 의미한다.
4. 결론적으로 GEMV 기본 경로는 현재 bank-side PIM에서 정상 동작한다.

### 6.2 `GEMV_TREE` 분석

1. `PIMKernelFixture.gemv_tree`를 실행했다.
2. 동일한 차원으로 결과가 출력됐다.
   - 기대효과: tree reduction 구조가 기대한 크기로 동작했음을 의미한다.
3. `passed`가 4096, `failed`가 0이었다.
   - 기대효과: reduction과 누산 결과가 정답과 일치했음을 의미한다.
4. 결론적으로 tree GEMV도 현재 구조에서 정상 동작한다.

## 7. 이번 결과의 의미

이번 실험은 설계를 바꾸기 전에 꼭 필요한 기준선이다.

- `GEMV`가 맞는다는 것은 projection 계열 연산의 기본 경로가 맞다는 뜻이다.
- `GEMV_TREE`가 맞는다는 것은 reduction 경로까지 현재 구조가 처리한다는 뜻이다.
- 따라서 MobileNetV4로 넘어가기 전에 필요한 산술 축은 현재 확보되어 있다.

## 8. 다음 단계

1. `PIMBenchFixture.gemv` 성능 실험을 돌린다.
2. `NUM_CHANS=1`, `16`, `64` 실험과 비교한다.
3. `gemv`와 `gemv_tree`의 차이가 설계상 어떤 의미를 가지는지 정리한다.
4. 그 다음에 설계를 바꿔야 할지 판단한다.

## 9. 한 줄 요약

이번 실험에서는 `GEMV`와 `GEMV_TREE`가 모두 정확도 기준에서 통과했다.  
즉, 현재 bank-side PIM은 projection 계열과 reduction 경로를 안정적으로 수행한다.

