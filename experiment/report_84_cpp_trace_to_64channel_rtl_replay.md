# 84차 실험 보고서: C++ MobileNetV4 trace의 64채널 RTL replay

## 1. 목적

C++의 `LOGIC_ACCUMULATOR_BW=64`는 지금까지 byte 수를 64 B/cycle로 나눈 고정 최대폭 모델이었다. 실제 MobileNetV4 partial 도착이 충분히 조밀하지 않으면 RTL은 매 cycle 두 burst를 채우지 못한다. 이번 실험은 C++에서 실제 도착 trace를 추출하고 같은 trace를 64채널 RTL에 재생해 sustained bandwidth를 검증한다.

## 2. C++ trace 계측

Bank-local 9-tap 합이 완성되어 logic die로 flush되는 순간 다음 정보를 기록한다.

```text
cycle, channel, rank, pim_block, key
```

설정:

```ini
LOGIC_ACCUMULATOR_TRACE_FILE=experiment/results/depthwise_actual_arrival_trace.csv
```

원본 파일: `experiment/results/depthwise_actual_arrival_trace.csv`

## 3. 실제 trace 분포

| 항목 | 값 |
|---|---:|
| 전체 event | 8,192 |
| Channel | 64 |
| PIM block/channel | 8 |
| Distinct arrival cycles | 16 |
| Event/arrival cycle | 512 |
| 첫 arrival | 28,922 |
| 마지막 arrival | 29,055 |

한 wave는 `64 channels × 8 PIM blocks = 512 bursts`다. 총 16 wave가 도착한다. 첫 wave만으로도 2-lane global link를 256 cycle 동안 채울 수 있어 다음 wave가 오기 전에 queue가 비지 않는다.

## 4. C++ 2단계 arbitration replay

C++ `LogicDieAccumulator::replayTwoStageLink`는 다음 규칙을 사용한다.

1. Channel별 queue에 도착 event를 넣는다.
2. Channel 하나는 cycle당 burst 하나만 local arbiter로 보낸다.
3. Global round-robin arbiter는 서로 다른 channel에서 최대 두 burst를 보낸다.
4. 모든 queue가 빌 때까지 반복한다.

결과:

```text
link_replay_bursts[8192]
link_replay_cycles[4096]
link_replay_full_cycles[4096]
link_replay_partial_cycles[0]
link_replay_idle_cycles[0]
link_replay_completion_cycle[33017]
```

## 5. 64채널 RTL trace replay

`rtl/tb/logic_die_64ch_trace_replay_tb.sv`가 C++ CSV를 직접 읽는다. 각 `{channel, PIM block}` source에 pending queue를 만들고 실제 arrival 상대 cycle에 event를 넣는다. Source는 ready를 받을 때까지 valid를 유지한다.

실행:

```bash
bash rtl/run_tests.sh
```

결과:

```text
LOGIC_DIE_64CH_TRACE_REPLAY_TB PASS
bursts[8192]
full_cycles[4096]
bytes_per_active_cycle[64]
```

## 6. 결론

| 모델 | Bursts | Drain cycles | Full cycles | 평균 active bandwidth |
|---|---:|---:|---:|---:|
| C++ 2-stage replay | 8,192 | 4,096 | 4,096 | 64 B/cycle |
| 64-channel RTL replay | 8,192 | 4,096 | 4,096 | 64 B/cycle |

실제 14×14×192 depthwise trace에서는 source burst가 충분히 조밀해 C++의 고정 64 B/cycle이 RTL sustained bandwidth와 일치한다. 따라서 기존 depthwise 결과의 transfer service 4,096 cycle 가정은 이 workload에 대해 유지할 수 있다.

## 7. 제한

- 이번 결론은 MobileNetV4 14×14×192, factor 9, tile batch 1 trace에 대한 결과다.
- 다른 shape, channel 수, sparse workload에서는 link utilization이 낮아질 수 있다.
- C++ replay queue는 queue capacity를 제한하지 않았고 RTL testbench source pending도 testbench 자료구조다.
- 실제 FP16 adder pipeline과 physical TSV backpressure는 포함하지 않았다.

## 8. 다음 단계

1. 7×7, 28×28, 56×56 trace에서 link utilization을 비교한다.
2. Source queue depth를 1, 2, 4, 8, 16으로 제한해 overflow/backpressure를 검증한다.
3. FP16 adder latency를 넣어 arrival과 drain overlap을 다시 측정한다.
4. Trace 기반 평균값을 C++ transfer model에 선택적으로 반영한다.
