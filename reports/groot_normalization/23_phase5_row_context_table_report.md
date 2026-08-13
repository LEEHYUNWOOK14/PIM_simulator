# Phase 5 — tag 기반 정규화 row-context table

## 목적

8개 scalar engine의 응답이 요청 순서와 달라져도 해당 row의 활성 bank mask를 정확히 복원하기 위해 `tag→target_mask` context table을 구현했다.

## 구현 및 검증

- RTL: `rtl/normalization_row_context_table.sv`
- 기본 후보: 16 banks, 16 entries, 16-bit tag
- free-entry allocation, tag 조합 lookup, 응답 소비 시 entry 반환
- 중복 활성 tag는 allocation을 막고 sticky 오류를 발생시킨다.
- lookup miss도 sticky 오류로 검출한다.

기능 결과:

```text
NORMALIZATION_ROW_CONTEXT_TABLE_TB PASS entries=4 out_of_order=1 duplicate=1 miss=1
```

세 개 context를 입력 순서와 다르게 `7002→7000→7001` 순으로 조회·반환했으며 mask 일치를 확인했다.

## generic synthesis

16-bank/16-entry 결과:

| Metric | Value |
|---|---:|
| Generic cells | 4,828 |
| Wires | 4,283 |
| Wire bits | 4,945 |
| Port bits | 73 |
| Yosys strict check | PASS |

조합 비교 구조이므로 entry 수에 따라 tag compare/mux 비용이 증가한다. 수치는 generic synthesis proxy이고 SRAM/CAM macro나 물리 timing 결과가 아니다.

## 판정

- **RTL_MEASURED:** 서로 다른 mask를 가진 in-flight row를 tag로 out-of-order 재결합할 수 있다.
- 중복 tag를 허용하지 않으므로 시스템은 tag를 entry 반환 전까지 재사용하면 안 된다.
- 다음 단계에서 raw-to-scalar top의 config handshake와 context allocation을 원자적으로 묶고, scalar response lookup/consume을 broadcast 수락과 묶는다.
