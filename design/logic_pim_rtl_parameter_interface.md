# Logic-PIM RTL 파라미터 인터페이스 초안

## 1. 문서 목적

현재 C++ simulator에서 검증한 계층형 PIM 구조를 향후 Verilog RTL 파라미터로 연결하기 위한 인터페이스 초안이다. 아래 값은 확정된 물리 설계가 아니라 simulator 후보점과 연구자가 결정해야 할 변수를 구분해 기록한다.

## 2. 현재 Simulator 후보점

| 항목 | 후보값 | 근거 |
|---|---:|---|
| HBM channel | 64 | 현재 프로젝트와 simulator 기준 구조 |
| Bank-side PIM blocks/channel | 8 | 기존 HBM2-PIM 설정 |
| Global logic PCU | 16 | MobileNetV4 전체 UIB 최초 bank crossover |
| Logic PCU latency | 2 cycles | 현재 timing 가정 |
| Logic internal bandwidth | 64 B/cycle | PCU 16개에서 최초 pointwise crossover |
| Hierarchy bandwidth | 64 B/cycle | 현재 bank/logic tensor transfer 기준 |
| Spatial grouping | 사용 | expand 21 groups, project 32 groups |
| Command coalescing | 사용 | overhead 4 조건에서 1.95x 개선 |
| Shared weight buffer | 65,536 B 후보 | MobileNetV4 UIB의 expand 49,152 B와 project 65,536 B를 순차 수용 |

## 3. 권장 Verilog Parameter

```systemverilog
parameter int HBM_CHANNELS             = 64;
parameter int BANK_PCU_PER_CHANNEL     = 8;
parameter int LOGIC_PCU_COUNT          = 16;
parameter int LOGIC_PCU_LATENCY        = 2;
parameter int LOGIC_DATA_BYTES_PER_CYCLE = 64;
parameter int HIERARCHY_BYTES_PER_CYCLE  = 64;
parameter int LOGIC_CMD_OVERHEAD       = 4;
parameter bit ENABLE_CMD_COALESCING    = 1'b1;
parameter int CMD_SIGNATURE_WIDTH      = 32;
parameter int LOGIC_QUEUE_DEPTH        = 64;
parameter int BROADCAST_MASK_QUEUE_DEPTH = 128; // MobileNetV4 project 관측 peak 78의 1차 후보
parameter int WEIGHT_BUFFER_BYTES      = 65536; // MobileNetV4 UIB 트래픽 실험의 1차 후보
parameter int WEIGHT_FILL_CHANNELS     = 32; // row-interleaved 정책의 최소 실험 crossover 후보
parameter string WEIGHT_FILL_POLICY    = "row_interleaved";
parameter int WEIGHT_STAGING_ROW       = 2048;
parameter bit DIRECT_STAGING_COMMAND_PATH = 1'b0;
parameter int WEIGHT_BUFFER_WRITE_PORTS = 4;
parameter int WEIGHT_BUFFER_WRITE_LATENCY = 1; // 1~4 cycle sweep 통과
parameter int POST_FILL_GUARD_CYCLES     = 0; // 진단용; epoch release 사용 시 불필요
parameter int OUTPUT_BUFFER_ENTRIES      = 2;
parameter int OUTPUT_DRAIN_LATENCY       = 4;
parameter int OUTPUT_DRAIN_BURSTS_PER_CYCLE = 8;
parameter int MODE_TRANSITION_LATENCY   = 0; // RTL state-machine measurement required
parameter bit ENABLE_EPOCH_RELEASE       = 1'b1;
```

## 4. RTL 모듈 경계

