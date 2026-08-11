# 05. 결함 등록부와 최종 판정

## 최종 판정

- 상태: **FAIL**
- 결론: 여러 정상-path 회귀와 축소 합성은 통과했지만, 재현 가능한 산술·프로토콜·제어·metadata 결함과 필수 top-level 경로 미통합 때문에 의도한 계층형 HBM2-PIM RTL로 안전하지 않다.
- production source 수정: 없음
- architecture/timing/resource 변경: 없음

## 핵심 결함

### AUD-001 — HIGH — FP16 multiplier가 C++ 수치 계약과 불일치

- 파일/module: `rtl/fp16_mul.sv:20-54`, `fp16_mul`
- 재현: `fp16_mul_random_audit_tb`, 4,217 vectors
- 기대: C++ `half.h`와 동일한 FP16 multiply
- 실제: 452 mismatch; `0001 × 3c00`이 `0001` 대신 `0401`
- 영향: MUL/MAC/MAD 기능 정확성
- 합성 검출: 아니오

### AUD-002 — HIGH — stalled DRAM read response overwrite

- 파일/module: `rtl/dram_bank_array_model.sv:54,94-103`, `dram_bank_array_model`
- 재현: `dram_read_backpressure_repro_tb`
- 기대: `valid && !ready` 동안 data 안정, 새 RD 미수락
- 실제: 두 번째 RD를 수락하고 첫 response data를 덮어씀
- 영향: transaction 유실·오연결
- 합성 검출: 아니오

### AUD-003 — HIGH — bank read-valid 없이 local PIM 실행

- 파일/module: `rtl/bank_side_pim_subsystem.sv:78-99`, `bank_pim_core.sv:81`
- 재현: `bank_operand_validity_repro_tb`
- 기대: 두 bank의 row data가 valid일 때만 명령 승인
- 실제: bank가 닫혀 있어도 result valid 발생
- 영향: X/미정 데이터의 architectural commit

### AUD-004 — HIGH — CRF finite JUMP가 무한 반복

- 파일/module: `rtl/pim_crf.sv:52-60`
- 재현: `crf_jump_repro_tb`, count=1/offset=1
- 기대: 한 번 jump 후 EXIT
- 실제: remaining이 0이 될 때 encoded count를 다시 load하여 영구 반복
- 영향: command stream hang

### AUD-005 — HIGH — illegal opcode가 error 없이 CRF deadlock

- 파일/module: `bank_pim_core.sv:81-82`, `bank_side_pim_subsystem.sv:91-92`
- 재현: `invalid_crf_deadlock_repro_tb` 및 연결 정적 추적
- 실제: ready=0, gated valid=0, error=0, PC 정지

### AUD-006 — HIGH — epoch/barrier가 dispatch를 gate하지 않음

- 파일/module: `rtl/logic_die_pim_top.sv:92,94-101,166-177`
- 재현: `logic_tag_channel_repro_tb`
- 실제: epoch begin/fill/release가 한 번도 없어도 result 발생
- 영향: weight/context 준비 전 실행 가능

### AUD-007 — HIGH — channel ID를 tag 하위 bit로 잘못 복원

- 파일/module: `rtl/logic_die_pim_top.sv:163-164`
- 재현: channel=1, tag=`0x100` → result channel=0
- 영향: 결과 source/destination 오연결

### AUD-008 — CRITICAL — 의도한 reduction/accumulator/result 경로가 Full-PIM top에 없음

- 파일/module: `rtl/full_pim_system_top.sv:89-189`
- 실제: `cross_channel_reduction`, `pim_local_accumulator`, `logic_result_router`, `logic_command_router` 미인스턴스; shared weight response도 PCU operand에 미연결
- 영향: multi-bank partial sum reduction과 최종 bank/host retirement라는 핵심 아키텍처가 end-to-end로 존재하지 않음
- 합성 검출: 사용되지 않은 별도 module은 top 합성에 들어오지 않으므로 검출하지 않음

