# Full-PIM physical integration output

`output.gds`는 저장소의 `full_pim_system_top` RTL을 Yosys, OpenROAD-flow-scripts,
sky130hd 및 KLayout으로 처리해 생성한 물리 통합 검증용 GDS다.

- physical top: `full_pim_system_top`
- physical parameters: 1 channel, 1 bank, 1 bank-PIM block, 1 logic PCU
- datapath: FP16 16-bit, 1 row, 1 column, CRF depth 2, shared weight buffer 16 bytes
- die bbox: 1536.465 um x 1536.465 um
- standard/physical components before stream merge: 87,994
- detailed-route wire length: 4,680,498 um
- detailed-route vias: 629,210
- KLayout cell count: 285
- file size: 125,315,900 bytes
- SHA-256: `C1BC8C4561D34112DB9DFE2C647C4D006F011E166AA73F2127EF342026E75CF1`

KLayout batch 검사는 top cell이 `full_pim_system_top`이고 bbox가 비어 있지 않음을
확인한다. `tools/open_output_gds.cmd`로 열 수 있다.

## 사용 범위

이 산출물은 **수정된 Full-PIM RTL이 합성·배치·배선·GDS 변환 흐름에 실제로
연결됨을 증명하는 integration artifact**다. 테이프아웃 signoff 결과가 아니다.
재현 시간을 제한하기 위해 `DETAILED_ROUTE_END_ITERATION=0`으로 초기 상세배선 뒤
종료했으며, 최종 상세배선 보고서에는 DRC 274,099건과 antenna net/pin 위반
602/743건이 남아 있다. 따라서 이 GDS로 DRC-clean, timing closure 또는 signoff PPA를
주장해서는 안 된다.