| 모듈 | 주요 역할 | 필수 입력/출력 |
|---|---|---|
| `bank_pcu_array` | 기존 bank-side elementwise/depthwise 처리 | bank data, PIM command, local result |
| `logic_cmd_router` | bank와 logic 연산 분류 | opcode, placement, tensor context |
| `logic_cmd_coalescer` | 동일 epoch 명령 broadcast 병합 | command signature, channel mask |
| `logic_pcu_scheduler` | global PCU lane 할당과 queue 관리 | command, ready/valid, PCU completion |
| `logic_pcu_array` | cross-bank GEMV/reduction 실행 | operands, weight, partial sum |
| `hierarchy_interconnect` | 64채널과 logic die 사이 이동 | channel mask, payload, backpressure |
| `shared_weight_buffer` | pointwise weight 재사용 | layer id, weight address, cache hit/miss |
| `result_router` | logic 결과를 bank 또는 다음 계층에 전달 | destination, result data |

## 5. Command Packet 최소 필드

| 필드 | 목적 | 연구 결정 필요 여부 |
|---|---|---|
| opcode | MAC, MAD, reduction 등 구분 | 필요 |
| channel mask | broadcast 대상 채널 그룹 | 필요 |
| source buffer | 입력 또는 partial sum 위치 | 필요 |
| destination buffer | 결과 저장 위치 | 필요 |
| tensor/layer id | 잘못된 명령 coalescing 방지 | 필요 |
| precision | FP16/INT8 등 데이터 형식 | 필요 |
| accumulation mode | local/global reduction 방식 | 필요 |
| epoch/barrier id | 명령 순서와 동기화 보장 | 필요 |
| command ordinal | 같은 epoch 안에서 channel별 동일 명령 순번 식별 | 필요 |
| channel ready mask | 해당 ordinal의 실제 broadcast 참여 channel 표시 | 필요 |
| expected channel mask | 해당 ordinal에서 기다려야 할 channel을 사전 지정 | 필요 |
| stream EOS ordinal | 마지막 wave에서 더 이상 명령이 없는 stream 표시 | 필요 |

현재 simulator는 주로 opcode와 PIM register encoding으로 signature를 만든다. RTL에서는 위 context가 다른 명령을 합치면 안 된다.

## 6. Simulator와 RTL Parameter 대응