### AUD-009 — HIGH — GDS가 감사 대상 Full-PIM RTL과 불일치

- 파일: `flow/designs/sky130hd/stob_pim2/config.mk`, `flow/README.md`, `output/README.md`
- 실제: physical top은 축소 `logic_die_64ch_reduction_top_pwrwrap`, Full-PIM top은 `full_pim_system_top`
- 영향: 현재 GDS로 Full-PIM PPA나 구현 완료를 주장할 수 없음

### AUD-010 — MEDIUM — CRF NOP/AUTO/FILL 반복 계약 누락

- 파일/module: `rtl/pim_crf.sv:48-61`
- 근거: `src/PIMRank.cpp:841-870`
- 실제: RTL CRF는 NOP loop count와 FILL/auto 8회 반복을 구현하지 않고 PC를 단순 증가

### AUD-011 — MEDIUM — parameter 값 1에서 zero-width interface

- 파일: 여러 module의 `$clog2(N)-1:0`
- 증거: `PIM_BLOCKS=1` compile 시 2-bit port padding warning
- 영향: 경계 parameter가 조용히 잘못 elaboration됨

### AUD-012 — MEDIUM — command/placement가 transaction과 함께 고정되지 않음

- 파일: `full_pim_system_top.sv:138-141`
- 실제: `bank_result_to_logic_i`를 결과가 stalled인 동안 다시 조합 평가해 경로를 바꿀 수 있음. `logic_command_router`도 top에 없음.

### AUD-013 — MEDIUM — DRAM timing 모델 범위 부족

- 파일: `dram_bank_array_model.sv`
- 실제: tRCD/tRAS/tRP 일부만 구현. REF는 상태/tRFC 효과가 없고 tWR/tCCD/tRRD/tFAW 등은 없음. `dram_command_decoder`는 subsystem에 연결되지 않음.
- 분류: controller reference model로서는 제한, 실제 HBM2 controller로는 미완성

### AUD-014 — LOW — 권위 설계 문서와 RTL README 인코딩 손상

- 파일: `design/logic_command_frontend_contract.md`, `design/logic_die_output_retirement_contract.md`, `rtl/README.md` 등
- 영향: 요구사항 해석과 리뷰 재현성 저하

## 질문별 판정

1. 검사한 연산의 기능 결과가 정확한가? **아니오. FP16 MUL/MAC/MAD 실패. ADD는 검사 범위 PASS.**
2. bank-specific/lockstep 동작이 맞는가? **부분적. pair/lockstep은 있으나 operand validity가 없음.**
3. local-to-logic 전송이 정확한가? **아니오. key 폐기와 channel/tag 오연결.**
4. reduction/accumulation이 정확한가? **standalone 일부 PASS, Full-PIM top end-to-end 미구현.**
5. valid/ready가 안전한가? **아니오. DRAM stalled response overwrite.**
6. clock/reset/CDC가 안전한가? **단일 clock이나 active reset stress/sign-off 미완료.**
7. Yosys가 핵심 논리를 보존하는가? **축소 block은 구조 PASS지만 기능 결함은 보존됨.**
8. 합성 구성과 GDS/DEF가 일치하는가? **아니오. top과 범위가 다름.**
9. OpenROAD 입력이 완전한가? **Full-PIM top 기준 아니오.**
10. 남은 미검증은? **64ch end-to-end, reset-active, INT8 계약, full formal, netlist equivalence 및 physical sign-off.**

## 가장 중요한 다음 prerequisite

아키텍처를 더 확장하기 전에 AUD-001~008의 기대 동작을 승인된 interface/ISA 계약으로 고정하고, 각각의 현재 failing regression을 유지한 채 production RTL의 최소 수정 권한을 부여해야 한다. 특히 Full-PIM top에 epoch-gated weight/operand dispatch → 16-PCU → cross-channel reduction/accumulation → result routing 경로를 명시적으로 연결하는 것이 최우선이다.
