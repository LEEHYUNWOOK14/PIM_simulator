# 04. 합성·Formal·물리설계 일관성

## Yosys 결과

|대상|구성|검사|결과|
|---|---|---|---|
|`bank_pim_core`|DATA_WIDTH=32|full generic synth + check|PASS, 22,674 cells, 0 problems|
|`logic_pcu_scheduler`|2 PCU, DATA_WIDTH=32|full generic synth + check|PASS, 28,716 cells, 0 problems|
|`full_pim_system_top`|2ch/4bank/2PB/2PCU/DW32|hierarchy + check|PASS, 7,031 hierarchical cells, 0 problems|
|`full_pim_system_top`|default 64ch|hierarchy + check|RESOURCE/ENV FAILURE|

로그는 `verification/rtl_audit/*.log`에 있다. reduced full top은 behavioral DRAM을 gate로 flatten하지 않았다.

합성 성공은 다음 기능 결함을 찾지 못했다: FP16 오연산, stalled response overwrite, epoch bypass, channel/tag 오연결, CRF infinite loop. 따라서 구조 `check` 0건은 기능 PASS가 아니다.

## Formal

Yosys SAT로 `logic_result_router`의 조합 routing, mutual exclusion, ready 선택 및 payload 복제를 모든 입력 조합에 대해 증명했다 (`sat -prove ok 1 -verify`: SUCCESS). 그러나 이 router는 Full-PIM top에 연결되지 않는다.

SymbiYosys는 설치되지 않았다. FIFO/arbiter/reduction/순차 valid-ready end-to-end property는 `NOT RUN`이다.

## 현재 물리 flow와 Full-PIM RTL 비교

|항목|현재 GDS/flow|감사 대상 Full-PIM RTL|
|---|---|---|
|Top|`logic_die_64ch_reduction_top_pwrwrap`|`full_pim_system_top`|
|범위|1 logic-die channel, 2 PIM banks, 16-bit reduction wrapper|64 channel, 16 bank/channel, 8 PB/channel, 16 logic PCU|
|RTL source path|repository junction으로 문서화된 `/mnt/c/orfs/rtl/*.sv` wildcard|현재 workspace `rtl/*.sv`; 당시 hash manifest 없음|
|SDC|10 ns clock, reset false path|동일성 증명 없음|
|GDS 상태|route 0 violation 주장, antenna 3건|해당 GDS 없음|

따라서 현재 GDS/DEF는 Full-PIM RTL의 물리 구현으로 사용할 수 없다. 오래된 산출물이라기보다 다른 top과 축소 구성을 의도적으로 구현한 별도 artifact다.

## OpenROAD 준비도

- 기존 reduction wrapper: 제한적 visualization/P&R artifact 존재
- 신규 Full-PIM top: FAIL
- 실제 DRAM macro/PHY: 없음
- full top netlist/SDC/macro LEF/pin plan: 없음
- CDC/STA/DFT/DRC/LVS/antenna/IR/EM sign-off: 없음

현재 신규 Full-PIM RTL은 OpenROAD production physical design 준비 상태가 아니다.
