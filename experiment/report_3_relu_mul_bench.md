# 3차 실험 보고서

## 1. 목적

이 보고서는 `PIMBenchFixture.relu`와 `PIMBenchFixture.mul` 성능 실험 결과를 정리한다.

이번 실험의 목표는 다음과 같다.

- `RELU`에서 PIM enabled와 disabled의 cycle 차이를 확인한다.
- `MUL`에서 PIM enabled와 disabled의 cycle 차이를 확인한다.
- 두 연산이 모두 bank-side PIM 경로에서 2배 이상 수준의 speed-up을 보이는지 확인한다.
- 같은 실험을 나중에 다시 수행할 수 있도록 터미널 프롬프트를 함께 남긴다.

## 2. 다시 돌릴 때 사용할 터미널 프롬프트

아래 명령을 WSL Ubuntu 터미널에서 그대로 실행하면 같은 실험을 다시 돌릴 수 있다.

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
```

만약 한 번에 이어서 보고 싶으면 아래처럼 파일 형태로도 실행할 수 있다.

```bash
bash experiment/run_first_experiments.sh
```

다만 이 스크립트는 `RELU`와 `MUL` 외에도 다른 테스트를 함께 실행하므로, 이번 보고서와 같은 범위만 다시 보려면 위의 두 줄만 따로 실행하는 편이 더 좋다.

## 3. 실험 대상

### 3.1 `PIMBenchFixture.relu`

- 실행 명령: `./sim --gtest_filter=PIMBenchFixture.relu`
- 목적: activation 연산의 성능 확인

### 3.2 `PIMBenchFixture.mul`

- 실행 명령: `./sim --gtest_filter=PIMBenchFixture.mul`
- 목적: element-wise 곱셈 연산의 성능 확인

## 4. 실제 실행 결과

### 4.1 `PIMBenchFixture.relu`

실행 출력 예시:

```text
Note: Google Test filter = PIMBenchFixture.relu
[==========] Running 1 test from 1 test suite.
[ RUN      ] PIMBenchFixture.relu
>>Performance Test
  RELU (PIM disabled)
  Input/output data dimension : 4194304
> Test Results 
> Cycle : 17504

  RELU (PIM enabled)
  Input/output data dimension : 4194304
> Test Results 
> Cycle : 7665

> Speed-up : 2.28363
[       OK ] PIMBenchFixture.relu (3114 ms)
```

### 4.2 `PIMBenchFixture.mul`

실행 출력 예시:

```text
Note: Google Test filter = PIMBenchFixture.mul
[==========] Running 1 test from 1 test suite.
[ RUN      ] PIMBenchFixture.mul
>>Performance Test
  MUL (PIM disabled)
  Input/output data dimension : 2097152
> Test Results 
> Cycle : 13255

  MUL (PIM enabled)
  Input/output data dimension : 2097152
> Test Results 
> Cycle : 5926

