# 87차 실험 보고서: 64채널 FP16 누산과 dual-link 통합 timed replay

## 1. 실험 목적

86차까지는 실제 FP16 값의 누산과 64채널 link arbitration을 서로 다른 testbench로
검증했다. 이번 실험은 `logic_die_64ch_reduction_top.sv` 안에서 다음 경로를 하나로
연결하는 것이 목적이다.

```text
실제 C++ arrival cycle
→ 64 channel × 8 PIM block source FIFO
→ key/slot 기반 FP16 reduction
→ channel별 8→1 arbiter
→ logic-die 64→2 global arbiter
→ 최종 key와 FP16 값 비교
```

## 2. RTL 변경

64채널 top에 `USE_INTERNAL_FP16` 파라미터를 추가했다.

| 값 | 동작 |
|---:|---|
| `0` | 기존 `add_result_i` 외부 datapath를 사용한다. 기존 test와 vendor IP 연결 호환성을 유지한다. |
| `1` | `fp16_add.sv`를 각 source의 lane에 내장해 reduction buffer가 실제 FP16 값을 누산한다. |

기본값은 `0`이므로 기존 top의 외부 인터페이스와 기본 elaboration은 바뀌지 않는다.
통합 test에서만 `1`로 설정한다.

## 3. 실제 timing 재생 방법

`logic_die_64ch_fp16_timed_payload_tb.sv`는 24,576행 payload trace를 먼저 읽는다.
각 행의 원래 `cycle`, `channel`, `pim_block`, `key`, `tap_index`, `partial_hex`를
보존한다. 원래 cycle이 되면 해당 512-source FIFO에 event를 넣고, DUT의
`update_ready`가 올라온 cycle에만 제거한다. 따라서 link가 막히면 source도 실제
valid/ready 규칙에 따라 기다린다.

최종 link에서 나온 key는 hash table로 C++ 기대 key를 찾고 FP16 payload와
bit 단위로 비교한다. 예상하지 않은 key, 누락된 key, protocol error, 값 불일치,
FIFO overflow가 하나라도 발생하면 즉시 실패한다.

## 4. 폭 검증을 두 test로 나눈 이유

Icarus Verilog에서 512 source × 16 FP16 lane, 총 8,192개 조합 가산기를 실제 약
14,000 cycle 동안 평가한 첫 실행은 15분 안에 끝나지 않았다. 검증 범위를 줄이는
대신 다음 두 test의 책임을 명확히 분리했다.

| test | 유지하는 범위 | 검증 결과 |
|---|---|---|
| `LOGIC_DIE_64CH_FP16_TIMED_PAYLOAD_TB` | 64 channel, 8 block/channel, 실제 arrival cycle, FIFO, reduction, 2단계 arbiter | 실제 lane 1개를 link 끝까지 검증 |
| `LOGIC_DIE_512SOURCE_FP16_PAYLOAD_TB` | 512 source, 16 FP16 lane, 24,576 partial, 8,192 final | 131,072개 final FP16 전부 검증 |

두 test는 같은 C++ trace를 사용한다. 첫 test가 topology와 timing을, 두 번째 test가
전체 256-bit datapath를 검증한다. 합성 가능한 production top은 여전히 16 lane을
지원하며, timed test만 실행 시간을 위해 `DATA_WIDTH=16`으로 elaboration한다.

## 5. 재현 명령

이미 생성한 trace로 전체 RTL 회귀를 실행한다.

```bash
bash experiment/run_fp16_payload_replay.sh rtl
```

C++ trace부터 다시 만들려면 다음 명령을 사용한다.

```bash
bash experiment/run_fp16_payload_replay.sh all
```

## 6. 실제 출력

```text
LOGIC_DIE_64CH_FP16_TIMED_PAYLOAD_TB PASS partials[24576] finals[8192] checked_lanes[1] full_cycles[4096] partial_cycles[0] replay_cycles[13880]
LOGIC_DIE_512SOURCE_FP16_PAYLOAD_TB PASS partials[24576] finals[8192] lanes[16] reference[C++ MobileNetV4]
LOGIC_DIE_64CH_REDUCTION_TOP ELABORATION PASS
LOGIC_DIE_DUAL_LINK_STRESS_TB PASS saturation_bursts[1024] saturation_bytes_per_cycle[64] random_bursts[1052]
```

## 7. 결과 해석

- `partials[24576]`: C++에서 발생한 모든 bank-local 3-tap partial이 RTL에 수락됐다.
- `finals[8192]`: key마다 partial 세 개가 모여 정확한 수의 final이 나왔다.
- `full_cycles[4096]`: final 두 개가 매 active cycle에 나와 `8192/2=4096`이 됐다.
- `partial_cycles[0]`: final drain 중 한 lane만 사용하는 cycle은 없었다.
- `replay_cycles[13880]`: 첫 arrival부터 마지막 drain까지 testbench handshake를 포함한 시간이다. C++ offline replay 13,878 cycle과의 2-cycle 차이는 reset 후 최초 valid 구동 및 마지막 관측 경계다.
- `lanes[16]`: 별도 wide test에서 final `8192×16=131072`개가 C++와 일치했다.

따라서 실제 MobileNetV4 arrival의 burstiness와 backpressure 아래에서도 FP16 누산
결과가 손상되지 않고 64채널 logic-die link를 통과한다.

## 8. 현재 결론과 다음 단계

이번 단계로 기능 관점의 계층형 경로는 다음 범위까지 연결됐다.

```text
Bank PIM 3-tap local aggregation
→ Logic-die FP16 3-partial reduction
→ 64-channel shared arbitration
→ 2×32 B/cycle final link
```

아직 `latency=1`, 16-lane 조합 가산기 수, 64 B/cycle link 폭이 물리적으로 가능한지는
입증하지 않았다. 다음 검증은 RTL 합성으로 lane당 cell 수와 critical path를 얻고,
16-lane·512-source 전체 복제 면적이 과도하면 공유 FP16 pipeline 수를 줄인 구조를
비교하는 것이다. 그 결과를 C++의 accumulator port와 latency에 다시 반영해야 한다.