| Simulator 설정 | RTL parameter | 비고 |
|---|---|---|
| `NUM_CHANS` | `HBM_CHANNELS` | 현재 64 고정 |
| `NUM_PIM_BLOCKS` | `BANK_PCU_PER_CHANNEL` | bank-side 구조 |
| `NUM_LOGIC_PIM_UNITS` | `LOGIC_PCU_COUNT` | global scheduler 기준 |
| `LOGIC_PIM_LATENCY` | `LOGIC_PCU_LATENCY` | RTL 합성 후 갱신 필요 |
| `LOGIC_PIM_BW` | `LOGIC_DATA_BYTES_PER_CYCLE` | 내부 interconnect 포함 |
| `HIERARCHY_PIM_BW` | `HIERARCHY_BYTES_PER_CYCLE` | bank/logic 경계 |
| `LOGIC_CMD_OVERHEAD` | `LOGIC_CMD_OVERHEAD` | command router 지연 |
| `LOGIC_CMD_COALESCING` | `ENABLE_CMD_COALESCING` | channel-mask broadcast 필요 |
| `LOGIC_WEIGHT_FILL_CHANNELS` | `WEIGHT_FILL_CHANNELS` | channel별 tile이 한 row에 들어가는지 함께 검증 |
| `LOGIC_WEIGHT_FILL_POLICY` | `WEIGHT_FILL_POLICY` | 현재 round-robin 후보; bank-count 균등화는 이득 없음 |
| `LOGIC_DIRECT_STAGING_COMMAND_PATH` | `DIRECT_STAGING_COMMAND_PATH` | weight staging command를 DRAM bank row-state와 분리; data bus와 buffer write timing은 유지 |
| `LOGIC_POST_FILL_GUARD_CYCLES` | `POST_FILL_GUARD_CYCLES` | buffer-ready 이후 command release 정렬 비용 |
| `LOGIC_OUTPUT_BUFFER_ENTRIES` | `OUTPUT_BUFFER_ENTRIES` | 동시에 조립 가능한 출력 위치 타일 수 |
| `LOGIC_OUTPUT_DRAIN_LATENCY` | `OUTPUT_DRAIN_LATENCY` | 완성 타일의 downstream 이동 시작 지연 |
| `LOGIC_OUTPUT_DRAIN_BW` | `OUTPUT_DRAIN_BURSTS_PER_CYCLE` | cycle당 downstream 이동 burst 수 |
| `LOGIC_EPOCH_RELEASE` | `ENABLE_EPOCH_RELEASE` | epoch/ordinal/channel-mask 기반 broadcast release |
| `LOGIC_BROADCAST_QUEUE_DEPTH` | `BROADCAST_MASK_QUEUE_DEPTH` | 0은 무제한, 현재 RTL 후보는 128 entries |
| `LOGIC_ONLINE_QUEUE_BACKPRESSURE` | command queue `ready` 연결 | true일 때 issue 단계에서 새 mask를 보류 |
| `LOGIC_DEPTHWISE_ACCUMULATION` | `ENABLE_DEPTHWISE_ACCUMULATION` | bank partial을 logic die에서 누산하는 선택 경로 |
| `LOGIC_ACCUMULATOR_ENTRIES` | `ACCUMULATOR_ENTRIES` | 동시에 유지할 출력 burst 수, 0은 simulator 무제한 |
| `LOGIC_ACCUMULATOR_LATENCY` | `ACCUMULATOR_LATENCY` | 부분합 수신 및 누산 고정 지연 |
| `LOGIC_ACCUMULATOR_BW` | `ACCUMULATOR_BYTES_PER_CYCLE` | bank-to-logic reduction link 처리량 |
| `LOGIC_ACCUMULATOR_OVERLAP` | `ENABLE_ACCUMULATOR_STREAMING` | bank MUL과 partial link를 valid/ready pipeline으로 중첩 |
| `BANK_LOCAL_AGGREGATION_TAPS` | `BANK_LOCAL_REDUCTION_FACTOR` | logic die 전송 전에 bank PCU가 합칠 depthwise tap 수 |
| `BANK_LOCAL_ACCUMULATOR_ENTRIES` | `BANK_LOCAL_ACCUM_ENTRIES` | rank당 bank-local partial entry 수 |
| `BANK_LOCAL_ACCUMULATOR_PORTS` | `BANK_LOCAL_ACCUM_PORTS` | cycle당 update 가능한 PIM-block partial 수 |
| `BANK_LOCAL_ACCUMULATOR_LATENCY` | `BANK_LOCAL_ACCUM_LATENCY` | local accumulator update service latency |
| `BANK_LOCAL_ACCUMULATOR_BANKS` | `BANK_LOCAL_ACCUM_BANKS` | PIM-block update를 분산할 accumulator SRAM bank 수 |
| `BANK_LOCAL_ACCUMULATOR_TILE_BATCH` | `TILE_BATCH_SIZE` | 동시에 live 상태로 유지할 spatial tile 수, 0은 전체 tile |

## 7.2 Depthwise Accumulator 인터페이스

RTL에는 `logic_accumulator_buffer` 모듈과 다음 valid/ready 계약이 필요하다.

```text
partial_valid, partial_ready
partial_key = {channel, rank, pim_block, bank_parity, row, column}
partial_data[16 x FP16]
partial_last_tap

final_valid, final_ready
final_key
final_data[16 x FP16]
```

각 key는 정확히 `KERNEL_SIZE * KERNEL_SIZE`개의 partial을 받은 뒤에만 final을 발생시켜야 한다. Buffer full이면 `partial_ready=0`으로 bank-side 발행에 backpressure를 전달하고, final write가 승인될 때 entry를 반환한다. 현재 C++ 1차 모델은 tap별 전송을 직렬화하므로 RTL 성능 후보에는 bank MUL과 link 전송의 overlap queue가 추가로 필요하다. 64채널 실제 shape depthwise 37,632개와 전체 UIB 최종 출력 18,816개에서 key와 tensor-lane 매핑 정확도를 검증했다. RTL에서는 partial handshake가 기존 bank CRF의 PC/NOP 진행을 대체하거나 동기화해야 한다.

