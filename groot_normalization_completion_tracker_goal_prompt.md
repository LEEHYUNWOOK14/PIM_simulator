# 다음 작업 목표: Bank-PCU E2E에 Completion Tracker 통합

## 작업 디렉터리

`C:\Users\Admin\OneDrive\2026-summer\STOB_semiconductor_pim\STOB_PIM2`

기준 목표 문서는 `groot_normalization_rsqrt_goal_prompt.md`이다.

## 현재 상태

다음 기능은 구현되어 있다.

- Bank별 SUM/SUMSQ reduction
- bank arrival barrier 및 skew 처리
- Logic PCU 병렬 partial reduction tree
- FP16/BF16 RSQRT LUT
- tag 기반 row-context 복원
- bank별 scalar broadcast 및 backpressure
- RMSNorm/LayerNorm microprogram adapter
- 실제 Bank-PCU를 포함한 축소 raw-to-affine E2E
- 여러 in-flight row를 위한 `normalization_bank_result_tracker`

최근 통과한 핵심 테스트:

- `HIERARCHICAL_NORMALIZATION_BANK_CORE_TOP_TB PASS`
- `NORMALIZATION_BANK_RESULT_TRACKER_TB PASS`

## 목표

`rtl/normalization_bank_result_tracker.sv`를 실제 최상위 후보인
`rtl/hierarchical_normalization_bank_core_top.sv`에 통합한다.

row 완료는 중간 reduction 결과나 GRF write가 아니라 다음 조건을 만족할 때만 발생해야 한다.

```text
최종 affine M_OUT 생성
→ 최종 결과 write-back handshake 성립
→ tracker entry 완료
→ row completion event 발생
```

## 반드시 구현할 내용

### Tracker allocation

- config 수락과 tracker entry allocation을 원자적으로 연결한다.
- tracker가 full이면 config를 수락하지 않는다.
- allocation 실패 후 부분적으로 시작된 row가 남지 않게 한다.
- row tag, epoch, active bank mask, expected result count를 저장한다.

### 중간 결과와 최종 결과 구분

다음 결과를 구분한다.

- reduction partial result
- normalized intermediate result
- GRF write
- microprogram 완료
- 최종 affine `M_OUT`

중간 GRF 결과는 tracker 완료 조건으로 사용하지 않는다. 최종 affine 결과만 tracker에 전달한다.

### 최종 write-back handshake

최종 결과는 다음 조건이 성립한 cycle에만 소비한다.

```text
final_result_valid && final_result_ready
```

`valid`만 발생하고 downstream이 stall인 경우에는 row를 완료 처리하지 않는다.

### Expected result 및 out-of-order 처리

- row별 expected final result count를 관리한다.
- 모든 최종 결과가 write-back된 경우에만 row completion을 발생시킨다.
- 여러 row가 동시에 in-flight인 상황을 지원한다.
- bank별 backpressure와 서로 다른 완료 순서를 지원한다.
- 완료된 tracker entry를 즉시 안전하게 재사용할 수 있어야 한다.
- 중복 결과, 누락 결과, 잘못된 tag/epoch를 검출한다.

### Reset 및 backpressure

- tracker full backpressure
- final result downstream stall
- bank별 독립 backpressure
- reset 중 active row 정리
- reset 이후 stale completion 차단
- tag/epoch 재사용 충돌 방지

## 작업 순서

1. 작업 전후 `git status --short`를 확인한다.
2. 기존 사용자 변경사항과 새 파일을 삭제하거나 되돌리지 않는다.
3. 다음 파일의 현재 신호 흐름을 먼저 확인한다.

   - `rtl/hierarchical_normalization_bank_core_top.sv`
   - `rtl/normalization_bank_result_tracker.sv`
   - `rtl/normalization_row_context_table.sv`
   - `rtl/bank_normalization_microprogram_adapter.sv`
   - `verification/groot_normalization/hierarchical_normalization_bank_core_top_tb.sv`
   - `verification/groot_normalization/normalization_bank_result_tracker_tb.sv`

4. config, row context, final result, write-back 신호 흐름을 확인한다.
5. 필요한 최소 범위로 tracker 통합 RTL을 수정한다.
6. 최종 affine write-back handshake를 completion 조건에 연결한다.
7. 기존 테스트와 신규 stress 테스트를 실행한다.
8. 합성 가능성 또는 구조적 audit을 확인한다.
9. 결과를 보고서에 기록한다.

## 필수 검증

다음 테스트를 통과시킨다.

- 기존 tracker 단위 테스트
- 기존 Bank-PCU top-level 테스트
- 단일 row 정상 완료
- 여러 row 동시 in-flight
- 여러 bank out-of-order 완료
- final write-back stall
- tracker full
- 중간 GRF write만 발생하고 최종 M_OUT이 없는 경우
- final result 누락
- final result 중복
- 잘못된 tag/epoch
- reset 도중 active row
- 완료 직후 tracker entry 재사용

각 테스트에서 다음을 기록한다.

- row 수와 active bank 수
- expected final result count
- 실제 write-back count
- out-of-order 여부
- backpressure cycle
- tracker full 여부
- row completion cycle
- 중복·누락·tag 오류 수

## 산출물

다음 산출물을 만든다.

1. tracker 통합 RTL
2. top-level 통합 테스트벤치 또는 확장 테스트
3. out-of-order/backpressure stress 테스트
4. 테스트 실행 스크립트
5. `reports/groot_normalization/29_phase5_completion_tracker_top_integration_report.md`

보고서에는 변경 RTL, row lifecycle, allocation 조건, 최종 write-back completion 조건, backpressure 동작, out-of-order 처리, 테스트 결과, 합성/구조 검증 결과, 남은 한계를 기록한다.

## 완료 조건

- 실제 `hierarchical_normalization_bank_core_top`에 tracker가 연결되어 있다.
- config acceptance와 tracker allocation이 원자적으로 동작한다.
- tracker full 시 새 row가 수락되지 않는다.
- 중간 GRF 결과가 row completion을 발생시키지 않는다.
- 최종 affine M_OUT의 실제 write-back handshake만 completion count를 증가시킨다.
- 모든 expected final result write-back 이후에만 row가 완료된다.
- 여러 row의 out-of-order completion이 정상 처리된다.
- backpressure에서 결과 누락이나 조기 완료가 없다.
- reset 후 stale completion이 없다.
- 기존 회귀 및 신규 stress 테스트가 통과한다.
- 재현 명령과 결과가 보고서에 기록되어 있다.

## 범위 제한

- `git reset`, `git checkout`, 광범위한 삭제를 수행하지 않는다.
- 문서가 아니라 실제 RTL 연결과 테스트 결과를 기준으로 완료를 판단한다.
- activation replay, DRAM write-back, GPU 실측, technology PPA 분석은 이번 작업 범위에 포함하지 않는다.
