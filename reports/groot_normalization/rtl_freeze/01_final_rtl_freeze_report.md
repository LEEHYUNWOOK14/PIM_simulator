# Logic-die Normalization PCU RTL 최종 동결 보고서

작성일: 2026-08-12  
검증 범위: 공정·배치배선 제외, RTL 기능·cycle·구조적 하드웨어 비용

## 1. 결론

현재 프로젝트 범위에서 RTL 구조를 다음과 같이 동결한다.

| 항목 | 최종값 | 판정 근거 |
|---|---:|---|
| bank interface | split read/write | reduction/replay는 read slot 1개 공유, write-back은 별도 backpressured path |
| read arbitration | fair round-robin | 양쪽이 계속 요청해도 split mode 최대 대기 1 cycle |
| write-back | read와 동시 진행 | output FIFO drain이 read slot을 소모하지 않음 |
| vector lanes | 8 | 256-bit bank word의 50%인 128 bit/cycle 공급률 하한 충족 |
| scalar engines | 4 | 현재 reducer/global-tree 공급률에서 검증된 기본값 |
| top contexts | 8 | 16보다 상태가 작고 실제 trace cycle도 개선 |
| local reduction contexts | 2 | 4개로 늘려도 RMS 128/2048 cycle 이득 0 |
| apply FIFO depth | 16 | depth 8은 41×1536 trace에서 2.8% 성능 저하 |
| traffic counter width | 32 bit | 기존 64 bit 대비 192 state bits 절감, 현재 전체 workload byte 범위 수용 |

따라서 질문에 대한 정확한 답은 다음과 같다. **architecture 선택과 필수 RTL 최적화는 완료됐고, 이 보고서가 정의한 범위에서는 RTL freeze가 가능하다.** 남은 것은 공정·물리 구현 또는 실제 제품 memory-controller protocol에 맞춘 adapter처럼 현재 범위 밖의 후속 통합 작업이다.

## 2. Bank interface 확정

새 `normalization_bank_scheduler`를 `logic_die_normalization_pcu_top` 내부에 연결했다.

- reduction read와 replay read는 동일한 bank read service slot을 공유한다.
- 두 read가 동시에 대기하면 round-robin으로 중재한다.
- write-back은 별도 경로이므로 bank가 ready이면 read와 같은 cycle에 진행한다. 이는 split-R/W에서 write-back에 전용 우선권을 준 것과 같다.
- 보수적인 비교용 `SHARED_RW_PORT=1`도 유지한다. 이 mode에서는 write-back 우선이며, age limit에 도달한 read가 우선권을 넘겨받는다.
- 16개 bank가 모두 valid/ready일 때만 lockstep transaction을 발행한다. 일부 bank만 도착한 skew 상태에서는 아무 bank도 먼저 소비하지 않는다.
- `STARVE_LIMIT` age counter, grant/conflict/skew counters, sticky protocol error를 구현했다.

스트레스 결과:

| mode | random BP | reduction grants | replay grants | write grants | conflicts | skew | 최대 read 대기 |
|---|---:|---:|---:|---:|---:|---:|---:|
| split-R/W | 128 cycles | 40 | 46 | 63 | 53 | 9 | 1/1 cycles |
| single shared | 128 cycles | 26 | 27 | 56 | 53 | 9 | 7/8 cycles |

기본값은 split-R/W다. 독립 reduction/replay read port를 가정한 이전 구조는 실제 bank bandwidth를 낙관적으로 계산하므로 최종 정책에서 제외했다.

## 3. 4/8/16-lane 최종 판정

### 처리량 하한

현재 bank data width는 256 bit, 즉 BF16 16개다. PCU가 최소 한 개의 128-bit slice를 매 active bank cycle에 받을 수 있어야 한다는 하한을 정했다.

| lanes | bank당 폭 | bank word 사용률 | 하한 판정 |
|---:|---:|---:|---|
| 4 | 64 bit | 25% | FAIL |
| 8 | 128 bit | 50% | PASS |
| 16 | 256 bit | 100% | PASS, 비용 과다 |