Overlap 모델의 전체 UIB sweep에서 64 B/cycle은 256,484 cycle로 기준보다 느렸고 256 B/cycle은 231,650 cycle로 기준 235,182 cycle을 1.50% 통과했다. 따라서 `256 B/cycle streaming`은 최초 성능 후보점이다. 2,048-bit/cycle 물리 link 비용이 클 수 있으므로 RTL 비교 후보에는 `128 B/cycle + bank local aggregation`도 반드시 포함한다.

Bank-local aggregation 후속 sweep에서는 `128 B/cycle + factor 3`이 231,727 cycle, `64 B/cycle + factor 9`가 231,178 cycle이었다. RTL 우선 비교점은 넓은 link보다 `64 B/cycle + 9-tap bank local accumulator`다. Bank accumulator에는 최소 `{valid, output_key, partial_sum, tap_count}`와 flush handshake가 필요하다.

유한 자원 모델 결과 14×14×192 shape의 peak는 128 entries/rank였다. `128 entries, 4 ports, latency 1`의 전체 UIB는 231,309 cycle로 기준보다 1.65% 빠르고 정확도와 write 감소를 유지했다. Data array 하한은 `128 × 32 B = 4 KiB/rank`이며 metadata는 별도다.

Banked 모델에서 `4 banks × 1 port`는 중앙 `1 bank × 4 ports`와 같은 33,622-cycle depthwise 처리량을 보였고, `8 banks × 1 port`는 33,138 cycle로 줄었다. 28×28×192 shape에서는 총 peak가 256으로 늘었지만 8-bank의 bank당 peak는 32로 유지됐다. 따라서 RTL 1차 후보는 8 banks × bank당 1 write port지만, 총 entry 수는 고정 128로 확정하지 않는다. 최대 지원 spatial tile 수 또는 tile별 flush 정책을 먼저 정해야 한다.

Tile-batch 정책을 추가한 결과 28×28×192를 총 128 entries, bank당 16 entries로 처리했고 출력 150,528개가 모두 통과했다. 무배치 63,910 cycle에서 batch-1 65,250 cycle로 2.10% 증가하므로 4 KiB/rank 저장공간 절감과 제어 overhead의 trade-off다. 전체 14×14 UIB에서 8 banks×1 port 후보는 230,075 cycle, 중앙 1 bank×4 ports는 230,514 cycle, bank-depthwise 기준은 233,365 cycle이었다. 현재 RTL 시작점은 8 banks, bank당 16 entries, bank당 1 update port, tile batch 1이다.

첫 RTL 제어 초안은 `rtl/bank_local_reduction_buffer.sv`에 있다. 이 모듈은 bank별 update/final valid-ready, slot/key 검사, entry 반환을 구현한다. 이후 `rtl/fp16_add.sv`와 `rtl/bank_local_fp16_reduction.sv`를 추가해 16-lane FP16 datapath를 실제로 연결했다. C++ `half.h`가 생성한 4,096개 정답과 bit 단위 비교를 통과했지만, C++의 latency 1은 아직 RTL 합성으로 입증되지 않았으므로 FP16 adder pipeline이 결정되면 반드시 재보정한다.

Yosys 0.52 generic 합성에서는 FP16 lane 하나가 3,227 cell, 16-lane burst pipeline이 51,632 cell, topological depth가 232로 측정됐다. 16-entry source buffer와 결합하면 source 하나가 88,987 cell과 5,457 flip-flop proxy가 됐다. 이 값은 공정 면적이나 ns가 아니지만 512-source 완전 복제와 latency 1을 기본 확정값으로 쓰기에 충분한 물리 근거가 없음을 보여준다. 다음 인터페이스에는 shared pipeline count와 storage banking을 별도 파라미터로 추가해야 한다.

