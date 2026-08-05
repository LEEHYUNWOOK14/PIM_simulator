# 69차 실험 보고서: Exclusive blocker와 첫 Architecture 변경 판단

> **폐기된 판단(71차 정정):** `bank_state_only=175229`는 실제 blocker가 아니라 empty-bank speculative PRECHARGE 계측 오염이었다. Direct staging 실험을 수행한 사실은 유효하지만 이 문서의 architecture 우선순위 근거는 사용하지 않는다.

## 1. 목적

Bank-state와 hierarchy predicate가 같은 cycle에 중복되는 문제를 제거하고, 첫 logic-die PIM architecture 변경 대상을 결정한다.

## 2. 분류 기준

| 지표 | 정의 |
|---|---|
| `hierarchy_union` | Epoch, barrier, write-bus, Rank mode, logic queue 중 하나 이상이 controller를 막은 상태 |
| `bank_all_no_hierarchy` | 모든 활성 채널에서 bank-state가 관찰됐고 hierarchy blocker는 한 채널에도 없는 cycle |
| `bank_all_with_hierarchy` | Bank-state all-active와 hierarchy blocker가 공존한 cycle |
| `bank_state_only` | Bank-state all-active이며 hierarchy, timing, row mismatch 등 다른 기록 원인이 없는 cycle |
| `hierarchy_all_no_issuability` | 모든 활성 채널이 hierarchy에 막혔지만 DRAM issuability 실패는 전혀 없는 cycle |
| `bank_hierarchy_all_intersection` | Bank-state와 hierarchy union이 모두 all-active인 cycle |

## 3. 재현 명령

```bash
LATENCIES=32 bash experiment/run_issuability_mode_latency_ab.sh
```

결과는 `experiment/results/global_exclusive_blocked_mode_latency_ab.csv`에 저장된다.

## 4. 결과

| 지표 | Cycle |
|---|---:|
| Total cycle | 235,182 |
| Hierarchy union any | 46,967 |
| Hierarchy union all-active | 41,359 |
| Bank all, hierarchy 없음 | 176,865 |
| Bank all, hierarchy 공존 | 42,780 |
| Bank-state only | 175,229 |
| Hierarchy all, issuability 문제 없음 | 0 |
| Bank/hierarchy 모두 all-active | 41,359 |

출력 18,816개가 모두 정확성 검증을 통과했다.

## 5. 핵심 해석

1. Bank-state only는 전체 실행의 약 74.51%다.
2. Hierarchy all-active 41,359 cycles는 전부 bank-state all-active와 겹친다.
3. Hierarchy만 존재하고 DRAM issuability 문제가 없는 all-active cycle은 0이다.
4. 따라서 epoch/barrier/write-bus 제어만 먼저 최적화해도 bank-state 문제가 그대로 남는다.
5. 첫 architecture 변경은 logic-die operand staging을 일반 bank row 상태에서 분리하는 것이 타당하다.

## 6. 첫 변경의 범위

다음 실험 기능을 기본값 OFF로 추가한다.

```ini
LOGIC_DIRECT_STAGING_COMMAND_PATH=false
```

ON일 때 `LOGIC_WEIGHT_FILL` transaction은 다음처럼 동작한다.

1. 일반 DRAM command queue 대신 logic-control command queue로 들어간다.
2. Bank ACT/PRE/open-row 조건을 요구하지 않는다.
3. 기존 data bus write 예약과 shared weight buffer write-port latency는 유지한다.
4. Weight 데이터와 완료 barrier 의미는 유지한다.

이 모델은 “무한 bandwidth로 즉시 채우기”가 아니다. Command frontend와 bank row-state 의존성만 분리하고 실제 데이터 이동 및 buffer write timing은 보존한다.

## 7. RTL 대응

Verilog에서는 logic-die shared weight buffer 앞에 다음 인터페이스가 필요하다.

```systemverilog
logic                    staging_valid;
logic                    staging_ready;
logic [STAGING_ADDR_W-1:0] staging_addr;
logic [STAGING_DATA_W-1:0] staging_data;
```

`staging_ready`는 DRAM bank의 `row_active`와 직접 결합하지 않는다. 다만 실제 HBM data path를 공유한다면 data bus arbitration과 buffer port ready는 계속 반영한다.

## 8. 검증 계획

1. 기존 OFF 경로의 cycle과 정확도가 유지되는지 확인
2. Direct staging ON에서 fill burst 수와 completed write 수가 동일한지 확인
3. Bank-state only와 fill ACT/PRE가 감소하는지 확인
4. Full UIB 출력 18,816개 정확성 확인
5. Total cycle과 stage별 expand/project 개선량 측정

## 9. 결론

Exclusive blocker 분석 결과 첫 변경 대상은 hierarchy barrier가 아니라 logic-die operand staging command path다. 다음 작업은 이 경로를 실험 플래그로 구현하고 OFF/ON A/B를 수행하는 것이다.
