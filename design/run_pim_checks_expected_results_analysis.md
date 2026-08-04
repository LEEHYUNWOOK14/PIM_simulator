# `run_pim_checks.sh` 예상 결과와 분석 방법

## 1. 목적

이 문서는 `design/run_pim_checks.sh`를 실행했을 때 예상되는 출력 형태와, 그 결과를 어떻게 해석해야 하는지를 정리한다.

대상 스크립트:

- [design/run_pim_checks.sh](./run_pim_checks.sh)

## 2. 스크립트가 하는 일

스크립트는 아래 순서로 테스트를 실행한다.

1. 정확도 테스트
2. 성능 테스트
3. 대역폭 테스트

정확도 테스트는 결과가 정답과 일치하는지 본다.  
성능 테스트는 cycle과 speed-up을 본다.  
대역폭 테스트는 메모리 시스템의 처리량 특성을 본다.

## 3. 실행 전 확인 사항

실행 전에 확인할 것:

- 프로젝트 루트의 `sim`이 이미 빌드되어 있어야 한다.
- WSL Ubuntu 터미널에서 실행해야 한다.
- 경로는 스크립트에 하드코딩된 `/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2`를 쓴다.

## 4. 예상 실행 결과 구조

스크립트를 돌리면 대략 다음과 같은 흐름으로 출력된다.

```text
[1/3] Accuracy tests
... PIMKernelFixture.add
... PIMKernelFixture.relu
... PIMKernelFixture.mul
... PIMKernelFixture.gemv
... PIMKernelFixture.gemv_tree

[2/3] Benchmark tests
... PIMBenchFixture.add
... PIMBenchFixture.relu
... PIMBenchFixture.mul
... PIMBenchFixture.gemv

[3/3] Bandwidth tests
... MemBandwidthFixture.hbm_read_bandwidth
... MemBandwidthFixture.hbm_write_bandwidth

Done.
```

각 테스트는 GoogleTest 스타일 출력이 함께 나온다.

## 5. 테스트별 예상 결과와 해석

### 5.1 `PIMKernelFixture.add`

예상 출력 의미:

- `Input/output data dimension : 1048576`
  - 1,048,576개 데이터에 대해 ADD를 검증한다.
- `passed : 1048576`
  - 전부 정답과 일치하면 정상이다.
- `failed : 0`
  - 하나라도 있으면 오류다.
- `[ PASSED ]`
  - 기능 검증 성공이다.

해석:

- bank-side element-wise 연산이 제대로 동작하는지 보는 첫 관문이다.
- 이전 실행 결과처럼 전부 pass면 현재 `ADD` 경로는 정상으로 볼 수 있다.

### 5.2 `PIMKernelFixture.relu`

예상 출력 의미:

- 입력 데이터 전체에 대해 ReLU가 올바르게 적용되는지 검증한다.
- `passed`가 전체 개수와 같아야 한다.
- `failed`는 0이어야 한다.

해석:

- sign bit 처리와 zero-clamp 경로를 확인한다.
- ADD와 함께 가장 기본적인 bank-side activation 검증이다.

### 5.3 `PIMKernelFixture.mul`

예상 출력 의미:

- element-wise 곱셈 결과가 정답과 일치해야 한다.
- pass/fail 요약이 핵심이다.

해석:

- 산술 경로가 ADD보다 조금 더 복잡하므로, 곱셈 루틴이 정상인지 확인한다.

### 5.4 `PIMKernelFixture.gemv`

예상 출력 의미:

- GEMV 기능 검증을 수행한다.
- 출력 길이와 내부 partial sum 계산이 맞아야 한다.
- 데이터가 더 복잡하게 흘러가므로 trace 없이도 기능성 확인이 가능하다.

해석:

- 향후 `1x1 CONV` 또는 projection 계열로 확장할 때 기준이 된다.
- bank-side PIM과 다음 단계 logic-die PIM 사이의 연결점 역할을 한다.

