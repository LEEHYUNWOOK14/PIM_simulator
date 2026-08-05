# Logic-die output retirement 설계 계약 초안

## 배경

현재 pointwise GEMV는 각 spatial position마다 결과를 GRF에서 bank로 writeback하고,
logic PIM을 HAB에서 SB로 전환한 뒤 bank READ로 결과를 회수한다. 이 때문에 Project
196 positions에서 mode/control/writeback barrier가 반복된다.

## 필요한 구조

Logic-die PIM이 mode를 유지한 채 다음 position을 처리하려면 별도 output retirement
경로가 필요하다.

| 구성요소 | 역할 |
|---|---|
| Output buffer | Logic PCU의 reduction 결과를 tile ID와 함께 임시 저장 |
| Completion queue | 완료된 `(layer, position, channel tile)` 순서를 기록 |
| Drain engine | HBM bank 또는 host readback 버퍼로 결과를 비동기 배출 |
| Dependency scoreboard | 다음 연산이 요구하는 tile의 drain 완료 여부를 추적 |
| Backpressure | Output buffer가 가득 차면 새 logic compute 발행을 중지 |

## 필수 신호

```text
logic_result_valid
logic_result_tile_id
logic_result_data
output_buffer_ready
drain_valid
drain_tile_id
drain_done
consumer_wait_tile_id
```

## 불변식

1. 같은 tile ID의 결과는 덮어쓰기 전에 output buffer 또는 HBM으로 retirement되어야 한다.
2. Consumer는 해당 tile의 `drain_done` 전에는 읽을 수 없다.
3. Mode 전환 없이 결과를 회수하려면 기존 bank READ와 다른 output-buffer READ가 필요하다.
4. Buffer full에서는 compute를 멈추되 이미 발행된 drain은 계속 진행해야 한다.
5. Source queue OFF bank-side PIM 경로는 이 구조를 사용하지 않는다.

## 시뮬레이터 다음 구현

첫 단계는 2-entry output buffer와 tile ID scoreboard다. 각 pointwise position 결과를
buffer entry에 저장하고, 기존 `readResult()`는 해당 entry의 완료를 기다린 뒤 읽는다.
이 경로가 검증된 후에만 position 사이 HAB context residency를 다시 활성화한다.

## 현재 구현 상태

- `LogicDieOutputBuffer` 2-entry 구조 구현 완료
- `(layer, position, channelTile)` scoreboard 구현 완료
- Burst valid bitmap과 tile ready 판정 구현 완료
- FIFO retirement와 full backpressure 통계 구현 완료
- Pointwise readback 결과가 buffer를 통과하도록 통합 완료
- 전체 UIB에서 392 tile reserve/retire 및 18,816개 정확도 검증 완료

현재는 `runPIM()` 완료 후 producer가 두 entry를 채우고, 세 번째 reserve의 full
backpressure에서 consumer가 oldest tile을 retire하는 sliding window를 구현했다. 전체
UIB에서 peak occupancy 2와 388회 backpressure가 검증됐다. 다음 단계에서는 이 상태
진행을 compute completion callback과 drain cycle에 연결해 시간축 중첩을 활성화해야 한다.