실제 41×1536 action trace에서 4-lane은 2063 cycles, 8-lane은 1065 cycles로 8-lane이 1.937배 빠르다. 전체 action workload split-R/W cycle model에서도 4/8/16-lane은 각각 683,989 / 358,483 / 248,055 weighted cycles이며, 8-lane은 4-lane 대비 1.908배다.

공정 독립 구조 비용 proxy는 4/8/16-lane 각각 847.875 / 1503.875 / 2815.875 units다. 16-lane은 8-lane보다 비용이 1.873배인데 split-R/W model 성능 이득은 1.445배뿐이다. 또한 width 128은 8-lane에서 bank당 정확히 8개 원소라 utilization 100%지만, 16-lane에서는 50%다.

따라서 **8-lane을 최종 선택하고 16-lane은 parameter 검증용으로만 유지**한다.

## 4. RMSNorm 및 AdaLayerNorm 검증

대표 BF16 RMSNorm vectors를 width 128과 2048에 대해 생성했다. 입력 평균을 0이 아니게 하고 gamma를 비균일하게 만들어 LayerNorm과 RMSNorm을 구분했으며, beta에도 큰 non-zero 값을 넣어 RMSNorm의 beta 생략을 확인했다.

| mode | shape | mixed golden mismatch | FP32 reference mismatch | top cycles | max contexts |
|---|---|---:|---:|---:|---:|
| RMSNorm | 8×128 | 0 | 0 | 200 | 8 |
| RMSNorm | 4×2048 | 0 | 0 | 196 | 4 |
| AdaLayerNorm-style per-row affine | 8×128 | 0 | 0 | 224 | 8 |

추가 scalar-only 측정은 RMSNorm 51 cycles, LayerNorm 63 cycles다. RMS response mean은 `0x00000000`으로 확인됐다. width 128은 16 banks × 8 lanes와 정확히 일치해 padding이나 유휴 lane 없이 utilization 100%다.

## 5. 적용한 RTL 최적화

### 적용

1. **context 16→8**
   - 280×2048: 9532→9017 cycles, 5.4% 개선
   - 41×1536: 1120→1065 cycles, 4.9% 개선
   - core/wrapper context state 약 1,176 bits 절감 및 comparator/mux fan-in 절반
   - context가 reduction look-ahead를 제한해 replay가 과도하게 지연되는 현상도 줄였다.

2. **traffic counter 64→32 bit internal state**
   - 외부 관찰 interface는 64 bit zero-extension으로 유지했다.
   - 6개 counter에서 총 192 state bits를 줄였다.

3. **scalar engine combinational loop 제거**
   - request-ready가 response-ready에 조합적으로 되먹임되던 경로를 제거했다.
   - response register를 명확한 1-entry buffer로 사용한다.
   - Verilator `UNOPTFLAT` 경고가 1건에서 0건으로 줄었다.

4. **scheduler 기반 overlap**
   - reduction/replay는 실제 shared read bandwidth 안에서 overlap한다.
   - write-back은 read와 병렬로 drain한다.
   - multi-row 회귀에서 overlap 동작을 확인했다.

5. **parameter 정리**
   - local reduction context와 apply FIFO depth를 top parameter로 노출해 비용/성능 sweep을 재현 가능하게 했다.

### 측정 후 기각

| 후보 | 결과 | 최종 판정 |
|---|---|---|
| local reduction contexts 2→4 | RMS width 128/2048 모두 200/196 cycles로 이득 0 | 2 유지 |
| apply FIFO 16→8 | 41×1536에서 1065→1095 cycles, 2.8% 저하 | 16 유지 |
| replay 고정 우선 arbitration | 41×1536에서 1120→1180 cycles로 악화 | round-robin 유지 |
| lane clock gating 추가 | target width 128/1536/2048은 8-lane에 정확히 나누어져 유휴 lane 없음; mux/control만 증가 | 추가하지 않음 |
| context/scalar table 병합 | 두 table의 수명이 다름: scalar context는 scalar issue 때 종료, wrapper context는 최종 bank write-back까지 유지 | 안전성 때문에 유지 |

