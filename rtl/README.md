# Hierarchical PIM RTL 초안

## 목적

이 폴더는 C++ cycle-level 모델에서 검증한 계층형 PIM 후보를 Verilog/SystemVerilog로 옮기기 위한 독립 RTL 작업공간이다. 아직 HBM PHY나 DRAM controller에 연결된 완성 칩 RTL은 아니다.

## 첫 모듈

`bank_local_reduction_buffer.sv`는 다음 C++ 후보를 표현한다.

- 8개 accumulator bank
- bank당 16 entry
- PIM block 하나를 accumulator bank 하나에 고정 연결
- bank당 cycle당 update 1개
- 총 128 live entry
- valid/ready backpressure
- `{slot, key}` 일치 검사
- 마지막 partial 수신 후 logic die 방향 final 출력

`logic_die_link_arbiter.sv`는 8개 bank의 final valid/ready를 하나의 공유 link로 모으는 32 B/cycle 기준 모듈이다. `logic_die_dual_link_arbiter.sv`는 두 개의 256-bit output lane으로 C++ 후보의 최대 64 B/cycle을 표현한다. `hierarchical_reduction_path.sv`는 reduction buffer와 dual arbiter를 연결한 통합 top-level이다.

`logic_die_64ch_reduction_top.sv`는 C++ 설정의 64 channel × 8 PIM block 전체를 표현한다. Channel마다 8→1 local arbiter를 두고 base logic die의 64→2 global arbiter가 결과를 받는다. 기본 64채널 elaboration과 축소 4채널 기능 test를 통과했다.

FP16 덧셈 자체는 `add_lhs_o`, `add_rhs_o`, `add_result_i`로 분리했다. 실제 RTL에서는 선택한 FP16 vector adder 또는 vendor IP를 연결하고, 합성 결과의 latency를 C++ `BANK_LOCAL_ACCUMULATOR_LATENCY`에 되돌려 넣어야 한다. 현재 testbench는 제어 흐름만 검증하기 위해 정수 덧셈을 사용한다.

## 필요한 도구

시스템 영역을 바꾸지 않고 사용자 홈에 Icarus Verilog를 설치하려면 다음 명령을 실행한다.

```bash
bash rtl/bootstrap_iverilog_local.sh
bash rtl/run_tests.sh
```

예상 성공 출력:

```text
BANK_LOCAL_REDUCTION_BUFFER_TB PASS
```

Icarus Verilog 12.0으로 두 모듈의 compile과 simulation을 실행해 다음 PASS를 확인했다.

```text
BANK_LOCAL_REDUCTION_BUFFER_TB PASS
LOGIC_DIE_64CH_REDUCTION_TOP_TB PASS
LOGIC_DIE_64CH_TRACE_REPLAY_TB PASS bursts[8192] full_cycles[4096] bytes_per_active_cycle[64]
HIERARCHICAL_REDUCTION_PATH_TB PASS
LOGIC_DIE_DUAL_LINK_STRESS_TB PASS saturation_bursts[1024] saturation_bytes_per_cycle[64] random_bursts[1052]
LOGIC_DIE_DUAL_LINK_ARBITER_TB PASS
LOGIC_DIE_LINK_ARBITER_TB PASS
LOGIC_DIE_64CH_REDUCTION_TOP ELABORATION PASS
```

이는 제어 모듈 testbench의 성공이며 FP16 datapath 합성이나 전체 HBM 연결 검증을 뜻하지 않는다. 기본 burst 폭은 C++의 16×FP16에 맞춘 256 bit, 즉 32 B다. Dual arbiter는 output lane 두 개를 사용해 최대 64 B/cycle 폭을 제공한다. 두 source가 동시에 valid여야 최대폭을 사용하므로 sustained bandwidth는 별도로 검증해야 한다.

Stress test는 512-cycle 포화 구간에서 64 B/cycle을 유지하고 2,000-cycle random valid/ready 구간에서 payload 안정성과 source fairness를 검사한다. Random test에서 발견된 stall 중 조합 선택 변경 문제는 dual arbiter의 hold register로 수정했다.

`logic_die_64ch_trace_replay_tb.sv`는 C++ MobileNetV4 trace CSV를 직접 읽어 64채널 top에 재생한다. 실제 8,192 burst가 4,096개의 dual-lane full cycle로 배출되어 C++ replay와 일치했다.

## 아직 결정하지 않은 연구 항목

- FP16 adder 구조와 pipeline latency
- Slot allocator와 key-to-slot mapping 위치
- 8-bank interconnect와 arbitration topology
- TSV/channel interface 폭
- 면적, 전력, 주파수, 열 제약
- Tile-batch 명령을 누가 생성하는지

