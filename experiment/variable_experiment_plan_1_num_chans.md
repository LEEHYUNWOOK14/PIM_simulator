# 변수 실험 1차 계획서

## 1. 목적

이 문서는 설정 파일의 실험변수를 바꿔가며 시뮬레이터 결과가 어떻게 달라지는지 확인하기 위한 1차 계획서다.

이번 1차 실험의 핵심 변수는 `NUM_CHANS`다.

왜 이 변수를 먼저 보느냐면:

- 채널 수는 성능 변화가 가장 직관적으로 보인다.
- 1채널, 16채널, 64채널 비교가 명확하다.
- bank 병렬성과 메모리 컨트롤러 부하를 동시에 볼 수 있다.
- 이후 다른 변수(`PIM_PRECISION`, `ADDRESS_MAPPING_SCHEME`, `ROW_BUFFER_POLICY`)를 볼 때 기준점이 된다.

## 2. 이번 실험에서 바꿀 변수

### 2.1 주 변수

- `NUM_CHANS`

### 2.2 고정할 변수

이번 1차 실험에서는 나머지 조건을 최대한 고정한다.

- `PIM_PRECISION=FP16`
- `ADDRESS_MAPPING_SCHEME=Scheme8`
- `ROW_BUFFER_POLICY=open_page`
- `SCHEDULING_POLICY=rank_then_bank_round_robin`
- `QUEUING_STRUCTURE=per_rank`

이렇게 해야 채널 수 변화만 분리해서 볼 수 있다.

## 3. 실험군

| 실험군 | 설정 파일 | `NUM_CHANS` | 목적 |
|---|---|---:|---|
| 기준군 | `system_hbm_1ch.ini` | 1 | 가장 단순한 단일 채널 기준 |
| 기본군 | `system_hbm.ini` | 16 | 현재 프로젝트의 표준 기준 |
| 병렬군 | `system_hbm_64ch.ini` | 64 | 최대 병렬성 비교 기준 |

## 4. 실험할 테스트

채널 수 실험은 정확도보다 성능 차이를 보는 것이 핵심이다.

따라서 다음 테스트를 우선 돌린다.

### 4.1 우선 테스트

- `PIMBenchFixture.add`
- `PIMBenchFixture.relu`
- `PIMBenchFixture.mul`
- `PIMBenchFixture.gemv`

### 4.2 선택 테스트

- `MemBandwidthFixture.hbm_read_bandwidth`
- `MemBandwidthFixture.hbm_write_bandwidth`

### 4.3 필요 시 추가

- `PIMKernelFixture.add`
- `PIMKernelFixture.relu`
- `PIMKernelFixture.mul`
- `PIMKernelFixture.gemv`
- `PIMKernelFixture.gemv_tree`

정확도는 이미 통과한 경로이므로, 변수 실험에서는 성능 중심으로 보는 편이 효율적이다.

## 5. 실험 순서

### 5.1 1단계: 1채널 기준선

1. `system_hbm_1ch.ini` 파일을 연다.
2. `NUM_CHANS=1`이 맞는지 확인한다.
   - 기대효과: 채널 병렬성이 거의 없는 가장 낮은 기준선을 만들 수 있을 것이다.
3. `PIM_PRECISION=FP16`을 유지한다.
   - 기대효과: 정밀도 변화가 섞이지 않아 채널 수 영향만 볼 수 있을 것이다.
4. 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

5. 출력의 `Cycle`과 `Speed-up`을 기록한다.
   - 기대효과: 단일 채널 기준의 baseline이 생길 것이다.

### 5.2 2단계: 16채널 기본군

1. `system_hbm.ini` 파일을 연다.
2. `NUM_CHANS=16`이 맞는지 확인한다.
   - 기대효과: 현재 프로젝트의 표준 동작을 확인할 수 있을 것이다.
3. 나머지 값은 가능한 한 그대로 둔다.
   - 기대효과: 채널 수가 1에서 16으로 늘어났을 때의 변화만 읽을 수 있을 것이다.
4. 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

5. 1채널 결과와 비교한다.
   - 기대효과: 채널 수 증가가 성능에 주는 실질적 효과를 볼 수 있을 것이다.

### 5.3 3단계: 64채널 병렬군

1. `system_hbm_64ch.ini` 파일을 연다.
2. `NUM_CHANS=64`가 맞는지 확인한다.
   - 기대효과: 가장 높은 채널 병렬성을 갖는 비교군을 얻을 수 있을 것이다.
3. `PRINT_CHAN_STAT=true`를 유지한다.
   - 기대효과: 채널별 분산이 성능에 어떻게 반영되는지 볼 수 있을 것이다.
4. 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

5. 16채널 결과와 비교한다.
   - 기대효과: 채널 수를 극단적으로 늘렸을 때 성능이 더 좋아지는지, 혹은 병목이 다른 곳으로 옮겨가는지 볼 수 있을 것이다.

## 6. 실험 시 기대하는 관찰 포인트

### 6.1 `Cycle`

- 채널 수가 많아지면 cycle이 줄어드는지 본다.
- 줄어들지 않으면 병목이 채널이 아니라 다른 곳에 있을 가능성이 있다.

### 6.2 `Speed-up`

- `NUM_CHANS=1`, `16`, `64` 사이에서 speed-up 차이를 본다.
- channel parallelism이 실제로 성능을 끌어올리는지 확인한다.

### 6.3 채널 통계

- `PRINT_CHAN_STAT=true`일 때 채널별 분산이 어떻게 보이는지 본다.
- 한두 개 채널에 몰리면 mapping이나 scheduling 쪽을 의심한다.

## 7. 실험 기록 방법

아래 항목을 실험마다 적는다.

- 실험군
- 사용한 설정 파일
- `NUM_CHANS`
- 테스트 이름
- `Cycle`
- `Speed-up`
- 채널 통계 요약
- 특이사항

## 8. 실험 노트 예시

```text
실험군: 1ch
설정 파일: system_hbm_1ch.ini
변수: NUM_CHANS=1
테스트: PIMBenchFixture.gemv
결과: Cycle = ...
해석: ...
메모: ...
```

## 9. 다시 돌릴 때 사용할 터미널 프롬프트

### 9.1 1채널

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

### 9.2 16채널

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

### 9.3 64채널

```bash
cd "/mnt/c/Users/Chandler/OneDrive/2026-하계/STOB 반도체 경진대회/STOB_PIM2"
./sim --gtest_filter=PIMBenchFixture.add
./sim --gtest_filter=PIMBenchFixture.relu
./sim --gtest_filter=PIMBenchFixture.mul
./sim --gtest_filter=PIMBenchFixture.gemv
```

각 실험군은 실행 명령은 같고, 열어두는 설정 파일만 다르다.

## 10. 결론

변수 실험 1차는 `NUM_CHANS` 하나만 바꿔서 1채널, 16채널, 64채널을 비교하는 것이다.

이 실험의 목적은:

- 채널 수가 성능에 실제로 얼마나 영향을 주는지 확인하는 것
- 이후 `PIM_PRECISION`, `ADDRESS_MAPPING_SCHEME`, `ROW_BUFFER_POLICY`로 넘어가기 위한 기준을 만드는 것

즉, 이번 단계는 “채널 병렬성이 성능을 어디까지 끌어올리는가”를 읽는 실험이다.

