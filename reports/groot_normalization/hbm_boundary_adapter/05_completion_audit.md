# Normalization HBM boundary 목표 완료 감사

작성일: 2026-08-12  
자동 감사: `completion_audit.json` PASS

| 목표 요구사항 | 판정 | 증거 |
|---|---|---|
| simulator command/response 규격 확정 | PASS | `01_command_credit_and_mapping.md`; ACT/RD/WR/PRE/REF, timing, ready-valid 특수 계약, read credit 1 명시 |
| PCU transaction ↔ HBM command mapping | PASS | 128↔256-bit packing, x/affine/output column map, ACT→RD→WR→PRE 순서 문서화 |
| boundary adapter RTL 구현 | PASS | `rtl/normalization_hbm_boundary_adapter.sv` |
| 실제 bank timing/credit RTL simulation | PASS | LayerNorm/RMSNorm × hidden 128/2048, timing error 0, peak/final read credit 1/0 |
| 추상 cycle과 HBM-connected cycle 비교 | PASS | `02_cycle_comparison.csv`; 2048에서 21.01×/22.56× 차이 |
| adapter queue/arbitration 최적화 | PASS | credit=1에서 queue 증설 기각; packing/reuse/coalescing/same-row schedule로 data command 50% 감소 |
| 공급률 미달 후 PCU scheduler 재검토 | PASS | shared host-style channel topology가 원인임을 확인; 실제 internal HBM 규격 부재 상태에서는 8-lane freeze 유지 |
| RTL 합성 가능성 | PASS | Yosys `check`: 0 problems, 1,644 generic cells |

## 최종 구조 경계

- 재사용: `dram_bank_array_model`의 bank state, command legality, timing, response behavior
- 신규 구현: normalization PCU transaction packing, address mapping, command FSM, credit tracking, write coalescing
- 재사용 금지: 기존 combinational PIM read adapter를 production normalization boundary로 직접 사용
- 향후 교체점: 실제 HBM 내부 channel/credit/response-ID 규격이 확정되면 command/credit front-end를 교체

## 재현

```bash
bash verification/groot_normalization/run_normalization_hbm_boundary_test.sh
bash verification/groot_normalization/run_normalization_pcu_abstract_cycle_test.sh
yosys -p "read_verilog -sv rtl/normalization_hbm_boundary_adapter.sv; hierarchy -check -top normalization_hbm_boundary_adapter; proc; opt; check; stat"
python3 verification/groot_normalization/audit_normalization_hbm_boundary.py
```