이 항목은 C++ 성능값만으로 확정하지 않고 RTL 합성과 연구자의 architecture 판단을 함께 사용해야 한다.

## FP16 datapath 검증

`fp16_add.sv`는 합성 가능한 조합형 FP16 lane 가산기이며,
`bank_local_fp16_reduction.sv`는 16개 lane을 기존 reduction buffer에 연결한다.
`run_tests.sh`는 저장소의 `lib/half.h`로 4,096개 정답을 생성해 RTL 결과와 bit
단위로 비교하고, 16-lane에서 `1.0 + 2.0 + 3.0 = 6.0` 누산도 확인한다.

```text
FP16_ADD_RANDOM_TB PASS vectors[4096] reference[C++ half.h]
BANK_LOCAL_FP16_REDUCTION_TB PASS lanes[16] sum[6.0]
```

이는 기능 검증 결과다. 조합형 FP16 가산기가 목표 clock 한 cycle을 만족한다는
뜻은 아니며, 합성 후 pipeline latency를 C++ 설정에 반영해야 한다.

실제 MobileNetV4 `14×14×192` 실행에서 생성한 24,576개 3-tap partial도 64채널×8
PIM block에 해당하는 512개 RTL source에서 재생한다. 세 partial씩 누산한 final
8,192개, 총 FP16 131,072개가 C++ 결과와 bit 단위로 일치한다.

```text
LOGIC_DIE_512SOURCE_FP16_PAYLOAD_TB PASS partials[24576] finals[8192] lanes[16] reference[C++ MobileNetV4]
```

`logic_die_64ch_reduction_top.sv`의 `USE_INTERNAL_FP16=1`은 외부 adder 대신 내장
FP16 lane을 선택한다. timed payload test는 실제 arrival cycle과 source FIFO를
유지하며 reduction부터 64-channel dual-link까지 대표 lane을 연속 검증한다.

```text
LOGIC_DIE_64CH_FP16_TIMED_PAYLOAD_TB PASS partials[24576] finals[8192] checked_lanes[1] full_cycles[4096] partial_cycles[0] replay_cycles[13880]
```

Icarus 실행 시간을 관리하기 위해 timed test는 1 lane으로 topology와 timing을
검증하고, 바로 앞의 512-source test가 16 lane 전체 값을 검증한다.

## Yosys 합성 proxy

sudo 없이 사용자 영역에 Yosys를 설치하고 generic 합성 sweep을 실행할 수 있다.

```bash
bash rtl/bootstrap_yosys_local.sh
bash rtl/run_synthesis_sweep.sh
```

Yosys 0.52 결과에서 FP16 1 lane은 3,227 generic cell과 topological depth 232,
16-lane burst pipeline은 51,632 cell이었다. 16-entry source buffer까지 포함하면
source 하나는 88,987 cell과 5,457 flip-flop proxy였다. 이는 실제 공정 면적이나
주파수가 아니라 구조 비교용 수치다. 결과는 `experiment/results/fp16_*synthesis*.csv`와
`experiment/report_88_yosys_area_proxy_and_latency_feedback.md`에 정리돼 있다.

## Shared FP16 pipeline

`shared_fp16_pipeline_fabric.sv`는 8 source의 operand를 round-robin으로 선택해
제한된 수의 16-lane FP16 pipeline에 보낸다. `shared_fp16_reduction_cluster.sv`는
이를 source별 key/slot buffer와 연결한다.

```bash
bash rtl/run_shared_cluster_tests.sh
bash rtl/run_shared_fabric_synthesis.sh
```

pipeline 1·2·4개 기능 test는 각각 26·14·8 service cycle에 통과했다. 64 B/cycle
link에 대응하는 첫 기준 후보는 32 B pipeline 2개이며 자세한 결과는
`experiment/report_89_shared_fp16_pipeline_scheduler.md`에 있다.

실제 MobileNetV4 channel payload와 arrival cycle은 다음 명령으로 재생한다.

```bash
python3 experiment/analyze_shared_pipeline_trace.py
bash rtl/run_shared_trace_tests.sh
```

64채널 replay에서 pipeline 1·2·4개 모두 13,879 cycle이었고, channel 0 RTL의
384 partial과 128 final도 모두 통과했다. pipeline 2개는 pipeline 4개와 같은 완료
cycle·peak FIFO를 더 작은 합성 proxy로 달성했다. 상세 내용은
`experiment/report_90_actual_64ch_shared_pipeline_trace.md`에 있다.
