# 90차 실험 보고서: 실제 64채널 trace의 shared pipeline 1·2·4 비교

## 1. 목적

89차에서는 합성 traffic으로 8-source shared scheduler를 검증했다. 이번 실험은
MobileNetV4 `14×14×192` depthwise에서 실제 발생한 24,576개 partial arrival을
사용해 channel당 pipeline 1·2·4개의 차이를 측정한다.

검증은 두 단계다.

1. 64채널 전체 cycle replay로 FIFO, scheduler stall, final dual-link를 분석한다.
2. 실제 channel 0 payload를 RTL shared cluster와 8→1 link에 넣어 FP16 값을 비교한다.

## 2. 64채널 replay 모델

`experiment/analyze_shared_pipeline_trace.py`는 CSV의 cycle, channel, PIM block,
key, tap index를 그대로 읽는다. 각 channel은 8개의 source FIFO, source별 final slot,
round-robin scheduler, 8→1 local link를 갖는다. logic die global link는 channel final을
cycle당 최대 두 개 배출한다.

한 cycle의 순서는 다음과 같다.

1. 해당 cycle의 partial arrival을 source FIFO에 넣는다.
2. 기존 final slot을 local 8→1 및 global 64→2 arbiter로 배출한다.
3. channel마다 최대 `PIPELINES`개의 eligible source update를 처리한다.
4. 세 번째 partial이 끝나면 다음 cycle부터 final slot이 valid가 된다.
5. final slot이 차 있으면 같은 source의 다음 last update에 backpressure를 건다.

재현 명령:

```bash
python3 experiment/analyze_shared_pipeline_trace.py
```

## 3. 64채널 결과

| Pipeline/channel | Replay cycle | Full link cycle | Idle link cycle | Peak source FIFO | Peak channel FIFO | Scheduler stall-source cycle | Final backpressure cycle |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 13,879 | 4,096 | 9,783 | 15 | 116 | 108,594 | 1,891,086 |
| 2 | 13,879 | 4,096 | 9,783 | 15 | 116 | 45,318 | 1,891,962 |
| 4 | 13,879 | 4,096 | 9,783 | 15 | 116 | 8,448 | 1,892,090 |

모든 후보가 partial 24,576개를 처리하고 final 8,192개를 만들었다. global dual-link는
final 두 개씩 4,096 full cycle에 배출했고 partial link cycle은 0이었다.

pipeline을 늘려도 전체 완료 cycle이 같은 이유는 scheduler보다 실제 arrival 간격과
final link/backpressure가 지배하기 때문이다. pipeline 4는 scheduler 대기를 크게
줄이지만 그 여유가 global completion 단축으로 이어지지 않는다.

이전 C++ arrival replay의 `24,576 burst`는 bank에서 logic die로 들어오는 partial을
link traffic으로 세었다. 이번 모델의 `8,192 final`은 logic-die reduction 이후
출력 link를 뜻한다. 두 숫자는 서로 다른 경계를 측정하므로 모순이 아니다.

## 4. 실제 channel RTL 경로

새 `shared_channel_reduction_path.sv`는 다음을 직접 연결한다.

```text
8 source FIFO 입력
→ shared_fp16_reduction_cluster
→ source별 final
→ logic_die_link_arbiter 8→1
```

`shared_channel_actual_trace_tb.sv`는 전체 trace에서 channel 0의 partial 384개와
final 128개를 추출한다. 실제 arrival cycle과 key/slot/tap 순서를 유지하며 link에서
나온 key와 FP16 값을 C++ 기대값과 bit 단위로 비교한다.

Icarus 실행 시간을 위해 timed path는 대표 FP16 lane 하나를 사용한다. 86·87차의
512-source wide test가 동일 trace의 16 lane 전체 131,072개 final 값을 별도로
검증하므로 수치 폭 검증은 유지된다.

재현 명령:

```bash
bash rtl/run_shared_trace_tests.sh
```

## 5. RTL 실제 결과

```text
SHARED_CHANNEL_ACTUAL_TRACE_TB PASS pipelines[1] partials[384] finals[128] peak_fifo[49] source_wait_cycles[9456] replay_cycles[9966] checked_lanes[1]
SHARED_CHANNEL_ACTUAL_TRACE_TB PASS pipelines[2] partials[384] finals[128] peak_fifo[42] source_wait_cycles[4562] replay_cycles[9966] checked_lanes[1]
SHARED_CHANNEL_ACTUAL_TRACE_TB PASS pipelines[4] partials[384] finals[128] peak_fifo[42] source_wait_cycles[2710] replay_cycles[9966] checked_lanes[1]
```

| Pipeline | Channel 0 peak FIFO | 누적 queued-request cycle | 완료 cycle |
|---:|---:|---:|---:|
| 1 | 49 | 9,456 | 9,966 |
| 2 | 42 | 4,562 | 9,966 |
| 4 | 42 | 2,710 | 9,966 |

pipeline 2는 pipeline 1보다 peak FIFO를 7개 줄이고 누적 대기를 51.8% 줄였다.
pipeline 4는 누적 대기를 더 줄이지만 peak와 완료 cycle은 개선하지 않았다.

## 6. 합성 결과와 결합한 판단

89차 channel-level cell proxy와 이번 trace를 함께 보면 다음과 같다.

| Pipeline | Channel cell proxy | 전용 8개 대비 절감 | Global completion | Channel 0 peak FIFO |
|---:|---:|---:|---:|---:|
| 1 | 368,153 | 48.29% | 13,879 | 49 |
| 2 | 436,915 | 38.63% | 13,879 | 42 |
| 4 | 578,780 | 18.70% | 13,879 | 42 |

현재 MobileNetV4 trace와 64 B/cycle link에서는 **pipeline 2개가 Pareto 기준 후보**다.

- pipeline 1보다 FIFO pressure가 작다.
- pipeline 4와 완료 cycle 및 peak FIFO가 같다.
- pipeline 4보다 channel cell proxy가 약 24.5% 작다.
- 32 B burst 두 개가 64 B/cycle link 폭과 정확히 대응한다.

## 7. 한계와 다음 단계

이 결론은 현재 depthwise trace 하나에 대한 후보 선정이다. pointwise GEMV와
depthwise가 logic-die pipeline을 동시에 요구하거나 다른 모델이 더 bursty하면
pipeline 4의 대기 감소가 의미를 가질 수 있다.

다음 단계에서는 MobileNetV4 UIB의 pointwise·depthwise·project가 연속 실행될 때
shared pipeline request를 하나의 trace로 수집해야 한다. 그 통합 trace에서 pipeline
2개의 queue가 overflow하지 않고 total cycle을 유지하는지 확인한 후 architecture
기준값으로 고정한다.