8 source가 16-lane pipeline을 공유하는 `shared_fp16_reduction_cluster.sv`를 추가했다. pipeline 1·2·4개의 24-partial 기능 test는 각각 26·14·8 cycle에 통과했다. C++에는 `LOGIC_ACCUMULATOR_PIPELINES`를 추가했으며 0은 기존 호환 모델, 1 이상은 logic-die에서 동시에 서비스할 수 있는 32 B burst 수다. 64 B/cycle link 조건에서는 pipeline 2개가 link를 채우는 최소 후보이고 pipeline 4개는 1채널 total cycle을 더 줄이지 못했다.

`rtl/logic_die_link_arbiter.sv`는 8개 bank output을 round-robin으로 한 lane에 모으며 Icarus testbench를 통과했다. Burst 하나는 256 bit=32 B이므로 단일 lane 처리량은 32 B/cycle이다. C++의 64 B/cycle 후보와 맞추려면 RTL output lane 2개가 필요하며, 이 차이를 해결하기 전에는 C++ bandwidth 값을 RTL 입증값으로 취급하지 않는다.

실제 UIB pointwise scheduler reservation 92,512건을 기록하고 16-PCU replay가 원본 start/completion과 전부 일치함을 확인했다. Fixed-arrival sweep에서 16·32·64 PCU의 expand span은 86,112·43,056·21,528 cycle, project span은 102,144·51,072·25,536 cycle이었다. 32 PCU를 우선 Pareto 후보로 두되, 64 PCU에서도 project peak waiting이 36,092건이므로 중앙 FIFO를 그대로 크게 만드는 대신 source-distributed queue와 bounded ready queue/backpressure를 RTL 인터페이스에 포함해야 한다.

후속 bounded replay에서 중앙 ready queue 64·128·256 entries는 같은 PCU 수에서 완료 cycle 차이가 없었다. 64-entry만으로 lane을 포화시켰으며 더 큰 queue는 source 대기를 중앙으로 옮길 뿐이었다. 따라서 RTL 1차 후보는 `LOGIC_READY_QUEUE_DEPTH=64`로 두고, source FIFO를 8·16·32 entries/stream으로 제한한 backpressure 실험을 거쳐 확정한다.

Finite-source replay에서는 source depth 8이 32 대비 저장량을 75% 줄이면서 `32 PCU`의 project 완료를 0.78%만 늦췄다. 따라서 1차 후보는 PCU 32, central ready queue 64, source depth 8/stream이다. C++에는 `LOGIC_PCU_QUEUE_DEPTH`를 추가했다. 64개 controller의 동시 승인 때문에 단순 local check는 depth 64에서 peak 127까지 초과했으며, 선점 credit은 후보 pop 실패 시 누수되어 폐기했다. 현재 C++는 한 channel wave의 headroom을 남기는 low-watermark 방식으로 miniature UIB를 통과했다. 최종 RTL은 polling 방식이 아니라 `request_valid[63:0]`, 중앙 `grant[63:0]`, queue credit 차감으로 정확한 hard cap을 구현해야 한다.

후속 `rtl/logic_die_dual_link_arbiter.sv`와 `rtl/hierarchical_reduction_path.sv`에서 256-bit output lane 두 개를 구현해 최대폭을 64 B/cycle로 맞췄다. Reduction buffer부터 dual link까지 통합 testbench가 PASS했다. 현재 두 lane은 payload 안정성을 위해 ready를 결합하므로 lane별 독립 stall의 처리량은 보수적이다.

512-cycle 포화 stress에서 1,024 burst, 즉 64 B/cycle을 지속했고 2,000-cycle random valid/ready에서 1,052 burst와 전 source progress를 확인했다. 초기 조합 arbiter는 stall 중 새 valid가 들어오면 payload가 바뀌는 결함이 있었고 hold grant/data register로 수정했다. 따라서 `64 B/cycle`은 RTL 최대폭으로 검증됐지만 workload 평균폭은 trace 기반으로 별도 보정해야 한다.

