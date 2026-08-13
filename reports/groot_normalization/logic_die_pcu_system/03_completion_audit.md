# Logic-die PCU 시스템 목표 완료 감사

| 요구사항 | 구현/증거 | 판정 |
|---|---|---|
| 기존 결과를 새 시스템 목표로 재분류 | `00_system_objective_reclassification.md`에서 유지/재해석/제외 항목과 새 gate 명시 | 완료 |
| 계층형 traffic model 추가 | `analyze_logic_die_pcu_system.py`, `hierarchical_traffic.csv`; bank-array, bank↔logic, external 분리 | 완료 |
| cycle simulator에 bank/replay/write-back 추가 | 세 port mode, scalar queue, context, replay/apply/write-back event와 stall 모델 구현; unit test 4개 PASS | 완료 |
| 기존 RTL 코어에 PCU top 데이터 경로 연결 | `logic_die_normalization_pcu_top.sv`; invocation→reduction→scalar→replay→write-back 연결 | 완료 |
| top-level interface/backpressure 검증 | 4/8/16-lane interface TB PASS, replay request 5-cycle stall 및 byte counter exact 검사 | 완료 |
| 실제 trace 정확도 검증 | 18 lane/profile 조합, lane당 21,534,720 weighted elements, mixed-model mismatch 0 | 완료 |
| 4/8/16-lane 후보 재판정 | `rtl_candidate_decision.json`; 8-lane/4-scalar/16-context 선정 | 완료 |
| 특정 공정 없이 hardware cost 비교 | FP unit 수와 state bit 기반 relative cost 공개 | 완료 |

## 남은 위험 — 완료 범위 밖이지만 freeze 시 명시할 조건

- trace는 action-head synthetic boundary capture이며 full GR00T inference가 아니다.
- current top은 reduction, replay, write-back 독립 포트를 노출한다. 실제 memory controller가 이를 serialize하면 single/shared 또는 split-RW model 범위로 cycle이 증가한다.
- 상대 비용은 공정 독립 구조 proxy이며 절대 면적·전력 수치가 아니다.
- full-model trace가 확보되면 lane 재선정보다는 workload weighting만 다시 계산해야 한다. RTL과 모델은 동일하게 재사용할 수 있다.

위 제한은 목표의 산출물 누락이 아니라 evidence scope의 경계다. 지정된 다섯 요구사항은 현재 worktree의 실행 결과로 모두 입증됐다.

