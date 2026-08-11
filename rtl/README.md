# HBM2-PIM RTL

이 디렉터리는 bank-side PIM, logic-die PCU, 공유 weight buffer, channel reduction과 결과 retirement를 포함하는 합성 가능한 SystemVerilog 모델이다. 실제 HBM PHY나 DRAM hard macro를 포함하는 fabrication sign-off RTL은 아니다.

## Production hierarchy

`full_pim_system_top.sv`가 기능 검증과 물리 flow의 공통 top이다.

```text
full_pim_system_top
├─ bank_side_pim_subsystem[channel]
│  ├─ dram_bank_array_model
│  ├─ pim_crf
│  └─ bank_pim_core[block]
├─ logic_die_link_arbiter
├─ logic_die_pim_top
│  ├─ logic_command_coalescer
│  ├─ logic_epoch_barrier
│  ├─ logic_operand_context_buffer
│  ├─ logic_shared_buffer
│  ├─ logic_pcu_scheduler
│  └─ cross_channel_reduction_network
├─ logic_normalization_reduction_engine
│  ├─ multi-bank SUM/SUMSQ accumulator
│  └─ logic_normalization_scalar_engine
│     └─ fp16_rsqrt_lut256
├─ channel_tsv_interconnect
└─ logic_result_router
```

## 명령 의미

- 산술: `ADD`, `MUL`, `MAC`, `MAD`
- 이동: `MOV`, `FILL`
- 제어: `NOP`, `JUMP`, `EXIT`
- NOP은 encoded loop count+1회 실행한다.
- FILL과 arithmetic AUTO는 8회 실행한다.
- JUMP는 encoded count만큼 backward jump한 뒤 다음 PC로 진행한다.
- Illegal word는 error를 내고 retire하여 CRF를 deadlock시키지 않는다.

## GR00T normalization sideband

`full_pim_system_top`은 row tag, expected bank mask, `inv_hidden`, epsilon과 bank별
FP16 partial SUM/SUMSQ를 받는 normalization sideband를 제공한다. Logic die의
normalization engine은 global accumulation, LayerNorm/RMSNorm finalize와 LUT256
RSQRT를 수행하고 mean/inv-std 또는 inv-RMS를 broadcast 응답으로 반환한다.

이 sideband는 현재 production hierarchy에 합성되지만 Bank-PCU가 partial SUM/SUMSQ를
자동 생성하는 경로 및 broadcast 결과를 소비하는 `NORM_APPLY` opcode까지 연결된 것은
아니다. 해당 제한을 전체 normalization 실행 완료와 혼동하면 안 된다.

## DRAM 모델 범위

`dram_bank_array_model`은 open-row 상태와 tRCD_RD/WR, tRAS, tRP, tWR, tCCD, tRRD, tFAW, tRFC, read/write turnaround을 검사한다. Refresh 중 일반/PIM read를 차단한다. 실제 HBM2 controller의 모든 power-down, mode-register, PHY training 동작을 모델링하지는 않는다.

## 검증 실행

```bash
bash rtl/bootstrap_iverilog_local.sh
bash rtl/run_full_pim_tests.sh
bash verification/rtl_audit/run_aud_001_008_regression.sh
bash verification/rtl_audit/run_parameter_min_matrix.sh
bash rtl/run_full_pim_synthesis.sh
```

검증 항목은 FP16 reference vector, bank operand validity, DRAM backpressure/timing, CRF 반복, epoch gate, tag/channel 보존, shared weight, multi-channel reduction, result routing, random stall과 Yosys hierarchy check를 포함한다.

## Physical flow

OpenROAD config는 `flow/designs/sky130hd/stob_pim2/config.mk`이며 `full_pim_system_top`을 축소 파라미터로 합성·배치·배선한다. 축소 physical instance의 PPA를 기본 64-channel 전체 구성의 PPA로 해석하면 안 된다.