초기 통합 RTL은 한 rank의 8 PIM-block slice만 표현했다. `rtl/logic_die_64ch_reduction_top.sv`는 channel별 8→1 local arbiter 64개와 global 64→2 dual arbiter로 확장해 C++의 공유 범위와 맞췄다. Rank당 data array는 4 KiB이고 64채널 stack 전체 하한은 256 KiB다. 4채널 축소 기능 test와 기본 64채널 elaboration이 PASS했다.

C++ 14×14×192 trace는 8,192 event, 16 arrival wave, wave당 512 burst였다. C++ 2-stage replay와 64채널 RTL CSV replay 모두 4,096 full dual-lane cycle, partial/idle 0으로 일치했다. 이 workload에서는 `LOGIC_ACCUMULATOR_BW=64`가 최대폭뿐 아니라 sustained bandwidth로도 검증됐다.

## 7.1 Epoch Release 규칙

1. 각 pointwise layer의 모든 weight fill이 완료되면 `fill_done`을 발생시킨다.
2. 대상 channel의 `channel_ready_mask`가 예상 mask와 같을 때 새 `epoch_id`를 발급한다.
3. channel마다 해당 epoch의 명령에 동일한 `command_ordinal`을 붙인다.
4. `{epoch_id, command_ordinal, opcode/signature}`가 같은 명령은 channel mask 하나로 broadcast한다.
5. ready mask가 완성되지 않은 epoch는 발급하지 않고 오류 또는 timeout 상태를 기록한다.

Workload scheduler는 group별 position 수와 pointwise CRF 명령 수로 stream별 EOS ordinal을 계산한다. Expected mask는 해당 ordinal보다 EOS가 큰 stream으로 구성하며, 실제 ready mask가 expected mask와 같아지는 즉시 queue entry를 닫는다.

Queue ready 규칙은 다음과 같다.

```text
ready = existing_mask_entry || open_entry_count < BROADCAST_MASK_QUEUE_DEPTH
```

Queue가 full이어도 이미 열린 mask를 완성하는 channel command는 받아야 한다. 새 mask entry만 `ready=0`으로 막아야 다른 channel이 기존 entry를 완성하고 교착을 피할 수 있다.

현재 simulator의 `LogicCommandContext`는 `{epochId, commandOrdinal, streamId, valid}`로 구성된다. RTL command queue에서도 이 필드들을 명시적으로 보존해야 하며, 각 ordinal의 channel mask는 고정 64-bit가 아니라 실제 참여 stream으로 조립한다. MobileNetV4 UIB 측정에서는 mask fanout이 8~64로 변했다.

Broadcast mask assembly residency 측정에서 expand peak는 1 entry, project peak는 78 entries였다. 따라서 64-entry mask queue는 현재 도착 스케줄을 수용하지 못하며 1차 후보는 128 entries다. 최소 entry를 `64-bit channel mask + 32-bit signature + 16-bit epoch + 16-bit ordinal = 128 bits`로 잡으면 128 entries는 최소 약 2 KiB다. source/destination과 상태 bit는 별도 추가해야 한다.

MobileNetV4 UIB에서는 expand epoch의 대상 stream이 63개, project epoch가 64개이며 두 mask 모두 완성됐다. `POST_FILL_GUARD_CYCLES=128`은 원인 진단용으로는 유효했지만 RTL 제어 후보는 위 handshake 방식이다.

## 7. 연구자가 채워야 하는 값

다음 값은 simulator가 자동으로 정답을 정할 수 없다.

1. PCU 16개의 허용 면적과 전력
2. 64 B/cycle interconnect의 배선 폭과 목표 주파수
3. shared weight buffer 용량과 bank 수
4. command signature와 epoch 정의
5. partial sum reduction network 구조
6. bank-side와 logic-side 동시 실행 arbitration 정책
7. MobileNetV4 외 workload에서의 최소 성능 조건

## 8. 다음 검증 게이트

1. 65,536 B shared weight buffer의 fill을 여러 HBM channel에 stripe할 interconnect를 결정한다.
2. RTL command packet 필드를 확정한다.
3. Verilog scheduler에서 16 PCU와 2개 이상 lane 동시 완료를 검증한다.
4. 합성 결과의 PCU latency와 bandwidth를 simulator 설정에 다시 입력한다.
5. MobileNetV4 전체 UIB 결과가 C++ simulator와 RTL timing model에서 같은 경향을 보이는지 비교한다.

