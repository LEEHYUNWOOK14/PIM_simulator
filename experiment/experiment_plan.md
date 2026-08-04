# 실험 계획서

## 1. 목적

이 문서는 현재 PIM 시뮬레이터에서 실험을 어떻게 진행할지 정리한 계획서다.

우선 목표는 다음 세 가지다.

1. 현재 bank-side PIM이 정상 동작하는지 확인한다.
2. 설정 파일을 바꿨을 때 결과가 어떻게 달라지는지 본다.
3. 나중에 MobileNetV4로 확장할 때 기준이 되는 실험 습관을 만든다.

## 2. 첫 실험은 무엇부터 할까

가장 먼저 할 실험은 `PIMKernelFixture.add`이다.

이유는 다음과 같다.

- 이미 정확도 테스트가 통과한 경로라서 기준선으로 쓰기 좋다.
- element-wise 연산이라 결과 해석이 쉽다.
- 설정을 조금 바꿨을 때 변화가 비교적 빨리 드러난다.
- 이후 `RELU`, `MUL`, `GEMV`로 확장하기 전에 가장 기본적인 검증이 된다.

## 3. 실험 순서 전체

### 3.1 1차 실험

- `PIMKernelFixture.add`
- `PIMBenchFixture.add`

목적:

- 정확도 확인
- 성능 기준 확인
- baseline 확보

### 3.2 2차 실험

- `PIMKernelFixture.relu`
- `PIMBenchFixture.relu`

목적:

- activation 경로 확인
- element-wise 후처리 동작 확인

### 3.3 3차 실험

- `PIMKernelFixture.mul`
- `PIMBenchFixture.mul`

목적:

- 산술 경로 확인
- ADD보다 조금 더 복잡한 연산이 정상인지 확인

### 3.4 4차 실험

- `PIMKernelFixture.gemv`
- `PIMKernelFixture.gemv_tree`
- `PIMBenchFixture.gemv`

목적:

- projection 계열 확장 기준 확인
- partial sum과 reduction 흐름 확인

## 4. 실험을 어떻게 진행할까

실험은 항상 아래 형태로 진행한다.

1. 설정 파일을 연다.
2. 바꿀 변수를 하나만 정한다.
3. 값을 수정한다.
4. 저장한다.
5. `./sim --gtest_filter=...`로 다시 실행한다.
6. 결과를 기록한다.
7. baseline과 비교한다.

## 5. 첫 실험 상세 절차

### 5.1 `PIMKernelFixture.add` 정확도 실험

1. `system_hbm.ini` 파일을 연다.
2. `PIM_PRECISION`을 `FP16`으로 유지한다.
   - 기대효과: 현재 기준과 같은 정밀도를 유지해서 결과 비교가 쉬워질 것이다.
3. `ADDRESS_MAPPING_SCHEME`을 `Scheme8`으로 유지한다.
   - 기대효과: PIM 주소 매핑이 기존 기준과 같아서 결과가 흔들리지 않을 것이다.
4. `DEBUG_CMD_TRACE`를 `true`로 둔다.
   - 기대효과: 명령이 어떻게 흘러가는지 확인할 수 있을 것이다.
5. 터미널에서 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMKernelFixture.add
```

6. 출력에서 `passed`와 `failed`를 확인한다.
   - 기대효과: `passed : 1048576`, `failed : 0`이면 현재 ADD 경로가 정상이라는 뜻이다.
7. 결과를 실험 기록표에 적는다.
   - 기대효과: 나중에 설정을 바꿨을 때 비교 기준이 생길 것이다.

### 5.2 `PIMBenchFixture.add` 성능 실험

1. `system_hbm.ini` 파일을 연다.
2. `PRINT_CHAN_STAT`를 `true`로 바꾼다.
   - 기대효과: 채널별 통계를 볼 수 있어서 성능 변화 원인을 찾기 쉬워질 것이다.
3. `PRINT_MEM_TRACE`를 `false`로 둔다.
   - 기대효과: 출력이 너무 길어지는 것을 막고, 성능 수치에 집중할 수 있을 것이다.
4. `DEBUG_CMD_TRACE`는 처음에는 `false`로 둔다.
   - 기대효과: trace가 너무 길어지는 것을 막고 성능 결과를 읽기 쉽게 만들 것이다.
5. 터미널에서 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMBenchFixture.add
```

