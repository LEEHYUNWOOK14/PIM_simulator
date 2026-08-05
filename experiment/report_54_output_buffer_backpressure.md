# Logic-die output buffer backpressure 통합 보고서

## 1. 목적

1차 output buffer 통합은 tile을 하나씩 즉시 retire해 peak occupancy가 1이었다. 이번
단계에서는 2-entry producer와 FIFO consumer를 분리하고 full backpressure 경로를 전체
MobileNetV4 UIB로 검증한다.

## 2. 구현

`readPointwiseSpatial()`에서 다음 sliding window를 사용한다.

```text
tile produce
  -> reserve entry
  -> 모든 burst write
  -> ready queue에 추가
  -> 다음 tile reserve

buffer full
  -> reserve 실패와 backpressure 기록
  -> oldest ready tile read/retire
  -> reserve 재시도
```

다른 layer나 duplicate 때문에 reserve가 실패한 경우에는 buffer가 full이 아니므로 즉시
오류 처리한다. Capacity backpressure와 잘못된 요청을 구분한다.

## 3. 예상값

각 pointwise layer는 196 positions다. Capacity가 2이므로 처음 두 tile 이후 나머지
194 tile이 각각 한 번 full을 만난다. Expand와 Project 두 layer의 예상 full event는
`2 * (196 - 2) = 388`이다.

## 4. 재현 명령

```bash
./sim --gtest_filter=LogicDieOutputBufferTest.*
HIERARCHY_SOURCE_QUEUES=true bash experiment/run_hierarchy_shared_drain.sh
bash experiment/run_source_queue_stall_breakdown.sh
```

## 5. 결과

| 항목 | 결과 |
|---|---:|
| 단위 테스트 | 3 PASS |
| MobileNetV4 출력 | 18,816 PASS |
| Reservations | 392 |
| Retirements | 392 |
| Full backpressure | 388 |
| Peak entries | 2 |
| 총 cycle | 247,342 |

모든 값이 예상과 일치했다. 마이크로 테스트도 출력 12개 PASS와 1,425 cycles를 유지했다.

## 6. 해석

Producer/consumer 상태와 2-entry backpressure는 기능적으로 검증됐다. 하지만 physical
pointwise 결과는 여전히 `runPIM()` 완료 후 buffer에 들어오므로 simulation cycle은
변하지 않는다. 이는 상태기계 검증이지 compute-drain 성능 중첩 결과가 아니다.

다음 단계는 PIM command stream의 position 완료 지점에서 producer callback을 발생시키고,
drain consumer에 별도 latency/bandwidth를 부여하는 것이다. 그 후 buffer full stall을
실제 scheduler cycle에 반영하고 HAB context residency를 다시 시험해야 한다.
