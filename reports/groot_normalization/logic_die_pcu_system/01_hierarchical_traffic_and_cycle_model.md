# 계층형 traffic 및 bank/replay/write-back cycle model

## Traffic 경계

Captured action-head schedule 269회에 대한 결과다.

| 경계 | Bytes | 판정 의미 |
|---|---:|---|
| GPU external baseline | 86,212,608 | activation read + output write + affine cold payload |
| Bank-only external | 3,374,080 | partial sum/sumsq 외부 반출 + mean/inv-std 반환 |
| Logic-die PCU external, resident | 8,608 | 269 × 32-byte invocation descriptor |
| Logic-die PCU external, cold affine | 82,336 | descriptor + affine parameter cold load |
| Bank-array reduction read | 43,069,440 | 첫 activation pass |
| Bank-array replay read | 43,069,440 | scalar 계산 후 두 번째 activation pass |
| Bank-array affine operand read | 86,138,880 | apply의 gamma/beta operand 소비 |
| Bank-array final write-back | 43,069,440 | normalization 결과를 bank에 저장 |
| Bank → logic partial | 1,687,040 | bank별 FP32 sum/sumsq |
| Logic → bank scalar | 1,687,040 | bank별 FP32 mean/inv-std |

Resident PCU 기준 외부 traffic 감소율은 **99.9900%**다. 내부 operand traffic은 215,347,200 B로 GPU external traffic보다 크지만, 이는 의도된 local data movement이므로 외부 I/O와 합산해 실패로 판정하지 않는다.

## Cycle model

`tools/analyze_logic_die_pcu_system.py`에 다음 event를 넣었다.

- bank reduction activation read
- reducer tail 및 global cross-bank reduction
- 4개 scalar engine queue/service
- activation replay
- 12-cycle apply pipeline
- final bank write-back
- context occupancy
- shared bank port에 따른 read/write stall

동일 workload를 세 bank-interface 가정으로 계산한다.

| 모드 | 의미 |
|---|---|
| `single_shared` | reduction read, replay read, write-back이 bank service slot 하나를 공유하는 보수적 bound |
| `split_rw` | reduction/replay가 read port를 공유하고 write port가 분리된 구조 |
| `independent_pcu_ports` | 현재 PCU top RTL처럼 reduction, replay, write-back ready/valid 경로가 각각 존재하는 optimistic interface bound |

| Lanes | Single shared cycles | Split R/W cycles | Independent model cycles |
|---:|---:|---:|---:|
| 4 | 1,010,525 | 676,188 | 371,253 |
| 8 | 506,594 | 339,708 | 231,756 |
| 16 | 256,583 | 228,408 | 226,599 |

이 모델은 주파수나 공정을 사용하지 않는다. 현재 top RTL의 실제 trace cycle과 비교했을 때 independent model 오차는 −6.1%~−11.9%이며, 최종 lane 선택에는 모델 추정치가 아니라 RTL 실측 cycle을 사용한다.

## 생성 산출물

- `reports/groot_normalization/results/logic_die_pcu_system/hierarchical_traffic.csv`
- `reports/groot_normalization/results/logic_die_pcu_system/lane_profile_cycles.csv`
- `reports/groot_normalization/results/logic_die_pcu_system/lane_system_dse.csv`
- `reports/groot_normalization/results/logic_die_pcu_system/system_decision.json`