### 5.5 `PIMKernelFixture.gemv_tree`

예상 출력 의미:

- tree reduction 경로를 함께 검증한다.
- adder tree 결과가 정답과 맞아야 한다.

해석:

- 누산과 reduction 구조를 확인한다.
- logic-die PIM에서 partial sum을 합치는 구조로 확장할 때 유용하다.

## 6. 성능 테스트 결과 읽는 법

### 6.1 `PIMBenchFixture.add`

예상 출력 형태:

- `PIM disabled` 구간
- `PIM enabled` 구간
- 각 구간의 `Cycle`
- 마지막 `Speed-up`

해석 방법:

- `PIM disabled`는 기준선이다.
- `PIM enabled`는 하드웨어 가속 효과를 본다.
- `Speed-up = disabled cycle / enabled cycle`

예시:

- disabled cycle이 6651
- enabled cycle이 3349
- speed-up은 약 1.98x

즉, PIM 사용 시 약 2배 빨라졌다는 뜻이다.

### 6.2 `PIMBenchFixture.gemv`

예상 출력 형태:

- 비활성화 시 cycle
- 활성화 시 cycle
- speed-up

해석:

- GEMV는 ADD보다 PIM 효과가 더 잘 드러날 수 있다.
- 이전 로그에서는 약 `2.74x` 수준의 향상이 관측되었다.
- 이 결과는 projection/conv 확장 가능성을 판단하는 기준이 된다.

## 7. 대역폭 테스트 결과 읽는 법

### 7.1 `MemBandwidthFixture.hbm_read_bandwidth`

보는 것:

- read throughput
- cycle 대비 전송량
- 채널 병렬성 효과

### 7.2 `MemBandwidthFixture.hbm_write_bandwidth`

보는 것:

- write throughput
- command queue와 bus 효율
- bank 충돌이나 정책 영향

해석:

- read와 write는 서로 다른 병목을 가진다.
- PIM 추가 후 성능이 변하면, 연산 자체보다 메모리 이동이 병목인지 같이 봐야 한다.

## 8. 결과 분석 체크리스트

테스트를 돌린 뒤 아래 순서로 본다.

1. `PASSED`인지 본다.
2. `failed` 수가 0인지 본다.
3. `cycle`이 기대보다 크지 않은지 본다.
4. `speed-up`이 1보다 큰지 본다.
5. read/write bandwidth가 비정상적으로 낮지 않은지 본다.
6. 특정 연산만 느리면 해당 경로를 의심한다.

## 9. 해석 기준 요약

### 9.1 정상으로 볼 수 있는 경우

- accuracy test가 전부 PASS
- benchmark에서 enabled cycle이 disabled cycle보다 작음
- speed-up이 1보다 큼
- read/write bandwidth가 설정 변경에 따라 합리적으로 변함

### 9.2 의심해야 하는 경우

- accuracy에서 failed가 발생
- speed-up이 1보다 작음
- benchmark가 지나치게 오래 걸림
- read/write 결과가 설정 변경과 무관하게 거의 같음

## 10. 실험 기록 예시

실험할 때는 아래 항목을 같이 적으면 좋다.

- 실행 날짜
- 사용한 설정 파일
- `PIM_PRECISION`
- `NUM_CHANS`
- `ADDRESS_MAPPING_SCHEME`
- 테스트 이름
- pass/fail
- cycle
- speed-up
- 특이 사항

## 11. MobileNetV4로 이어서 볼 포인트

MobileNetV4를 붙일 때는 아래 순서로 해석한다.

1. `ADD`, `RELU`, `MUL`이 먼저 안정적인지 본다.
2. `GEMV`가 projection 계열 확장에 충분한지 본다.
3. `gemv_tree`로 누산 구조를 확인한다.
4. 이후 `1x1 CONV`, `depthwise conv`를 추가한다.

## 12. 결론

