# 38차 실험 보고서: Pointwise spatial row session

## 1. 실험 목적

Logic-die pointwise 연산을 전체 feature map 단위가 아니라 연속된 행 범위로 나누어 실행한다. 하나의 세션이 전체 출력 배열과 진행 행을 보존하고, 여러 번의 행 실행 결과가 전체 CPU reference와 같은지 검증한다.

## 2. 추가한 API

```cpp
auto session = pim.beginPointwiseSpatialSession(
    weights, input, height, width, outputChannels);

pim.enqueuePointwiseRows(session, 0, 2);
pim.waitPointwiseRows(session);
auto firstRows = pim.readPointwiseRows(session);

pim.enqueuePointwiseRows(session, 2, 1);
pim.waitPointwiseRows(session);
auto lastRow = pim.readPointwiseRows(session);
```

`session->output`에는 완료된 행 결과가 원래 공간 순서대로 누적된다. `session->nextRow`는 다음에 제출해야 하는 행 번호다.

## 3. 상태와 오류 계약

| 요청 | 결과 |
|---|---|
| `nextRow`부터 시작하는 1개 이상의 행 | 허용 |
| 이전 행 범위가 active인 상태의 추가 enqueue | `logic_error` |
| 이미 처리한 행 또는 건너뛴 행부터 enqueue | `invalid_argument` |
| 높이를 넘어가는 행 범위 | `invalid_argument` |
| active 범위가 없을 때 wait/read | `logic_error` |
| read 완료 | 출력 누적, `nextRow` 증가, active handle 해제 |

이 계약은 행 의존성을 명시적으로 보존한다. 현재는 한 세션에서 동시에 한 행 범위만 active일 수 있다.

## 4. 재현 명령

저장소 루트의 WSL 터미널에서 다음 명령을 실행한다.

```bash
bash experiment/run_nonblocking_pointwise_test.sh
```

스크립트는 빌드 후 기본 handle, depthwise halo 연결, row session 테스트를 실행하고 다음 CSV를 갱신한다.

```text
experiment/results/nonblocking_pointwise_test.csv
```

## 5. 출력 예시

```text
session_height  session_width  session_row_ranges  session_completed_rows  session_outputs_checked  session_total_cycle
3               4              2                   3                       36                       2770
```

각 열의 의미는 다음과 같다.

| 열 | 측정값 | 해석 |
|---|---:|---|
| `session_height` | 3 | 입력 feature map의 행 수 |
| `session_width` | 4 | 한 행의 spatial position 수 |
| `session_row_ranges` | 2 | `0~1행`, `2행`의 두 범위로 실행 |
| `session_completed_rows` | 3 | 전체 3행 완료 |
| `session_outputs_checked` | 36 | `3×4×3` 출력을 CPU reference와 비교 |
| `session_total_cycle` | 2,770 | 두 행 범위의 준비, 실행, read를 모두 포함 |

테스트 종료의 `[ PASSED ]`와 `outputs_checked[36]`을 함께 확인해야 한다. Cycle만 출력되더라도 정확도 검증 실패가 있으면 유효한 성능 결과가 아니다.

## 6. 정확도 결과

- 입력 형상: `3×4×3`
- Pointwise weight: `3 input × 3 output`
- 실행 분할: 첫 2행 + 마지막 1행
- 비교 출력: 36개
- 실패 출력: 0개
- 테스트 결과: 통과

따라서 행 범위를 나누더라도 결과 위치와 채널 순서가 전체 pointwise reference와 일치한다.

## 7. 함께 수행된 회귀 결과

| 검증 | 주요 결과 |
|---|---|
| 기본 nonblocking handle | 6개 출력 통과, 864 cycle |
| Expand→depthwise halo | 앞 2개 output row의 5,376개 출력 통과, 37,478 cycle |
| Pointwise row session | 36개 출력 통과, 2,770 cycle |

## 8. 현재 한계

행 범위마다 기존 `enqueuePointwiseSpatialGroups`를 다시 호출하므로 shared weight layer 준비와 fill이 반복된다. 즉, 세션이 weight를 보관하지만 아직 하드웨어 weight-buffer resident 상태를 재사용하지는 않는다. 또한 한 범위가 read될 때까지 다음 범위를 enqueue할 수 없어 logic pointwise와 bank-side depthwise의 실제 중첩도 아직 발생하지 않는다.

이번 2,770 cycle은 분할 API의 정확도 기준값이지 최적화된 pipeline 성능값이 아니다.

## 9. 다음 구현

1. 세션 시작 시 weight/CRF를 한 번만 준비하고 이후 행 범위에서 재사용한다.
2. 행 범위별 completion token과 partial readback을 명시한다.
3. 최소 3행 activation line buffer를 추가한다.
4. 준비된 expand 행을 소비하는 동안 다음 행을 제출하는 wavefront scheduler를 구현한다.
5. 순차 기준 214,228 cycle과 실제 overlap 결과를 비교한다.
