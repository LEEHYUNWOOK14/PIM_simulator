# 30차 실험 보고서: 채널별 온라인 큐 역압력과 PCU 병목 중첩

## 1. 실험 목적

온라인 broadcast-mask queue가 가득 찼을 때 어느 stream의 명령 발행이 멈추는지, 그 정지가 실제 총 실행시간을 늘리는 critical-path 병목인지 확인한다.

## 2. 재현 명령

프로젝트 루트의 WSL 터미널에서 다음 명령을 실행한다.

```bash
DEPTH_LIST="32 64 128" \
ONLINE_QUEUE_BACKPRESSURE=true \
RESULT_FILE=experiment/results/channel_backpressure_distribution.csv \
bash experiment/run_broadcast_queue_depth_sweep.sh
```

단위 테스트는 다음과 같이 실행한다.

```bash
scons -j4
./sim --gtest_filter='LogicDieSchedulerTest.*'
```

## 3. 설정

| 항목 | 값 |
|---|---:|
| workload | MobileNetV4 UIB 14, expand 96→192 + project 192→96 |
| HBM channel | 64 |
| rank/channel | 2 (workload stream은 rank 0 사용) |
| weight fill policy | `row_interleaved` |
| weight fill channel | 32 |
| epoch release | `true` |
| online backpressure | `true` |
| queue depth | 32, 64, 128 |

## 4. 결과

| Depth | 막힌 channel-cycle | PCU busy와 겹친 channel-cycle | 막힌 wall-cycle | 막힌 stream 수 | stream별 정지 범위 | 총 cycle |
|---:|---:|---:|---:|---:|---:|---:|
| 32 | 7,513 | 7,513 | 291 | 32 | 225~290 | 214,228 |
| 64 | 211 | 211 | 53 | 4 | 52~53 | 214,228 |
| 128 | 0 | 0 | 0 | 0 | 0 | 214,228 |

`channel-cycle`은 한 cycle에 막힌 stream 수를 모두 더한 값이다. 따라서 depth 32의 평균 동시 정지 stream 수는 `7,513 / 291 = 25.82`, depth 64는 `211 / 53 = 3.98`이다.

| Depth | 정지가 기록된 stream ID |
|---:|---|
| 32 | 2, 6, 10, 14, ..., 62, 66, 70, 74, ..., 126 |
| 64 | 2, 6, 10, 14 |
| 128 | 없음 |

stream ID는 `channel * NUM_RANKS + rank`이다. 이 실행은 `NUM_RANKS=2`, rank 0 stream을 사용하므로 depth 32의 물리 채널은 홀수 채널 1, 3, ..., 63이고 depth 64는 채널 1, 3, 5, 7이다. 다른 rank 수로 실행하면 같은 비트 위치의 물리 채널 해석도 달라진다.

## 5. 출력값 읽는 법

```text
logic_online_issue_blocked_channel_cycles[7513]
logic_online_issue_busy_overlap_channel_cycles[7513]
logic_blocked_wall_cycles[291]
logic_blocked_streams[32]
logic_blocked_stream_mask_low[4919131752989213764]
logic_blocked_stream_mask_high[4919131752989213764]
```

- `blocked_channel_cycles`: stream별 정지 cycle의 합이다. wall-clock 지연과 같지 않다.
- `busy_overlap_channel_cycles`: 정지 순간 logic PCU scheduler도 바빴던 channel-cycle이다.
- `blocked_wall_cycles`: 하나 이상의 stream이 정지한 서로 다른 simulator cycle 수다.
- `blocked_streams`: 한 번이라도 정지한 stream 수다.
- `blocked_stream_mask_low/high`: 정지 stream 0~63, 64~127을 각각 나타내는 64-bit 비트마스크다.
- `total_cycle`: 전체 workload 완료 시간이다. 본 실험에서는 세 depth가 모두 같다.

## 6. 분석

1. 정지 channel-cycle의 100%가 logic PCU busy 구간과 겹쳤다. queue가 명령을 잠시 막아도 PCU가 새 작업을 즉시 처리할 수 없었으므로 총 cycle은 증가하지 않았다.
2. 32-entry queue는 광범위한 stream에 압력을 만들지만 64-entry queue는 4개 stream에만 짧게 압력이 집중된다.
3. 128-entry에서는 관측 peak open mask 78개를 수용하여 정지가 없다.
4. MobileNetV4 UIB 14의 성능 최소 후보는 64 entries다. 32 entries도 현재 총 cycle은 같지만 workload나 PCU 수가 바뀌면 숨겨진 정지가 critical path로 이동할 위험이 크다.
5. RTL 1차 안전 사양은 128 entries, 면적 절감 후보는 64 entries로 유지한다. 최종 선택은 다른 MobileNetV4 pointwise shape와 PCU/BW sweep 후 결정한다.

## 7. 검증 결과

- `LogicDieSchedulerTest.*`: 9개 모두 통과
- MobileNetV4 expand/project 수치 정확도: 통과
- incomplete expected mask: 모든 depth에서 0
- 결과 CSV: `experiment/results/channel_backpressure_distribution.csv`

## 8. 다음 실험

다음은 MobileNetV4의 서로 다른 pointwise 입력/출력 채널 및 공간 크기를 사용해 peak open mask, blocked wall-cycle, total cycle을 비교한다. 이 실험으로 64-entry 후보가 UIB 14 한 사례에만 맞춘 값인지 확인한다.