이 스크립트는 단순한 실행 목록이 아니라, 지금 시뮬레이터가 어디까지 정상인지 확인하는 체크포인트 묶음이다.  
정확도 테스트로 기능을 확인하고, 성능 테스트로 PIM 이득을 확인하고, 대역폭 테스트로 메모리 병목을 확인하면 된다.

## 13. 실제 실행 결과 해석 예시

아래 해석은 실제로 `run_pim_checks.sh`를 실행했을 때 나온 로그를 기준으로 한다.

### 13.1 정확도 테스트 결과

실행 로그의 핵심은 다음과 같다.

```text
PIMKernelFixture.add
passed : 1048576
failed : 0

PIMKernelFixture.relu
passed : 1048576
failed : 0

PIMKernelFixture.mul
passed : 1048576
failed : 0

PIMKernelFixture.gemv
passed : 4096
failed : 0

PIMKernelFixture.gemv_tree
passed : 4096
failed : 0
```

해석:

- `add`, `relu`, `mul`은 1,048,576개 요소 전부 정답과 일치했다.
- `gemv`와 `gemv_tree`는 출력 4096개가 모두 정답과 일치했다.
- 따라서 현재 bank-side PIM의 정확도 경로는 기능적으로 정상이다.

### 13.2 성능 테스트 결과

실행 로그의 핵심은 다음과 같다.

```text
PIMBenchFixture.add
PIM disabled  Cycle : 6651
PIM enabled   Cycle : 3349
Speed-up : 1.98597
FAILED
```

해석:

- PIM enabled가 disabled보다 빠르므로 방향성은 맞다.
- 하지만 이 테스트는 `expectPIMBench(2.0)` 기준을 사용한다.[^1]
- 따라서 speed-up `1.98597`은 2.0을 아주 조금 넘지 못해 실패로 표시된다.
- 이것은 기능 실패가 아니라 **성능 기준 미달**이다.

### 13.3 이 결과가 의미하는 것

- 정확도는 통과했으므로 데이터 이동, 산술, 결과 비교는 정상이다.
- 성능 테스트는 “PIM 가속이 있긴 하지만 기대한 2.0x를 간신히 못 넘는 상태”를 보여준다.
- 따라서 지금 단계에서 필요한 것은 기능 수정보다 **성능 오버헤드 분석**이다.[^2]

### 13.4 다음에 볼 것

1. `ADD`, `RELU`, `MUL`은 정확도 통과로 확인 완료로 본다.
2. `GEMV`와 `GEMV_TREE`도 정확도 기준에서는 정상이다.
3. `PIMBenchFixture.add`는 거의 2x 근처이므로, 어디에서 cycle이 더 들어가는지 본다.
4. trace 옵션을 켜서 명령 경로와 모드 전환을 살펴본다.[^3]

### 13.5 결과를 한 문장으로 쓰면

> 현재 시뮬레이터는 bank-side PIM 정확도 검증에는 성공했으며, `ADD`, `RELU`, `MUL`, `GEMV`, `GEMV_TREE` 모두 정답 일치 결과를 보였다.  
> 다만 `PIMBenchFixture.add`는 speed-up이 `1.98597x`로 `expectPIMBench(2.0)` 기준을 근소하게 넘지 못해 실패했으므로, 이는 기능 오류가 아니라 성능 기준 미달로 해석해야 한다.

[^1]: `src/tests/PIMBenchTestCases.cpp`에서 각 벤치마크는 `expectPIMBench(2.0)`를 호출한다.
[^2]: `src/tests/PIMBenchTestCases.h`의 `expectPIMBench()`는 `non_pim_cycle_ / pim_cycle_ > expected_perf_gain` 조건을 검사한다.
[^3]: `DEBUG_CMD_TRACE`, `DEBUG_PIM_TIME`, `PRINT_MEM_TRACE` 같은 trace 옵션을 켜면 성능 오버헤드의 원인을 더 잘 볼 수 있다.


