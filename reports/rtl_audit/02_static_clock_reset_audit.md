# 02. 정적 RTL·Clock·Reset 감사

## Clock/Reset/CDC

- 감사한 Full-PIM RTL은 하나의 `clk_i` domain만 사용한다.
- 대부분의 순차 블록은 active-low asynchronous reset인 `always_ff @(posedge clk_i or negedge rst_ni)`를 사용한다.
- RTL 내부에서 확인된 CDC, generated clock, clock gating 또는 combinational clock는 없다.
- SDC에는 `clk_i` 10 ns clock와 0.2 ns uncertainty만 있으며 reset을 false path로 둔다.
- input/output delay, load/drive, max transition/fanout, generated clock 및 CDC constraint는 없다.

단일 clock이므로 CDC 결함은 확인되지 않았지만, asynchronous reset deassertion synchronizer와 reset recovery/removal sign-off 증거는 없다.

## 정적 핵심 발견

### Bank operand valid 미사용

`bank_side_pim_subsystem.sv:78-81`은 DRAM model의 `pim_read_valid`를 받지만 `bank_pim_core`에는 data만 전달한다. `bank_pim_core.sv:81`의 ready는 결과 공간과 opcode legal만 본다. 닫힌 bank 또는 tRCD 미충족 상태에서도 command가 commit된다.

### Illegal CRF deadlock/error masking

`bank_pim_core.sv:81-82`는 illegal이면 ready=0, valid일 때 error=1이다. 그러나 `bank_side_pim_subsystem.sv:91`은 core command valid를 `crf_command_ready`로 먼저 gate한다. 결과적으로 illegal command에서 core valid=0, error=0, CRF PC는 영구 정지한다.

### DRAM stalled response overwrite

`dram_bank_array_model.sv:54`의 RD 허용 조건은 `!read_pending_q`만 검사하고 `read_valid_o && !read_ready_i`를 검사하지 않는다. `read_pending_q`가 response valid 생성 시 해제되므로, 기존 response가 stalled인 동안 새 RD가 들어와 `read_data_o`를 덮어쓴다.

### Tag/channel 오연결

`logic_die_pim_top.sv:163-164`는 실제 selected channel을 pipeline metadata로 보존하지 않고 tag 하위 bit를 channel로 재해석한다. tag와 channel이 독립이면 잘못된 source channel을 보고한다. `full_pim_system_top.sv:159-160`은 더 나아가 bank context key를 버리고 channel 번호만 tag로 만든다.

### Epoch가 dispatch를 제어하지 않음

`logic_epoch_barrier`의 release/active는 관찰 output일 뿐이다. `logic_die_pim_top.sv:92`의 `coalesced_ready`와 170행 dispatch 조건은 epoch 상태, epoch ID 또는 ready mask를 참조하지 않는다. begin/fill/release 없이도 command가 실행된다.

### 미연결 기능

shared weight buffer read data는 외부 response로만 나가며 PCU operand mux로 연결되지 않는다. `cross_channel_reduction`, `pim_local_accumulator`, `logic_result_router`, `logic_command_router`는 Full-PIM top에 인스턴스되지 않는다.

### Parameter 경계

`$clog2(PIM_BLOCKS)-1:0`, `$clog2(PCUS)-1:0`, `$clog2(CHANNELS)-1:0` 형태 때문에 값 1에서 `[-1:0]`이 되어 Icarus가 2-bit port로 해석한다. 감사 TB의 `PIM_BLOCKS=1`에서 실제 width padding warning이 재현됐다. 공식 지원 범위 guard가 없다.

### 합성 구조 위험

- 128-entry coalescer는 모든 entry의 epoch/ordinal/signature/mask를 한 조합 루프에서 선형 검색한다.
- behavioral DRAM PIM read는 전체 memory를 조합 read한다.
- Yosys는 CRF, GRF, shared buffer, coalescer/context arrays를 register list로 변환한다고 경고한다.

이는 구조 오류로 검출되지는 않지만 64-channel physical timing/area 준비가 됐다는 증거가 아니다.

## X 상태

GRF/SRF와 memory payload는 reset되지 않는다. valid로 보호된다면 허용될 수 있으나 bank read valid가 core acceptance에 연결되지 않아 초기화되지 않은 DRAM payload가 architectural result로 노출될 수 있다. 이는 단순한 내부 don't-care가 아니라 기능 결함이다.
