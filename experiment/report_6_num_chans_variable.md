# 6차 실험 보고서

## 1. 목적

이 보고서는 `NUM_CHANS` 채널 수 변수를 바꿨을 때 현재 시뮬레이터가 어떻게 반응하는지 확인한 결과를 정리한다.

이번 실험의 목적은 다음과 같다.

- 채널 수를 줄였을 때 benchmark가 정상 동작하는지 확인한다.
- `1ch`, `16ch`, `64ch` 비교의 첫 단계 결과를 확보한다.
- 설계 변경 전에 채널 병렬성이 실제로 어떤 영향을 주는지 본다.
- 채널 수를 바꿨을 때 안정성이 유지되는지 확인한다.

## 2. 실험 방식

`PIMBenchFixture`는 `system_hbm_64ch.ini`를 읽기 때문에, 이 파일의 `NUM_CHANS`만 바꿔가며 실험했다.

실험 순서는 다음과 같다.

1. `NUM_CHANS=1`
2. `NUM_CHANS=16`
3. `NUM_CHANS=64` 복귀 확인

## 3. 다시 실행할 때 쓰는 터미널 프롬프트

아래 명령을 그대로 다시 쓰면 같은 실험을 반복할 수 있다.

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

단, 실행 전에 `system_hbm_64ch.ini`의 `NUM_CHANS` 값을 실험하려는 채널 수로 바꿔야 한다.

## 4. 실제 실행 결과

### 4.1 `NUM_CHANS=1`

`system_hbm_64ch.ini`의 `NUM_CHANS`를 1로 바꾸고 benchmark를 실행했다.

실행 결과:

```text
Note: Google Test filter = PIMBenchFixture.add
[ RUN      ] PIMBenchFixture.add
>>Performance Test
  ADD (PIM disabled)
  Input/output data dimension : 1048576
> Test Results
> Cycle : 424358

  ADD (PIM enabled)
  Input/output data dimension : 1048576
Segmentation fault
```

해석:

- PIM disabled 구간은 시작되었다.
- PIM enabled 구간으로 넘어가다가 세그폴트가 발생했다.
- 즉, `NUM_CHANS=1` 상태에서는 현재 benchmark 경로가 끝까지 수행되지 못했다.

### 4.2 `NUM_CHANS=16`

`system_hbm_64ch.ini`의 `NUM_CHANS`를 16으로 바꾸고 benchmark를 다시 실행했다.

실행 결과:

```text
Note: Google Test filter = PIMBenchFixture.add
[ RUN      ] PIMBenchFixture.add
>>Performance Test
  ADD (PIM disabled)
  Input/output data dimension : 1048576
> Test Results
> Cycle : 26774

  ADD (PIM enabled)
  Input/output data dimension : 1048576
Segmentation fault
```

해석:

- `NUM_CHANS=16`에서도 동일하게 PIM enabled 단계에서 세그폴트가 났다.
- 즉, 채널 수를 줄인 구성은 현재 benchmark 코드와 안정적으로 맞지 않는다.

### 4.3 `NUM_CHANS=64` 복귀 확인

채널 수를 다시 64로 돌려놓고 benchmark를 실행했다.

실행 결과:

```text
Note: Google Test filter = PIMBenchFixture.add
[ RUN      ] PIMBenchFixture.add
>>Performance Test
  ADD (PIM disabled)
  Input/output data dimension : 1048576
> Test Results
> Cycle : 6651

  ADD (PIM enabled)
  Input/output data dimension : 1048576
> Test Results
> Cycle : 3349

> Speed-up : 1.98597
```

해석:

- 64채널 기준은 다시 정상적으로 실행되었다.
- 다만 `ADD` benchmark는 기대 성능 기준을 넘지 못해서 테스트가 실패했다.
- `Speed-up`은 `1.98597`로 출력되었다.

## 5. 결과 해석

### 5.1 1채널과 16채널에서 공통으로 보인 점

1. `PIM disabled` 구간은 계산이 시작됐다.
2. `PIM enabled`로 넘어가다가 세그폴트가 났다.
3. 따라서 채널 수만 바꾸는 단순한 실험이 현재 benchmark에 바로 호환되지는 않는다.

이 결과는 두 가지 중 하나를 뜻할 수 있다.

- benchmark 내부에서 64채널 기준의 배열이나 인덱스를 전제로 하고 있다.
- 채널 수를 줄이면 일부 PIM 경로가 아직 처리되지 않는 상태다.

### 5.2 64채널 기준

- 64채널은 다시 실행 가능했다.
- 따라서 현재 시뮬레이터의 안정 기준은 여전히 64채널 구성에 가깝다.
- `ADD` benchmark는 성능 기준을 약간 못 넘었으므로, 다음 단계에서 병목 분석이 필요하다.

## 6. 분석 포인트

### 6.1 `NUM_CHANS=1`

- 채널 수가 줄어들면 데이터 분산과 명령 분배 구조가 달라진다.
- 현재 benchmark는 그 변화에 완전히 대응하지 못했다.
- 그래서 설계 변경 전이라면 이 부분을 먼저 파서와 명령 경로에서 확인해야 한다.

### 6.2 `NUM_CHANS=16`

- 16채널 역시 동일하게 실패했다.
- 즉, 문제는 1채널 특이값이 아니라 낮은 채널 수 자체에 있다.

### 6.3 `NUM_CHANS=64`

- 64채널은 benchmark가 다시 돌아간다.
- 현재 기준 실험은 64채널을 baseline으로 두는 것이 안전하다.

## 7. 현재까지의 결론

- `NUM_CHANS=1`은 benchmark에서 세그폴트가 발생했다.
- `NUM_CHANS=16`도 같은 방식으로 세그폴트가 발생했다.
- `NUM_CHANS=64`는 다시 실행 가능했다.
- 따라서 지금 단계에서 채널 수 변수는 단순히 성능 숫자만 바꾸는 변수가 아니라, 실행 안정성 자체를 흔드는 변수다.

## 8. 다음 단계

1. 세그폴트 원인을 확인한다.
2. benchmark가 낮은 채널 수에서 어떤 배열 크기나 인덱스를 가정하는지 찾는다.
3. 채널 수 실험을 제대로 하려면 추가 수정이 필요한지 판단한다.
4. 그 다음 병목 정리와 설계 변경 판단으로 넘어간다.

## 9. 한 줄 요약

이번 실험에서 `NUM_CHANS`를 1과 16으로 줄이면 benchmark가 세그폴트로 깨졌고, 64채널로 복귀하면 다시 실행되었다.  
즉, 현재 시뮬레이터는 낮은 채널 수 구성에 아직 안정적으로 대응하지 못한다.

