# AUD-009~014 수정 및 검증 결과

검증일: 2026-08-07

## 판정

| ID | 판정 | 핵심 증거 |
|---|---|---|
| AUD-009 | RESOLVED/VERIFIED (integration scope) | `full_pim_system_top` GDS 생성 및 KLayout top/bbox 검사 PASS |
| AUD-010 | RESOLVED/VERIFIED | NOP 4, FILL 8, AUTO 8, EXIT 1로 총 21 retire PASS |
| AUD-011 | RESOLVED/VERIFIED | CHANNELS/BANKS/PCUS/PIM_BLOCKS/ENTRIES/INPUTS=1 elaboration PASS |
| AUD-012 | RESOLVED/VERIFIED | stall 중 입력 route 변경에도 transaction route 유지 PASS |
| AUD-013 | RESOLVED/VERIFIED | tWR/tCCD/tRRD/tFAW/tRFC 및 read/write turnaround 테스트 PASS |
| AUD-014 | RESOLVED/VERIFIED | 설계 계약과 RTL README를 현재 hierarchy/동작으로 동기화하고 UTF-8 복구 |

## AUD-009 물리 통합 증거

OpenROAD top은 `full_pim_system_top`이다. 물리 증명 인스턴스는 1 channel, 1 bank,
1 bank-PIM block, 1 logic PCU, FP16 16-bit datapath의 최소 파라미터 구성이며 bank-side
PIM, logic PCU, shared weight, epoch/coalescer, reduction 및 result router 계층을 모두
유지한다.

- Yosys technology synthesis PASS
- synthesized gate netlist: `1_2_yosys.v`, 12,980,986 bytes
- gate netlist에서 `hold_route_q`, `repeat_active_q`, `refresh_busy_q` 보존 확인
- physical components: 87,994
- floorplan/PDN, placement, CTS, global route PASS
- routed ODB: `5_2_route.odb`, 86,749,001 bytes
- final ORFS GDS: `6_final.gds`
- copied artifact: `output/output.gds`, 125,315,900 bytes
- SHA-256: `C1BC8C4561D34112DB9DFE2C647C4D006F011E166AA73F2127EF342026E75CF1`
- independent KLayout check: `FULL_PIM_GDS PASS top=full_pim_system_top cells=285 bbox=(0,0;1536465,1536465)`

로컬 OpenROAD가 최신 ORFS의 일부 Tcl API를 제공하지 않아
`openroad_compat.tcl`을 PRE/POST hook으로 사용했다. 이 shim은 unsupported status/GUI
accessor와 placement option만 처리하며 RTL이나 합성 netlist를 변경하지 않는다.

## 물리 품질 한계

AUD-009의 원래 결함은 “GDS top이 감사 대상 Full-PIM top과 다르다”는 정합성
문제였으며, 위 증거로 닫혔다. 다만 이 산출물은 signoff GDS가 아니다.

- `DETAILED_ROUTE_END_ITERATION=0`
- detailed-routing violations: 274,099
- antenna violations: 602 nets / 743 pins
- 10 ns constraint 기준 timing 미수렴

따라서 GDS 연결성 증거와 DRC/timing closure를 혼동해서는 안 된다. 후자는 별도
물리 최적화 과제다.
