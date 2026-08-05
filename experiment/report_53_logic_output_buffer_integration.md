# Logic-die output buffer 1차 통합 보고서

## 1. 목적

Project context residency 실험에서 확인된 결과 덮어쓰기와 retirement 문제를 해결하기
위해 2-entry logic-die output buffer와 tile scoreboard를 구현한다.

## 2. 구현 구조

`src/LogicDieOutputBuffer.h`에 다음 기능을 추가했다.

| 기능 | 구현 |
|---|---|
| Tile ID | `(layer, position, channelTile)` |
| Capacity | 2 entries |
| Burst 추적 | Entry별 valid bitmap과 완료 burst 수 |
| Ready | 모든 예상 burst가 기록되면 ready |
| Retirement | 예약 순서의 FIFO retirement |
| Backpressure | Full 상태에서 reserve 거절 및 stall 카운트 |
| 통계 | reservations, writes, completed, retirements, full stalls, peak entries |

MultiChannelMemorySystem이 buffer를 공유 소유하고, Pointwise handle마다 layer generation을
부여한다. `readPointwiseSpatial()`은 기존 physical output을 buffer에 기록한 뒤 buffer에서
읽은 값으로 최종 fp16 reduction 결과를 만든다.

## 3. 단위 테스트

```bash
./sim --gtest_filter=LogicDieOutputBufferTest.*
```

세 테스트가 모두 통과했다.

1. Burst가 순서와 다르게 도착해도 tile 완료 후 FIFO retirement한다.
2. 2개 entry가 찬 상태에서 세 번째 reserve를 거절하고 full stall을 기록한다.
3. 미완료 tile read와 다른 layer tile reserve를 거절한다.

## 4. 전체 UIB 검증

```bash
bash experiment/run_source_queue_stall_breakdown.sh
```

| 항목 | 결과 |
|---|---:|
| MobileNetV4 출력 | 18,816 PASS |
| Tile reservations | 392 |
| Tile retirements | 392 |
| Full stalls | 0 |
| Peak entries | 1 |
| 총 cycle | 247,342 |

Expand 196 positions와 Project 196 positions가 모두 output buffer를 통과했다. 통합 전후
cycle이 같으므로 이번 단계는 기능적 데이터 경로와 scoreboard 검증이며 아직 성능 모델을
바꾸지 않는다.

## 5. 해석과 다음 단계

이 보고서의 1차 결과 이후 2-entry producer/consumer sliding window를 구현했다. 최신
결과는 `experiment/report_54_output_buffer_backpressure.md`에 기록했다. 시간축 compute/drain
overlap을 만들려면 다음 변경이 필요하다.

1. Logic compute completion 시점에 tile entry를 reserve/write한다.
2. 다음 position compute는 빈 entry가 있으면 즉시 발행한다.
3. Host/HBM drain consumer는 별도로 ready tile을 FIFO retire한다.
4. 두 entry가 모두 차면 scheduler에 backpressure를 전달한다.
5. 이 비동기 경로가 동작한 뒤에만 HAB context residency를 다시 적용한다.