6. `PIM disabled Cycle`, `PIM enabled Cycle`, `Speed-up`를 확인한다.
   - 기대효과: PIM이 실제로 어느 정도 빨라졌는지 숫자로 확인할 수 있을 것이다.
7. `Speed-up`이 2.0보다 조금 낮게 나오면, 성능 오버헤드가 어디서 생기는지 다음 실험에서 추적한다.
   - 기대효과: 어떤 설정이 성능에 영향을 주는지 점점 좁혀갈 수 있을 것이다.

## 6. 다음에 해볼 실험

### 6.1 `RELU`

1. `./sim --gtest_filter=PIMKernelFixture.relu`를 실행한다.
2. `passed`와 `failed`를 확인한다.
   - 기대효과: activation 경로도 ADD처럼 안정적인지 확인할 수 있을 것이다.
3. `PIMBenchFixture.relu`로 성능도 확인한다.
   - 기대효과: 단순 activation에서 PIM 이득이 어느 정도인지 볼 수 있을 것이다.

### 6.2 `MUL`

1. `./sim --gtest_filter=PIMKernelFixture.mul`를 실행한다.
2. 정확도가 통과하면 산술 경로를 기준선으로 삼는다.
   - 기대효과: ADD보다 약간 복잡한 element-wise 연산도 정상이라는 근거가 생길 것이다.
3. `PIMBenchFixture.mul`을 실행한다.
   - 기대효과: 산술 연산에서 cycle이 어떻게 달라지는지 볼 수 있을 것이다.

### 6.3 `GEMV`

1. `./sim --gtest_filter=PIMKernelFixture.gemv`를 실행한다.
2. `./sim --gtest_filter=PIMKernelFixture.gemv_tree`를 실행한다.
3. `./sim --gtest_filter=PIMBenchFixture.gemv`를 실행한다.
   - 기대효과: projection 계열과 reduction 구조를 함께 확인할 수 있을 것이다.

## 7. 실험할 때 바꿔볼 변수

### 7.1 먼저 바꿔볼 변수

- `NUM_CHANS`
- `PIM_PRECISION`
- `ADDRESS_MAPPING_SCHEME`
- `DEBUG_CMD_TRACE`
- `PRINT_CHAN_STAT`
- `PRINT_MEM_TRACE`

이 변수들은 비교적 해석이 쉽고, 결과를 읽는 데 바로 도움이 된다.

### 7.2 나중에 바꿔볼 변수

- `ROW_BUFFER_POLICY`
- `SCHEDULING_POLICY`
- `QUEUING_STRUCTURE`
- `TRANS_QUEUE_DEPTH`
- `CMD_QUEUE_DEPTH`
- `NUM_BANKS`
- `NUM_BANK_GROUPS`
- `NUM_PIM_BLOCKS`

이 변수들은 성능에 큰 영향을 줄 수 있어서, 먼저 baseline을 잡은 뒤 바꾸는 것이 좋다.

## 8. 기록 방법

실험을 돌릴 때마다 아래 항목을 적는다.

- 날짜
- 실행한 테스트 이름
- 사용한 설정 파일
- 바꾼 변수 이름
- 바꾼 값
- 기대효과
- 실제 결과
- pass/fail 여부
- cycle 또는 speed-up
- 특이사항

## 9. 추천 실험 노트 형식

```text
실험명:
설정 파일:
변수 변경:
기대효과:
실제 결과:
판정:
메모:
```

## 10. 결론

첫 실험은 `PIMKernelFixture.add`와 `PIMBenchFixture.add`로 시작한다.  
그 다음 `RELU`, `MUL`, `GEMV` 순으로 확장한다.  
처음에는 변수 하나씩만 바꾸고, 결과를 baseline과 비교하는 방식으로 가는 것이 가장 안전하다.



