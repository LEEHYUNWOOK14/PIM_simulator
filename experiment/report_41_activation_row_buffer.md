# 41차 실험 보고서: 3-row activation line buffer

## 1. 실험 목적

Logic-die pointwise가 완료한 행을 보관하고, 3×3 bank-side depthwise에 필요한 halo가 완성되는 순간 출력 행 completion token을 생성한다. 전체 expand feature map 완료를 기다리지 않는 wavefront 실행의 데이터 의존성 기반을 만든다.

## 2. 구현 구조

`src/ActivationRowBuffer.h`에 고정 행 buffer를 추가했다.

- 입력 행은 0번부터 연속해서 push한다.
- 3×3 kernel은 최대 3개 실제 activation 행만 보관한다.
- 위·아래 경계는 zero-padding 행으로 window를 구성한다.
- 다음 depthwise 출력에 필요한 마지막 입력 행이 완료되면 `canRelease()`가 true가 된다.
- 준비된 출력 행은 `release()`로 순서대로만 꺼낸다.
- 소비되지 않은 halo 때문에 3행이 모두 차면 새 입력에 backpressure를 발생시킨다.

## 3. 3×3 same-padding release 규칙

| 완료된 입력 행 | 새로 release 가능한 출력 행 |
|---|---|
| 입력 0행 | 없음 |
| 입력 0~1행 | 출력 0행 |
| 입력 0~2행 | 출력 1행 |
| 입력 0~3행 | 출력 2행, 마지막이면 출력 3행 |

출력 `y`에는 입력 `y-1`, `y`, `y+1`이 필요하다. 범위를 벗어난 행은 0으로 채운다.

## 4. 재현 명령

```bash
bash experiment/run_nonblocking_pointwise_test.sh
```

CSV 결과:

```text
experiment/results/nonblocking_pointwise_test.csv
```

## 5. 독립 buffer 결과

```text
buffer_input_rows  buffer_released_rows  buffer_kernel  buffer_peak_rows  buffer_values_checked
4                  4                     3              3                 27
```

- 입력 4행을 모두 연속 수신했다.
- 출력 행 token 4개를 모두 순서대로 release했다.
- 실제 resident activation은 최대 3행이었다.
- 상단, 중앙, 하단 window의 27개 값을 직접 비교했다.

## 6. Pointwise session 연결 결과

```text
session_completed_rows  session_released_depthwise_rows  session_line_buffer_peak_rows  session_outputs_checked
3                       3                                3                              36
```

첫 pointwise 범위의 2개 행을 read한 뒤 line buffer가 depthwise 출력 0행을 release했다. 마지막 pointwise 행을 넣은 뒤 출력 1행과 bottom-padding 출력 2행을 release했다. Pointwise 전체 출력 36개도 CPU reference와 일치했다.

## 7. 통과 조건

- 비연속 input row push 거부
- Halo 미완성 상태의 release 거부
- 상단과 하단 zero padding 정확성
- 최대 resident row ≤ kernel size 3
- Pointwise row token과 depthwise output token 순서 일치
- 기존 weight/CRF residency 정확도 유지

## 8. 현재 한계

Line buffer는 completion과 데이터 window를 제공하지만 bank-side depthwise 명령은 아직 기존 `executeDepthwiseLowered`를 사용한다. 이 함수는 MUL/ADD tap마다 `runPIM()`으로 전체 큐를 drain하므로 다음 logic pointwise 행과 실제 transaction overlap을 만들 수 없다. 이번 결과는 overlap 성능 결과가 아니라 overlap을 안전하게 시작할 데이터 의존성 검증이다.

## 9. 다음 구현

1. Depthwise lowered 연산을 stage handle로 분리한다.
2. `enqueueDepthwiseStage`와 `waitDepthwiseStage`를 제공한다.
3. 준비된 bank depthwise stage를 enqueue한다.
4. 다음 logic pointwise 행을 enqueue한다.
5. 한 drain 구간에서 두 source가 실제 발행되는지 source별 counter로 검증한다.
6. 순차 실행과 overlap 실행의 정확도·cycle을 비교한다.
