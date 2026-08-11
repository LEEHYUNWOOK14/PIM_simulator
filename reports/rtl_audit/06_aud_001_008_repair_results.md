# AUD-001~008 RTL 수정 및 재검증 결과

검증일: 2026-08-07

## 판정

AUD-001~008은 동작 계약을 확정한 뒤 production RTL에 수정했으며, 재현 테스트·기본 회귀·random stall·Yosys 구조 검사를 모두 통과했다. 이번 판정은 **AUD-001~008 RESOLVED/VERIFIED**이다. AUD-009~014는 별도 후속 범위로 남아 있으므로 전체 RTL에 대한 무조건적인 sign-off를 의미하지 않는다.

## 수정 요약

| ID | 반영 내용 | 검증 결과 |
|---|---|---|
| AUD-001 | FP16 multiply 정규화·subnormal·RNE 수정 | C++ `half.h` 4,217 vectors, mismatch 0 |
| AUD-002 | 미소비 read response가 있으면 후속 RD 수락 차단 | stalled data 안정성 및 두 번째 RD backpressure PASS |
| AUD-003 | 명령이 참조하는 even/odd bank별 valid를 ready에 반영 | 닫힌 bank에서 결과 미발생 PASS |
| AUD-004 | JUMP 진입 상태와 잔여 횟수를 분리 | count=1/offset=1, 5 retire 후 EXIT PASS |
| AUD-005 | illegal word를 error와 함께 retire | reserved opcode `A` error 관측 및 deadlock 없음 |
| AUD-006 | epoch release authorization을 dispatch 조건에 연결 | release 전 결과 없음, release 후 진행 PASS |
| AUD-007 | scheduler metadata에 `{tag, channel}` 독립 전달 | tag `0x100`, channel 1 보존 PASS |
| AUD-008 | cross-channel reduction, shared weight, result router를 full top에 연결 | 4채널 reduction 12.0 및 weight 기반 host 결과 4.0 PASS |

초기 AUD-005 테스트 설명의 “reserved opcode 9”는 잘못된 표기였다. 현재 ISA 상 `9`는 `FILL`이므로 실제 reserved opcode `A`로 바로잡아 검사했다.

## 실행 결과

- `rtl/run_full_pim_tests.sh`: 8/8 PASS
- `verification/rtl_audit/run_aud_001_008_regression.sh`: FP16 reference와 AUD positive regression 전부 PASS
- random stall: 40 batches, 320 raw PCU results PASS
- logic-die reduction: 네 채널의 3.0을 한 개의 12.0으로 축약, tag 보존 PASS
- full-system weight 경로: 외부 src1=2.0, shared weight=1.0 조건에서 4.0 산출 PASS
- `rtl/run_full_pim_synthesis.sh`: bank core, 2-PCU scheduler, 2-channel full top hierarchy/check PASS
- 합성 cell summary: bank core 24,611; scheduler 32,658; reduced full top 7,529

Yosys의 memory-to-register-array 경고는 남아 있으나 조합 loop 경고는 제거했다. 실제 SRAM/DRAM macro mapping과 timing closure는 이 RTL 기능 검증의 범위가 아니다.

## 잔여 제한

AUD-009~014는 닫히지 않았다. 특히 GDS top 정합성, NOP/AUTO/FILL 반복 의미, parameter=1 폭 처리, transaction route latch, 상세 DRAM timing model은 후속 검증과 수정이 필요하다.
