# Phase 5 Completion Tracker Bank-PCU Top Integration Report

작성일: 2026-08-11

## 결론

`normalization_bank_result_tracker`를 `hierarchical_normalization_bank_core_top`에 통합했다. 이제 row completion은 microprogram 명령 수락이나 중간 GRF 결과가 아니라, 활성 bank의 최종 affine `M_OUT`이 외부 write-back ready와 handshake된 뒤에만 발생한다.

2개 row와 4개 활성 bank를 사용한 축소 E2E 테스트에서 두 row가 동시에 in-flight인 상태로 실행됐고, 먼저 할당된 row의 한 bank write-back을 stall하여 나중 row가 먼저 완료되는 out-of-order completion을 확인했다.

## 변경 범위

### Top-level RTL

변경 파일:

- `rtl/hierarchical_normalization_bank_core_top.sv`

추가된 주요 인터페이스:

- `row_completion_valid_o`
- `row_completion_ready_i`
- `row_completion_tag_o`
- `final_result_unknown_tag_error_o`
- `duplicate_final_result_error_o`
- `RESULT_TRACKER_ENTRIES`

config 경로는 다음과 같이 연결했다.

```text
external config
  ├─ issue path ready
  └─ result tracker allocation ready
       ↓
두 ready가 모두 성립한 동일 cycle에만 config 수락 및 tracker allocation
```

tracker가 full이거나 동일 tag가 이미 존재하거나 expected mask가 0이면 issue path로 config가 전달되지 않는다. 따라서 issue context만 생성되거나 tracker entry만 생성되는 부분 수락을 방지한다.

### Final-result 분류와 ready 경로

Bank-PCU 결과 중 destination이 `PIM_OPD_M_OUT`인 결과만 final result로 분류한다.

```text
intermediate GRF/A_OUT result
  → 기존 external result_ready만 적용

final M_OUT result
  → external result_ready AND tracker bank_result_ready
  → 두 조건이 모두 성립할 때 Bank-PCU와 tracker가 같은 결과를 소비
```

tracker 입력 valid에도 external `result_ready_i`를 포함했기 때문에 downstream write-back이 stall된 동안에는 received mask가 증가하지 않는다. `transaction_done_o`는 microprogram command issue 완료를 나타낼 뿐 row completion 조건으로 사용하지 않는다.

### Error 연결

- issue path와 tracker의 duplicate-tag 오류는 `duplicate_tag_error_o`로 합쳤다.
- zero target/mask 오류는 `zero_target_error_o`로 합쳤다.
- 최종 결과의 unknown tag와 duplicate/unexpected bank는 별도 출력으로 노출했다.

## Row lifecycle

```text
config valid/ready handshake
→ issue context와 tracker entry 동시 allocation
→ Bank reduction 및 Logic scalar finalize
→ Bank-PCU microprogram 실행
→ intermediate result는 외부에서 즉시 소비
→ final affine M_OUT write-back handshake
→ tracker received bank mask 갱신
→ expected mask 전체 수신
→ row completion valid/tag 출력
→ completion ready handshake 후 entry 해제 및 재사용
```

현재 축소 E2E에서는 활성 bank마다 한 번의 최종 `M_OUT`을 생성하므로 tracker의 expected count는 bank mask의 bit별 1개이다.

## 검증

### Bank-PCU top 통합 테스트

명령:

```bash
bash verification/groot_normalization/run_hierarchical_normalization_bank_core_top_test.sh
```

결과:

```text
HIERARCHICAL_NORMALIZATION_BANK_CORE_TOP_TB PASS
rows=2 active_banks=4 results=12 completions=2
out_of_order=1 tracker_full=1 writeback_stalls=1 active_reset=1 cycles=53
```

검증 항목:

- RMSNorm row와 LayerNorm row 동시 in-flight
- 활성 bank mask가 서로 다른 2개 row
- 먼저 할당한 row의 최종 bank write-back stall
- 나중 row가 먼저 완료되는 out-of-order completion
- stall된 최종 결과가 handshake되기 전 조기 completion 없음
- intermediate 결과가 tracker completion count에 포함되지 않음
- tracker 2-entry full 상태에서 세 번째 config backpressure
- active row가 있는 상태의 reset
- reset 이후 stale completion 없음
- reset 이후 config ready 복구
- 최종 affine 데이터와 bank mask 검증

### Tracker 단위 stress 테스트

명령:

```bash
bash verification/groot_normalization/run_normalization_bank_result_tracker_test.sh
```

결과:

