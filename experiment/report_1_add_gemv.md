# 1차 실험 보고서

## 1. 목적

이 보고서는 실험 계획서의 첫 단계인 bank-side PIM 검증 결과를 정리한다.

이번 보고서의 기준은 다음과 같다.

- `PIMKernelFixture.add` 실제 실행 결과
- `PIMBenchFixture.gemv` 저장된 profiling 로그 결과
- `PIMKernelFixture.gemv_tree`는 이번 세션에서 직접 실행하지 못한 상태

## 2. 실험 대상

### 2.1 `ADD` 정확도 실험

- 실행 명령: `./sim --gtest_filter=PIMKernelFixture.add`
- 목적: bank-side element-wise 연산의 정확도 확인

### 2.2 `GEMV` 성능 실험

- 참조 데이터: `profiling/gemv/smoke_final.log`
- 목적: GEMV 경로의 성능과 speed-up 확인

## 3. 실제 결과

### 3.1 `PIMKernelFixture.add`

실행 결과:

```text
passed : 1048576
failed : 0
[ PASSED ]
```

해석:

- 1,048,576개 요소가 모두 정답과 일치했다.
- `failed`가 0이므로 현재 `ADD` 경로는 정확도 기준에서 정상이다.
- bank-side PIM의 가장 기본적인 element-wise 경로가 제대로 동작한다는 의미다.

### 3.2 `PIMBenchFixture.gemv`

profiling 로그 결과:

```text
PIM disabled  Cycle : 36082
PIM enabled   Cycle : 13166
Speed-up : 2.74054
[       OK ]
```

해석:

- PIM enabled가 disabled보다 크게 빠르다.
- speed-up이 `2.74054x`이므로 GEMV 경로에서 PIM 효과가 분명하다.
- 이 결과는 나중에 `1x1 CONV`나 projection 계열을 붙일 때 좋은 기준선이 된다.

## 4. 실험 분석

### 4.1 `ADD` 실험 분석

1. `PIMKernelFixture.add`를 실행했다.
2. `passed`가 1,048,576으로 나왔다.
   - 기대효과: element-wise 연산이 전부 정답과 일치했음을 의미한다.
3. `failed`가 0으로 나왔다.
   - 기대효과: bank-side PIM의 기본 산술 경로가 정상임을 의미한다.
4. 따라서 현재 `ADD` 경로는 정확도 기준에서 합격이다.

### 4.2 `GEMV` 실험 분석

1. 저장된 `profiling/gemv/smoke_final.log` 결과를 확인했다.
2. PIM disabled cycle은 `36082`였다.
   - 기대효과: 일반 메모리 경로의 기준 cycle을 보여준다.
3. PIM enabled cycle은 `13166`이었다.
   - 기대효과: PIM이 적용된 실행 경로의 cycle을 보여준다.
4. speed-up은 `2.74054`였다.
   - 기대효과: GEMV에서 PIM이 약 2.74배 빨라졌음을 뜻한다.
5. 따라서 GEMV 경로는 정확도뿐 아니라 성능 면에서도 기준을 충족한다.

## 5. 현재까지의 결론

- `ADD`는 정확도 기준에서 정상이다.
- `GEMV`는 저장된 성능 결과 기준으로 약 `2.74x` speed-up을 보였다.
- 따라서 현재 bank-side PIM의 기본 연산 경로는 검증 가능한 상태다.
- 이 결과를 바탕으로 `RELU`, `MUL`, `GEMV_TREE`를 같은 방식으로 확장하면 된다.

## 6. 아직 남은 항목

- `PIMKernelFixture.gemv_tree`
- `PIMKernelFixture.relu`
- `PIMKernelFixture.mul`
- `PIMBenchFixture.relu`
- `PIMBenchFixture.mul`

특히 `gemv_tree`는 이번 세션에서 직접 다시 돌리려 했지만 실행 환경 권한 문제로 완료하지 못했다.

## 7. 다음 단계

1. `RELU` 정확도와 성능을 확인한다.
2. `MUL` 정확도와 성능을 확인한다.
3. `GEMV_TREE`를 다시 실행할 수 있는 환경에서 돌린다.
4. 결과를 바탕으로 MobileNetV4의 projection 계열과 reduction 구조를 연결한다.

## 8. 한 줄 요약

현재 시뮬레이터는 `ADD` 정확도를 통과했고, 저장된 `GEMV` 로그에서는 `2.74054x` speed-up이 확인되었다.  
즉, bank-side PIM의 기본 연산 경로는 기능과 성능 양쪽에서 출발점으로 쓸 수 있다.



