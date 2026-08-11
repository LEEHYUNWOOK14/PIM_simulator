# 01. 아키텍처와 인터페이스 감사

## 실제 Full-PIM hierarchy

```text
full_pim_system_top
├── g_channel[0..CHANNELS-1]
│   ├── bank_side_pim_subsystem
│   │   ├── dram_bank_array_model
│   │   ├── pim_crf
│   │   └── bank_pim_core[0..PIM_BLOCKS-1]
│   │       ├── pim_command_decoder
│   │       └── pim_vector_alu
│   │           ├── fp16_mul lanes
│   │           └── fp16_add lanes
│   └── logic_die_link_arbiter
├── logic_die_link_arbiter (channel-to-logic)
├── logic_die_pim_top
│   ├── logic_command_coalescer
│   ├── logic_epoch_barrier
│   ├── logic_shared_buffer
│   ├── logic_operand_context_buffer
│   └── logic_pcu_scheduler
│       └── logic_pcu[0..15]
└── channel_tsv_interconnect (direct result path)
```

다음 모듈은 존재하지만 `full_pim_system_top` hierarchy에는 없다.

- `logic_command_router`
- `pim_local_accumulator`
- `cross_channel_reduction`
- `logic_result_router`
- 기존 `logic_die_64ch_reduction_top` 계열

따라서 “모듈 파일이 존재한다”와 “전체 데이터 경로에 구현됐다”를 구분해야 한다.

## 인터페이스 표

|경로|폭|Flow control|ID|stall/ordering|판정|
|---|---:|---|---|---|---|
|DRAM command → bank model|command 3b, payload 256b|`cmd_valid/ready`|bank,row,col|단일 command port|부분 구현|
|bank model → local PCU|bank당 256b|`pim_read_valid` 생성|고정 even/odd pair|PCU가 valid를 소비하지 않음|FAIL|
|CRF → local PCU array|32b|공통 valid, 모든 block ready AND|channel-local CRF|lockstep|정상 경로 PASS, error path FAIL|
|local PCU → channel arbiter|256b + key|valid/ready|context key|block별 output hold|PASS 범위 있음|
|channel arbiter → logic operand|256b|valid/ready|channel source + key|한 번에 한 channel|key가 top에서 폐기됨|
|logic command → coalescer|32b + epoch/ordinal/signature/mask|valid/ready|epoch/ordinal/signature/channel|128 open entries|부분 구현|
|operand context → 16 PCU|256b operands ×4|valid/ready|tag|최대 16 동시 issue|정상 경로 PASS|
|logic PCU → top output|256b + tag|valid/ready|tag/channel|stall hold|channel 계산 FAIL|
|local result → direct TSV|2×256b|valid/ready|key/channel|lane 독립 stall|PASS 범위 있음|
|logic PCU → reduction/result router|해당 없음|해당 없음|해당 없음|top 연결 없음|REQUIRED BUT MISSING|
|logic result → bank/host|해당 없음|해당 없음|해당 없음|router가 top에 없음|REQUIRED BUT MISSING|

## 연산 배치

|연산|Local PCU|Logic PCU|전체 경로 판정|
|---|---|---|---|
|ADD|구현|구현|FP16 add reference PASS|
|MUL|구현|구현|FP16 reference FAIL|
|MAC|구현|구현|multiplier 결함 때문에 FAIL|
|MAD|구현|구현|multiplier 결함 때문에 FAIL|
|MOV/FILL|local 구현|logic PCU datapath에는 의미 없음|CRF 반복 semantics 누락|
|JUMP/NOP/EXIT|CRF|logic command에는 별도 control 없음|JUMP/NOP semantics FAIL|
|REDUCE_SUM|standalone module|top 미연결|REQUIRED BUT MISSING|
|ACCUMULATE/CLEAR|standalone local accumulator|top 미연결|REQUIRED BUT MISSING|
|MAX|없음|없음|NOT REQUIRED/NOT IMPLEMENTED|
|LOAD/STORE|DRAM RD/WR 수준|연산 opcode 없음|AMBIGUOUS|

## 아키텍처 적합성 결론

bank pair, local GRF/SRF, 16-PCU issue, coalescer, buffer 및 TSV 구성요소는 존재한다. 그러나 top-level 실행 경로는 epoch, weight buffer, cross-channel reduction, accumulator와 result router를 하나의 transaction으로 연결하지 않는다. 현재 구현은 “필요 블록의 초안 모음과 일부 정상 경로”이지, 의도한 계층형 HBM2-PIM 전체 기능 구현으로 판정할 수 없다.