## 9. 온라인 큐 용량 판단

MobileNetV4 UIB 14에서 depth 32/64/128의 blocked wall-cycle은 각각 291/53/0이었다. 막힌 channel-cycle은 모두 logic PCU busy 구간과 겹쳐 총 cycle은 214,228로 같았다. 따라서 RTL 1차 안전 사양은 128 entries, 면적 절감 검토 사양은 64 entries로 둔다. 64 entries를 확정하기 전에는 다른 MobileNetV4 pointwise shape에서도 peak open mask와 critical-path 중첩을 반복 측정해야 한다.

독립 pointwise shape sweep에서 expand `28×28, 64→192`와 `14×14, 96→192`의 peak는 모두 1, project `14×14, 192→96`의 peak는 64였다. 그러나 실제 UIB 연결 실행의 project peak는 78이었다. RTL queue sizing은 독립 opcode의 fanout만이 아니라 선행 연산 이후 PCU busy 상태와 다음 epoch 유입의 중첩을 포함해야 한다. 이 차이 때문에 64 entries는 면적 비교 후보로만 유지하고 128 entries를 기준 후보로 사용한다.

PCU 8/16/32, logic bandwidth 32/64/128 B/cycle의 9개 microarchitecture에서 depth 128 peak를 교차 검증한 결과 최대값은 78이었다. Depth 64의 blocked channel-cycle은 조합에 따라 0~211로 변했지만 모두 PCU busy 구간과 겹쳤다. Queue pressure는 PCU 또는 bandwidth에 대해 단조롭지 않으므로 RTL 용량 산정에는 전체 block의 cycle-accurate command arrival를 사용한다.

CommandQueue의 online predicate 거절 시 뒤쪽 독립 command를 세는 HOL 계측을 추가했다. MobileNetV4 UIB depth 32/64에서 predicate reject는 7,513/211 channel-cycle이지만 발행 가능한 queued 대체 command는 0이었다. 현재 workload에서는 command-level HOL이 없지만 RTL arbiter는 `logic_ready=0`일 때 다른 bank-side queue를 선택할 수 있어야 한다. Ready 평가의 성능 counter 갱신 경로와 관찰 전용 probe 경로도 분리한다.

Bank/logic 독립 queue와 공유 service port를 가진 `HierarchyPIMArbiter` 사전 통합 모델을 추가했다. 64+64 동시 요청과 16-cycle logic not-ready trace에서 strict round-robin은 15 idle cycles로 완료가 142 cycle이었고 ready-bypass는 15개 bank 요청을 우회 발행해 127 cycle에 완료했다. RTL 기본 후보는 round-robin state에 ready-bypass를 결합한 정책이다. Fixed priority는 반대 source의 bounded wait를 보장하지 못하므로 기본 정책에서 제외한다.

`HIERARCHY_READY_BYPASS`를 실제 MemoryController CommandQueue에 연결했다. Blocked logic packet은 queue에 유지한 채 뒤쪽 packet을 side-effect-free probe로 검사하고 실제 발행 시에만 bypass counter를 증가시킨다. MobileNetV4 UIB에서는 barrier와 dependency 때문에 실제 bypass가 0이지만 on/off 모두 정확도와 214,228 cycle을 유지했다. RTL의 독립 queue에서는 같은 정책을 직접 적용하고 simulator의 실제 효과 검증은 tile-level workload overlap 이후 수행한다.

실제 UIB stage cycle은 expand 88,048, depthwise 20,360, project 103,288, add 1,659, ReLU/read 873으로 합계 214,228이다. 14×14 spatial tile과 3×3 halo dependency를 적용한 wavefront 상한은 191,348 cycle로 22,880 cycle(10.68%) overlap 가능성을 보였다. 이 값은 구현 전 목표선이며 RTL에는 최소 3-row activation line buffer, tile completion token, bank/logic 독립 queue가 필요하다.