## 6. Freeze 검증 결과

| 요구사항 | 결과 | 직접 증거 |
|---|---|---|
| LayerNorm 정확도 | PASS | 4/8-lane action trace mixed mismatch 0 |
| RMSNorm 정확도 | PASS | width 128/2048 mismatch 0 |
| AdaLayerNorm 정확도 | PASS | per-row gamma/beta 8×128 mismatch 0 |
| 4/8-lane regression | PASS | 2063 / 1065 cycles, protocol error 0 |
| random backpressure | PASS | scheduler 128 random cycles, apply/top stall tests |
| bank skew/conflict | PASS | skew 9, conflicts 53, partial issue 0 |
| context full/tag wrap | PASS | tags `fffe, ffff, 0000, 0001`, full backpressure 및 recovery |
| reset during transaction | PASS | reduction 중 reset 후 context/counter/pipeline clear 및 재실행 |
| cycle model vs RTL | PASS | 5 representative cases에서 absolute error ≤3% |
| traffic counters | PASS | activation/affine/writeback/partial/scalar/external byte exact assertions |
| lint | PASS with reviewed warnings | Verilator exit 0, `UNOPTFLAT=0`; arithmetic width/unused warnings은 기존 명시적 구현 특성 |
| generic synthesis | PASS | Yosys `check`: 0 problems, top structural elaboration 성공 |

Yosys generic result는 공정 면적이 아니라 구조 검증용이다. 최종 8-lane hierarchy에는 16 bank reducers, 16 apply pipes, 4 scalar engines, 1 global reducer, 1 scheduler가 포함되며 top hierarchy는 200,010 generic cells로 elaboration됐다.

## 7. Cycle model 일치 범위

Cycle model은 split-R/W, global reducer single-in-flight, scalar latency 51/63, local context 2, top context 8, row handoff를 반영한다.

| case | RTL | model | 오차 |
|---|---:|---:|---:|
| RMS 8×128 | 200 | 206 | +3.0% |
| RMS 4×2048 | 196 | 196 | 0.0% |
| Ada/LN 8×128 | 224 | 221 | -1.3% |
| LN 41×1536 | 1065 | 1067 | +0.19% |
| LN 280×2048 | 9017 | 9007 | -0.11% |

이는 cycle-exact microarchitecture simulator가 아니라 transaction-level model이므로 freeze gate를 ±3%로 정의했다. 해당 gate는 자동 단위 테스트로 고정했다.

## 8. 남은 작업

### 현재 RTL freeze 범위 안

필수 작업은 남아 있지 않다. 기능, arbitration, accuracy, parameter regression, stress, cycle, counter, lint, generic synthesis gate를 모두 통과했다.

### 향후 선택 작업

- 특정 HBM/DRAM controller의 실제 command/credit protocol에 맞춘 adapter
- clock-gating cell 삽입과 power intent는 전력 최적화를 목표에 포함할 때만 수행
- 경고 0개 정책이 필요하면 기존 FP32 primitive의 width cast와 unused generate signal 정리
- 공정, STA, floorplan, thermal, GDS 검증은 사용자가 명시적으로 제외한 범위

이 후속 항목은 현재 구조 선택을 다시 처음부터 수행해야 하는 작업이 아니다. freeze된 scheduler/PCU boundary 바깥의 구현 상세 또는 물리 검증이다.

## 9. 재현 방법과 증거 파일

전체 freeze regression:

```bash
bash verification/groot_normalization/run_logic_die_pcu_freeze_regression.sh
```

주요 증거:

- `reports/groot_normalization/rtl_freeze/freeze_regression.log`
- `reports/groot_normalization/rtl_freeze/yosys_generic_synthesis.log`
- `reports/groot_normalization/results/logic_die_pcu_system_scheduler/system_decision.json`
- `reports/groot_normalization/results/logic_die_pcu_system_scheduler/lane_system_dse.csv`
- `reports/groot_normalization/results/rmsnorm_l8_vectors/numerical_accuracy.csv`
- `reports/groot_normalization/results/adalayernorm_l8_vectors/accuracy.csv`