> Speed-up : 2.23675
[       OK ] PIMBenchFixture.mul (2347 ms)
```

## 5. 결과 해석

### 5.1 `RELU` 결과 해석

1. `RELU (PIM disabled)` 구간이 먼저 나온다.
   - 이것은 PIM을 쓰지 않고 일반 메모리 경로로 연산했을 때의 기준 cycle이다.
2. `Cycle : 17504`가 출력되었다.
   - 기대효과: PIM이 없는 baseline 성능을 보여준다.
3. `RELU (PIM enabled)` 구간이 나온다.
   - 이것은 PIM 연산 경로가 사용된 결과다.
4. `Cycle : 7665`가 출력되었다.
   - 기대효과: PIM enabled가 disabled보다 훨씬 적은 cycle을 사용했음을 의미한다.
5. `Speed-up : 2.28363`이 출력되었다.
   - 기대효과: PIM 사용 시 약 2.28배 빠르다는 뜻이다.
6. `[       OK ]`가 나왔다.
   - 기대효과: 성능 기준을 만족하고 테스트가 통과했음을 의미한다.

### 5.2 `MUL` 결과 해석

1. `MUL (PIM disabled)` 구간이 먼저 나온다.
   - 이것은 일반 메모리 경로 기준 cycle이다.
2. `Cycle : 13255`가 출력되었다.
   - 기대효과: PIM 미사용 시의 연산 비용을 나타낸다.
3. `MUL (PIM enabled)` 구간이 나온다.
   - 이것은 PIM을 사용한 연산 경로다.
4. `Cycle : 5926`가 출력되었다.
   - 기대효과: PIM enabled 경로가 더 빠르게 동작했음을 의미한다.
5. `Speed-up : 2.23675`가 출력되었다.
   - 기대효과: PIM 사용 시 약 2.24배 개선되었다는 뜻이다.
6. `[       OK ]`가 나왔다.
   - 기대효과: MUL 벤치마크도 성능 기준을 만족했다.

## 6. 종합 분석

### 6.1 공통점

- `RELU`와 `MUL` 모두 PIM enabled에서 disabled보다 더 적은 cycle을 사용했다.
- 두 테스트 모두 speed-up이 2.0을 넘었다.
- 둘 다 `[ OK ]`로 끝났기 때문에 성능 기준을 통과했다.

### 6.2 차이점

- `RELU`는 `4194304`개 데이터에 대해 측정되었다.
- `MUL`은 `2097152`개 데이터에 대해 측정되었다.
- `RELU`의 speed-up은 `2.28363`이었다.
- `MUL`의 speed-up은 `2.23675`였다.

### 6.3 해석

이 결과는 현재 bank-side PIM이 단순 activation과 element-wise 산술에 대해 충분한 성능 이득을 제공한다는 뜻이다.

특히:

- `RELU`는 MobileNetV4 같은 CNN에서 매우 자주 등장하는 활성화 연산이므로 중요하다.
- `MUL`은 quantization 보정, element-wise fusion, 일부 후처리 연산과 연결될 수 있어 중요하다.
- 두 연산이 모두 2배 이상 speed-up을 보였으므로, 이후 MobileNetV4 매핑에서 bank-side PIM 경로를 우선 적용할 근거가 된다.

## 7. 이번 실험에서 배운 점

1. `RELU`와 `MUL`은 성능 실험에서도 안정적으로 동작했다.
2. 설정 파일이 올바르면 PIMBenchFixture 계열은 정상적으로 cycle과 speed-up을 출력한다.
3. `Speed-up`은 단순히 PIM enabled가 잘 작동하는지 보는 값이 아니라, 실제로 기준선 대비 얼마나 개선되는지 보여준다.
4. 같은 테스트를 다시 돌릴 때는 위의 재실행 프롬프트를 그대로 쓰면 된다.

## 8. 주석형 해설

아래는 출력 한 줄을 읽는 방법을 아주 간단히 적은 해설이다.

```text
RELU (PIM disabled)
```
이 줄은 PIM을 쓰지 않은 기준 경로를 뜻한다.

```text
Cycle : 17504
```
이 수치는 일반 메모리 경로에서 연산이 끝나는 데 걸린 총 cycle이다.

```text
RELU (PIM enabled)
```
이 줄은 PIM 내부 연산 경로를 사용했다는 뜻이다.

```text
Cycle : 7665
```
이 수치는 PIM을 썼을 때 걸린 cycle이다.

```text
Speed-up : 2.28363
```
이 값은 disabled cycle을 enabled cycle로 나눈 비율이며, PIM 사용 효과를 직접 보여준다.

```text
[       OK ]
```
이 표시는 성능 조건을 충족하고 테스트가 통과했다는 뜻이다.

## 9. 결론

이번 실험에서 `PIMBenchFixture.relu`와 `PIMBenchFixture.mul`은 모두 성공했다.

- `RELU` speed-up: `2.28363x`
- `MUL` speed-up: `2.23675x`

즉, 현재 bank-side PIM은 activation과 element-wise 산술에서 모두 2배 이상 수준의 성능 개선을 보여준다.

