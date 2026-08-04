# 4차 실험 보고서

## 1. 목적

이 보고서는 `PIMBenchFixture.relu`와 `PIMBenchFixture.mul` 성능 실험 결과를 정리한다.

이번 실험의 목적은 다음과 같다.

- `RELU`에서 PIM enabled와 disabled의 성능 차이를 확인한다.
- `MUL`에서 PIM enabled와 disabled의 성능 차이를 확인한다.
- 같은 실험을 나중에 다시 수행할 수 있도록 터미널 프롬프트를 남긴다.
- 출력 예시와 해설을 함께 적어서, 다음 실험자가 결과를 그대로 읽을 수 있게 한다.

## 2. 다시 돌릴 때 사용할 터미널 프롬프트

아래 명령을 WSL Ubuntu 터미널에서 그대로 실행하면 같은 실험을 다시 돌릴 수 있다.

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
```

## 3. 실험 대상

### 3.1 `PIMBenchFixture.relu`

- 실행 명령: `./sim --gtest_filter=PIMBenchFixture.relu`
- 목적: activation 성능 확인

### 3.2 `PIMBenchFixture.mul`

- 실행 명령: `./sim --gtest_filter=PIMBenchFixture.mul`
- 목적: element-wise 곱셈 성능 확인

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
[       OK ] PIMBenchFixture.relu (3015 ms)
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
[       OK ] PIMBenchFixture.mul (2365 ms)
```

## 5. 출력 해설

### 5.1 공통 출력 형식

1. `Note: Google Test filter = ...`
   - 어떤 테스트만 선택해서 실행했는지 보여준다.
2. `[==========] Running 1 test from 1 test suite.`
   - 한 개의 테스트만 실행하고 있음을 보여준다.
3. `[ RUN      ] ...`
   - 실제 테스트가 시작되었다는 뜻이다.
4. `>>Performance Test`
   - 성능 테스트 구간이 시작되었다는 뜻이다.
5. `PIM disabled`와 `PIM enabled`
   - PIM을 쓰지 않은 기준 경로와 PIM을 쓴 경로를 나란히 비교한다.
6. `Cycle`
   - 해당 경로를 완료하는 데 걸린 사이클 수다.
7. `Speed-up`
   - `disabled cycle / enabled cycle`의 비율로, PIM의 성능 이득을 직접 보여준다.
8. `[       OK ]`
   - 성능 기준을 만족하고 테스트가 통과했음을 의미한다.

### 5.2 `RELU` 해설

1. `RELU (PIM disabled)`에서 `Cycle : 17504`가 나왔다.
   - 기대효과: PIM을 사용하지 않을 때의 baseline 성능을 보여준다.
2. `RELU (PIM enabled)`에서 `Cycle : 7665`가 나왔다.
   - 기대효과: PIM 경로가 훨씬 적은 cycle로 끝났음을 보여준다.
3. `Speed-up : 2.28363`이 나왔다.
   - 기대효과: PIM 사용 시 약 2.28배 빨라졌다는 뜻이다.
4. `[       OK ]`가 나왔다.
   - 기대효과: 성능 기준을 통과했다는 뜻이다.

### 5.3 `MUL` 해설

1. `MUL (PIM disabled)`에서 `Cycle : 13255`가 나왔다.
   - 기대효과: PIM 미사용 기준 cycle이다.
2. `MUL (PIM enabled)`에서 `Cycle : 5926`이 나왔다.
   - 기대효과: PIM 사용 시 더 짧은 cycle로 끝났음을 보여준다.
3. `Speed-up : 2.23675`가 나왔다.
   - 기대효과: PIM 사용 시 약 2.24배 성능 향상이 있다는 뜻이다.
4. `[       OK ]`가 나왔다.
   - 기대효과: MUL 성능 테스트도 통과했다.

## 6. 결과 분석

### 6.1 `RELU`

- disabled cycle: `17504`
- enabled cycle: `7665`
- speed-up: `2.28363`

해석:

- activation 연산이 PIM에 잘 맞는다.
- 메모리 왕복보다 메모리 내부 처리의 이점이 분명하다.
- MobileNetV4의 activation 경로를 bank-side PIM에 둘 근거가 된다.

### 6.2 `MUL`

- disabled cycle: `13255`
- enabled cycle: `5926`
- speed-up: `2.23675`

해석:

- element-wise 곱셈도 2배 이상 가속된다.
- ADD, RELU와 같은 단순 산술 경로가 현재 구조에서 충분히 성능이 좋다.
- quantization 보정이나 element-wise fusion 후보로 쓸 수 있다.

## 7. 보정 메모

이 실험을 다시 돌릴 때는 설정 파일이 BOM 없이 저장되어 있어야 한다.

이전에는 `system_hbm_64ch.ini`가 BOM 때문에 파서에서 `invalid parameter`를 낸 적이 있었지만, 지금은 제거된 상태다.

즉, 같은 명령을 다시 실행하면 같은 결과를 재현할 수 있다.

## 8. 재현용 체크리스트

실험 전에 아래를 확인한다.

1. `system_hbm_64ch.ini`가 BOM 없이 저장되어 있는지 확인한다.
2. `PIM_PRECISION=FP16`이 유지되는지 확인한다.
3. `ADDRESS_MAPPING_SCHEME=Scheme8`이 유지되는지 확인한다.
4. WSL Ubuntu에서 실행하는지 확인한다.
5. 프로젝트 루트에서 실행하는지 확인한다.

## 9. 결론

이번 실험에서 `RELU`와 `MUL`은 모두 성능 기준을 통과했다.

- `RELU` speed-up: `2.28363x`
- `MUL` speed-up: `2.23675x`

따라서 현재 bank-side PIM은 activation과 element-wise 산술에서 모두 2배 이상 수준의 성능 개선을 보여준다.