Spatial pointwise를 enqueue/wait/readback으로 분리하고 transaction buffer를 handle이 소유하도록 구현했다. 한 PIMKernel당 outstanding handle은 현재 1개이며 shared weight fill은 enqueue 준비 단계에서 완료한다. Expand 3개 input row에서 bank-side depthwise output 2개 row, 5,376개 원소의 정확도를 검증했다. RTL과 다음 simulator 단계에는 row-range session, partial completion token, 3-row line buffer가 필요하다.

연속 행 범위를 실행하는 `PointwiseSpatialSession`을 추가했다. `3×4×3` pointwise를 `2행 + 1행`으로 나눠 실행해 36개 출력을 모두 검증했고, 비연속 행과 active 범위 중복 제출을 차단한다. 현재 행 범위마다 weight fill을 반복하고 한 범위만 outstanding이므로 RTL 인터페이스에는 layer-level weight residency, row completion token, partial readback address가 추가로 필요하다.

Session 단위 shared weight residency를 구현했다. 첫 범위의 512 fill bursts 이후 재사용 범위의 fill은 0이며 작은 행 세션은 2,770에서 2,672 cycle로 감소했다. Weight layer generation이 바뀌면 재사용을 거부한다. RTL에는 weight layer ID/generation과 valid bit가 필요하며, CRF residency와 row completion token은 아직 별도로 구현해야 한다.

Logic-die channel group별 CRF residency bitmap도 추가했다. 첫 행 범위에서 8개 group을 각 1회 프로그램하고 재사용 범위의 CRF program은 0회였다. 총 cycle은 2,658로 감소했다. 이 모델은 bank-side PCU와 logic-die PCU의 CRF가 물리적으로 분리된다는 전제를 사용하며, RTL에는 group별 `crf_context_id`, valid bit, context 교체 규칙이 필요하다.

3×3 depthwise용 `ActivationRowBuffer`를 추가했다. Pointwise 완료 행을 최대 3개 보관하고 halo가 준비될 때 output-row token을 순서대로 release한다. 4개 입력 행에서 4개 token, peak 3행, 상하 zero padding을 검증했다. RTL line buffer에는 contiguous row sequence 검사, `row_valid`, `output_row_ready`, full backpressure가 필요하다.

Depthwise를 17개 nonblocking MUL/ADD stage로 분리하고 bank stage와 logic pointwise row를 한 drain에 넣었다. 기존 단일 CRF에서는 logic 출력 12개가 모두 0이 되어 bank/logic PCU가 command state까지 공유한다는 결함이 드러났다. `PIMRank`에 bank CRF와 logic CRF를 분리한 뒤 공동 drain 출력 12개가 모두 통과했다. RTL에서도 두 계층의 CRF, PC, valid/context state를 물리적으로 분리해야 한다.

Command ready probe도 packet domain을 받아 bank/logic CRF 중 실제 실행과 같은 context를 decode하도록 수정했다. Online queue backpressure의 probe와 `doPIM` 실행 명령이 일치하며 공동 drain 1,942 cycle과 정확도는 유지됐다.

Source별 issue cycle을 계측한 결과 같은 drain에서도 bank window 1,748~2,344와 logic window 2,758~3,080은 전혀 겹치지 않았고 전환 공백은 414 cycle이었다. 독립 PCU만으로는 overlap이 발생하지 않으며 RTL에는 bank/logic 독립 command queue와 source-scoped barrier가 필요하다.

Source-scoped transaction/command queue를 실험적으로 활성화하자 logic issue가 0이 되고 출력 12개가 모두 0이 됐다. CRF 외에 PC, jump/repeat counter, exit, PIM mode가 아직 공유되기 때문이다. RTL과 simulator 모두 queue 분리 전에 전체 execution context를 bank/logic별로 분리해야 한다. 실험 설정 `HIERARCHY_SOURCE_QUEUES`는 context 분리 완료 전까지 기본 false다.
