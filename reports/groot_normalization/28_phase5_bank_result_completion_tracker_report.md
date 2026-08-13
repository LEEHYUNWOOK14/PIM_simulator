# Phase 5 — Bank-PCU 최종 result row-completion tracker

## 목적

Bank-PCU adapter의 `transaction_done`은 마지막 명령이 수락된 시점일 뿐 최종 `M_OUT`의 write-back 완료가 아니다. 이를 분리하기 위해 실제 최종 result handshake를 tag와 expected bank mask 기준으로 추적하는 completion tracker를 구현했다.

## 구현

- RTL: `rtl/normalization_bank_result_tracker.sv`
- 기본 후보: 16 banks, 16 in-flight entries, 16-bit tag
- config 시 `tag + expected bank mask`를 할당한다.
- bank별 최종 result handshake를 received mask에 기록한다.
- expected mask 전체가 수신된 row만 completion ready/valid로 내보낸다.
- 여러 row의 bank result가 섞이거나 row 완료 순서가 바뀌어도 tag로 재결합한다.
- completion consumer stall 동안 완료 tag를 보존한다.
- duplicate tag, unknown tag, duplicate/unexpected bank, zero mask를 sticky 오류로 검출한다.

## 기능 검증

```text
NORMALIZATION_BANK_RESULT_TRACKER_TB PASS entries=4 out_of_order=1 completion_stall=1 errors=4
```

두 row `0xc000(mask 0101)`과 `0xc001(mask 1010)`의 bank result를 교차 입력했다. 첫 completion을 stall한 뒤 두 번째 row를 완료했으며, 정상 tag/mask 완료와 네 오류 경로를 확인했다.

## generic synthesis

16 banks / 16 entries 결과:

| Metric | Value |
|---|---:|
| Generic cells | 15,283 |
| Wires | 14,242 |
| Wire bits | 15,592 |
| Port bits | 346 |
| Yosys strict check | PASS |

조합 tag lookup과 entry별 bank mask가 generic gates로 전개된 수치다. 실제 CAM/register-file 또는 physical implementation 비용이 아니다.

## 판정과 제한

- **RTL_MEASURED:** 실제 final-result handshake를 기준으로 out-of-order row completion을 안전하게 정의할 수 있다.
- tracker는 result data를 저장하지 않는다. data는 handshake와 동시에 별도 write-back 경로가 받아야 한다.
- 실제 Bank-PCU top에는 아직 tracker를 연결하지 않았다. 연결 시 intermediate result는 즉시 소비하고 `M_OUT`만 tracker/write-back backpressure를 적용해야 한다.
- 동일 tag는 completion entry가 반환되기 전에 재사용할 수 없다.

## 다음 작업

`hierarchical_normalization_bank_core_top`의 config 수락과 tracker allocation을 원자적으로 묶고, Bank-PCU의 intermediate result와 final `M_OUT` ready를 분리하여 최종 row-completion 출력까지 통합한다.
