# 설계 변경 전 실험 계획표

## 1. 지금 다음에 할 실험

다음 실험은 `PIMBenchFixture.gemv`이다.

이유는 다음과 같다.

- `add`, `relu`, `mul`은 이미 정확도와 성능 기준선을 확보했다.
- `gemv`는 element-wise 연산보다 한 단계 복잡해서, 설계 변경 전에 반드시 한 번 더 확인해야 한다.
- `gemv_tree`까지 같이 보면 단순 연산과 reduction 계열을 함께 비교할 수 있다.
- MobileNetV4로 넘어가기 전에, 현재 시뮬레이터의 기본 연산 범위를 정리하기에 좋다.

---

## 2. 설계 변경 전 실험의 큰 흐름

설계를 바꾸기 전까지는 아래 순서로 진행한다.

1. 현재 기준 연산 검증
2. 현재 기준 성능 검증
3. 설정 파일 변수 1개씩 변경
4. 변경 전후 비교
5. 설계 바꿔야 할 이유를 데이터로 정리

이 순서를 지키면, 나중에 Verilog 구조를 바꿀 때도 “왜 바꿔야 하는지”가 분명해진다.

---

## 3. 실험 순서표

| 단계 | 실험 이름 | 목적 | 기준 파일 | 다음 판단 |
|---|---|---|---|---|
| 1 | `PIMKernelFixture.gemv` | 기본 GEMV 정확도 확인 | `system_hbm.ini` | 현재 연산 경로가 정상인지 확인 |
| 2 | `PIMKernelFixture.gemv_tree` | reduction 계열 확인 | `system_hbm.ini` | tree 방식이 정상인지 확인 |
| 3 | `PIMBenchFixture.gemv` | GEMV 성능 확인 | `system_hbm.ini` | speed-up 기준 확보 |
| 4 | 채널 수 변경 실험 | `NUM_CHANS` 영향 확인 | `system_hbm_1ch.ini`, `system_hbm.ini`, `system_hbm_64ch.ini` | 병렬성 영향 확인 |
| 5 | 메모리 동작 변수 실험 | 스케줄링/버퍼 정책 영향 확인 | `system_hbm.ini` | 성능 병목 원인 확인 |
| 6 | 주소 매핑 변수 실험 | address mapping 영향 확인 | `system_hbm.ini` | bank/chang conflict 원인 확인 |
| 7 | PIM 범위 비교 실험 | bank PIM과 logic PIM 구분 기준 확보 | 별도 실험 계획서 | 설계 변경 필요성 판단 |

---

## 4. 각 실험의 상세 수행 방법

### 4.1 `PIMBenchFixture.gemv`

1. `system_hbm.ini` 파일을 연다.
2. 기존 값은 그대로 두고, baseline 상태를 유지한다.
   - 기대효과: 현재 구조에서 GEMV가 어느 정도 성능을 내는지 기준점을 얻을 수 있다.
3. 터미널에서 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMBenchFixture.gemv
```

4. 출력에서 `PIM disabled Cycle`, `PIM enabled Cycle`, `Speed-up`을 기록한다.
   - 기대효과: GEMV에서 PIM이 실제로 유의미한 이득을 주는지 숫자로 확인할 수 있다.

### 4.2 `PIMKernelFixture.gemv`

1. `system_hbm.ini` 파일을 연다.
2. 설정은 바꾸지 않고 정확도 기준만 확인한다.
   - 기대효과: 성능을 보기 전에 연산 결과가 맞는지 먼저 확인할 수 있다.
3. 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMKernelFixture.gemv
```

4. `passed`와 `failed`를 확인한다.
   - 기대효과: GEMV 정확도가 현재 설정에서 정상인지 알 수 있다.

### 4.3 `PIMKernelFixture.gemv_tree`

1. `system_hbm.ini` 파일을 연다.
2. tree 방식의 동작이 현재 구조에서 맞는지 확인한다.
   - 기대효과: reduction 방식 경로까지 같이 검증할 수 있다.
3. 아래 명령을 실행한다.

```bash
./sim --gtest_filter=PIMKernelFixture.gemv_tree
```

4. 결과를 `gemv`와 비교한다.
   - 기대효과: tree 방식이 일반 GEMV와 어떻게 다른지 비교할 수 있다.

---

## 5. 변수 실험으로 넘어가는 조건

다음 조건이 만족되면 설정 변수 실험으로 넘어간다.

1. `add`, `relu`, `mul`, `gemv`, `gemv_tree`가 모두 정확도에서 통과한다.
2. `add`, `relu`, `mul`, `gemv`의 성능 결과가 기록된다.
3. `NUM_CHANS`를 바꿨을 때 결과를 비교할 baseline이 생긴다.
4. 실험 기록을 보고 어떤 변수가 중요한지 설명할 수 있다.

이 조건이 되면 “기본 기능 확인”이 끝난 것이고, 그다음부터는 본격적으로 변수를 흔들어 보는 단계다.

---

## 6. 설계 변경 전에 꼭 해볼 변수 실험

### 6.1 1차 변수 실험: `NUM_CHANS`

1. `system_hbm_1ch.ini`를 사용한다.
2. `NUM_CHANS=1`로 맞춘다.
   - 기대효과: 가장 단순한 기준점을 만들 수 있다.
3. `PIMBenchFixture.add`, `relu`, `mul`, `gemv`를 각각 실행한다.
   - 기대효과: 채널 수가 줄었을 때 성능이 어떻게 떨어지는지 확인할 수 있다.

### 6.2 2차 변수 실험: `NUM_CHANS=16`

1. `system_hbm.ini`를 사용한다.
2. `NUM_CHANS=16` 상태를 baseline으로 둔다.
   - 기대효과: 현재 기준 구조를 다시 확인할 수 있다.
3. 같은 네 개의 benchmark를 실행한다.
   - 기대효과: 1채널과 비교해서 병렬성이 얼마나 성능을 올리는지 볼 수 있다.

### 6.3 3차 변수 실험: `NUM_CHANS=64`

1. `system_hbm_64ch.ini`를 사용한다.
2. `NUM_CHANS=64`로 맞춘다.
   - 기대효과: 채널을 많이 늘렸을 때 성능이 더 좋아지는지 확인할 수 있다.
3. 같은 네 개의 benchmark를 실행한다.
   - 기대효과: 채널 확장의 한계나 병목을 볼 수 있다.

---

## 7. 설계를 바꾸기 전에 얻어야 하는 결론

설계를 바꾸기 전에 아래 질문에 답할 수 있어야 한다.

- 채널 수를 늘리면 실제로 성능이 얼마나 좋아지는가?
- `add`와 `relu` 같은 단순 연산은 이미 충분히 빠른가?
- `mul`과 `gemv`는 어디에서 병목이 생기는가?
- 지금 구조에서 해결되지 않는 병목이 정말 있는가?

이 질문에 답할 수 있으면, 그 다음에 로직 PIM을 추가할지, bank PIM과 어떻게 나눌지, 어떤 파라미터를 바꿔야 할지 훨씬 선명해진다.

---

## 8. 추천 다음 실행 순서

1. `PIMKernelFixture.gemv`
2. `PIMKernelFixture.gemv_tree`
3. `PIMBenchFixture.gemv`
4. `NUM_CHANS=1` 실험
5. `NUM_CHANS=16` 재확인
6. `NUM_CHANS=64` 확장 실험

이 순서가 끝나면, 그때부터는 설계를 바꾸는 실험 계획서로 넘어가면 된다.

