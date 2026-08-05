# 39차 실험 보고서: Pointwise session weight residency

## 1. 실험 목적

`PointwiseSpatialSession`이 여러 행 범위를 실행할 때 logic-die shared weight buffer를 매번 초기화하고 채우던 동작을 제거한다. 첫 범위가 채운 weight를 이후 범위가 재사용하고, 정확도와 기존 전체 UIB 회귀가 유지되는지 검증한다.

## 2. 구현 내용

- 일반 pointwise enqueue와 session 재사용 enqueue를 내부 경로에서 구분했다.
- 첫 행 범위는 weight layer 생성, fill, ready barrier를 수행한다.
- 이후 행 범위는 buffer를 초기화하지 않고 resident weight를 읽는다.
- 새 행 범위마다 별도의 release epoch는 계속 생성한다.
- `LogicDieWeightBuffer`에 layer generation을 추가했다.
- 다른 연산이 buffer layer를 교체하면 session 재사용을 거부한다.
- Baseline/physical/saved weight byte 통계는 재사용 범위의 실제 전송 0 B를 반영한다.

## 3. 재현 명령

저장소 루트의 WSL 터미널에서 실행한다.

```bash
bash experiment/run_nonblocking_pointwise_test.sh
```

결과 CSV:

```text
experiment/results/nonblocking_pointwise_test.csv
```

## 4. 출력 예시와 해석

```text
session_row_ranges  session_reused_ranges  session_weight_fill_bursts  session_reused_fill_bursts  session_outputs_checked  session_total_cycle
2                   1                      512                         0                           36                       2672
```

| 열 | 값 | 의미 |
|---|---:|---|
| `session_row_ranges` | 2 | `2행 + 1행` 두 범위 실행 |
| `session_reused_ranges` | 1 | 두 번째 범위가 resident weight 사용 |
| `session_weight_fill_bursts` | 512 | 세션 전체에서 첫 범위만 발생시킨 fill |
| `session_reused_fill_bursts` | 0 | 재사용 범위에서 추가 fill 없음 |
| `session_outputs_checked` | 36 | CPU reference와 비교한 전체 출력 |
| `session_total_cycle` | 2,672 | 두 범위의 준비, 실행, read 총 cycle |

핵심 통과 조건은 `session_reused_fill_bursts=0`, 출력 36개 일치, Google Test `[ PASSED ]`의 세 가지다.

## 5. 전후 비교

| 모델 | 총 cycle | 차이 |
|---|---:|---:|
| 38차: 행 범위마다 weight fill | 2,770 | 기준 |
| 39차: session weight residency | 2,672 | -98 (-3.54%) |

작은 `3×4×3` 형상이므로 절감량 자체보다 두 번째 범위의 fill이 0이라는 기능 검증이 중요하다. 실제 MobileNetV4 형상에서는 행 분할 크기와 fill 크기를 함께 sweep해야 한다.

## 6. 정확도 및 회귀

| 테스트 | 결과 |
|---|---|
| 기본 nonblocking pointwise | 6개 출력 통과, 864 cycle |
| Expand→bank depthwise halo | 5,376개 출력 통과, 37,478 cycle |
| Row session weight reuse | 36개 출력 통과, 2,672 cycle |
| 전체 MobileNetV4 UIB | 18,816개 출력 통과, 214,228 cycle |

전체 UIB는 기존 blocking API를 사용하므로 cycle과 traffic 통계가 이전 기준값과 동일하다. 내부 함수 분리가 기존 경로에 회귀를 만들지 않았다는 증거다.

## 7. Layer generation 보호

`beginLogicWeightLayer`가 호출될 때마다 generation이 증가한다. Session은 첫 fill 직후 generation을 저장하고, 재사용 전에 현재 값과 비교한다. 값이 다르면 다른 연산이 shared buffer를 교체한 것이므로 `logic_error`를 발생시킨다. 이는 서로 다른 weight를 같은 주소로 잘못 읽는 silent corruption을 방지한다.

## 8. 현재 한계

Weight는 재사용하지만 `executeGemv`가 각 spatial position에서 CRF programming과 mode 전환을 반복한다. 따라서 이번 결과를 weight+CRF 전체 residency로 해석하면 안 된다. 또한 다음 행 범위는 이전 범위를 wait/read한 뒤에만 enqueue할 수 있어 logic/bank 실제 overlap은 아직 없다.

## 9. 다음 구현

1. Channel group별 CRF generation과 resident 상태를 추적한다.
2. 같은 pointwise 명령을 사용하는 group의 중복 CRF programming을 제거한다.
3. 3행 line buffer와 row completion token을 구현한다.
4. Expand 다음 행과 bank-side depthwise 준비 행을 동시에 발행한다.
5. 순차 UIB 214,228 cycle 대비 실제 overlap을 측정한다.