```text
NORMALIZATION_BANK_RESULT_TRACKER_TB PASS
entries=4 completions=4 out_of_order=1 completion_stall=1
full=1 active_reset=1 missing_wait=1 reuse=1 errors=4
```

검증 항목:

- out-of-order bank result
- completion output backpressure
- unknown tag
- duplicate bank result
- duplicate allocation tag
- zero expected mask
- entry full backpressure
- active entries reset
- expected bank 누락 시 completion 대기
- completion 후 entry 재사용

### 전체 normalization 테스트 회귀

명령:

```bash
bash verification/groot_normalization/run_foundation_regression.sh --tests-only
```

결과:

```text
FOUNDATION_REGRESSION TESTS PASS
summary=reports/groot_normalization/results/foundation_regression_results.csv
```

모든 `verification/groot_normalization/run_*_test.sh` 테스트가 통과했다.

## 합성 검증

명령:

```bash
bash verification/groot_normalization/run_hierarchical_normalization_bank_core_top_synthesis.sh
bash verification/groot_normalization/run_normalization_bank_result_tracker_synthesis.sh
```

결과:

```text
HIERARCHICAL_NORMALIZATION_BANK_CORE_SYNTHESIS PASS banks=4,16 lanes=4 engines=8
NORMALIZATION_BANK_RESULT_TRACKER_SYNTHESIS PASS banks=16 entries=16
```

Yosys generic cell 결과:

| 구성 | Generic cells |
|---|---:|
| Bank-PCU top, 4 banks, 4 lanes, 8 scalar engines | 1,149,903 |
| Bank-PCU top, 16 banks, 4 lanes, 8 scalar engines | 4,104,658 |
| Completion tracker, 16 banks, 16 entries | 15,283 |

원시 로그:

- `reports/groot_normalization/results/hierarchical_normalization_bank_core_b4_l4_e8_yosys.log`
- `reports/groot_normalization/results/hierarchical_normalization_bank_core_b16_l4_e8_yosys.log`
- `reports/groot_normalization/results/normalization_bank_result_tracker_b16_e16_yosys.log`

이 수치는 Yosys generic synthesis 결과다. GRF와 내부 memory가 register/mux로 전개되므로 technology-mapped 면적, 주파수 또는 전력 수치로 사용하면 안 된다.

## 알려진 한계

- 현재 Bank-PCU top은 외부 `activation_data_i`를 직접 사용한다. production replay buffer와 DRAM read/replay/write-back 경로는 아직 없다.
- 현재 축소 E2E는 활성 bank당 final `M_OUT` 1개를 추적한다. 여러 replay vector 또는 주소를 bank별로 순회하는 production 경로에서는 `(tag, bank, vector/address)` 단위 count 또는 packet identity 확장이 필요하다.
- 중복/누락 검출은 현재 bank bit 기준이다. 동일 bank에서 여러 final vector를 허용하려면 tracker 구조를 count 기반으로 확장해야 한다.
- `EVEN_BANK` 고정 operand를 even/odd bank 및 vector address 순회로 확장하는 작업은 포함하지 않았다.
- 실제 DRAM write completion 신호가 없으므로 이번 단계의 write-back 완료는 top 외부 `result_valid_o && result_ready_i` handshake로 정의했다.
- 합성 통과는 구조적 합성 가능성 증거이며 timing closure나 physical PPA 증거가 아니다.

## 다음 작업

다음 우선순위는 activation replay와 실제 DRAM write-back 경로다.

1. reduction에 사용한 activation의 tag/address를 replay buffer에 보존한다.
2. Bank-PCU apply가 동일 activation을 even/odd bank와 vector address 순서로 재생하도록 한다.
3. final result를 DRAM write command/data/response 경로에 연결한다.
4. tracker를 bank mask 방식에서 bank별 vector/address count 방식으로 확장한다.
5. 실제 DRAM write response handshake를 row completion 조건으로 교체한다.

## 완료 판단

이번 목표의 축소 E2E 범위에서 다음 조건을 충족했다.

- tracker가 실제 Bank-PCU top에 통합됨
- config acceptance와 tracker allocation이 원자적으로 연결됨
- tracker full 시 config backpressure 확인
- intermediate 결과와 final `M_OUT` 구분
- 실제 외부 write-back handshake 이후에만 completion count 증가
- 여러 row의 out-of-order completion 확인
- downstream stall에서 결과 누락과 조기 completion 없음
- active reset 이후 stale completion 없음
- 전체 normalization 테스트 회귀 통과
- 4/16-bank top 및 16×16 tracker generic synthesis 통과

Production replay 및 DRAM write-back 완료 조건은 다음 Phase 5 작업으로 남긴다.
