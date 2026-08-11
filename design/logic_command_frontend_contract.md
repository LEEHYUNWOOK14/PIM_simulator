# Logic-die PIM 명령 프런트엔드 계약

## 목적

Bank-side PIM과 logic-die PIM은 독립된 CRF, PC, 반복 상태와 실행 문맥을 가지되 실제 HBM command/data bus와 bank timing은 공유한다. 명령의 문자열 tag만으로 control/data domain을 판정하지 않으며, 명시적인 domain과 packet class를 사용한다.

## 패킷 분류

| 실행 주체 | 분류 | 소유 상태 | 공유 자원 |
|---|---|---|---|
| Bank PIM | `BANK_CONTROL` | bank CRF, PC, mode, GRF | command/data bus |
| Logic PIM | `LOGIC_CONTROL` | logic CRF, PC, epoch, operand context | command bus |
| Bank PIM | `BANK_DATA` | HBM bank/row data | bank timing, data bus |
| Logic PIM | `LOGIC_DATA` | weight/input/output row와 shared buffer | bank timing, data bus |

PIM 예약 주소 여부는 `PIMRank::isReservedRA()`로 판정한다. `LOGIC_WEIGHT_FILL`처럼 logic용 payload도 물리 HBM row를 접근하므로 DRAM timing을 우회하지 않는다.

## 불변 조건

1. Bank와 logic domain은 CRF, PC, JUMP/repeat 상태, mode latch를 공유하지 않는다.
2. Logic control packet은 ACT/PRE 상태를 임의로 바꾸지 않는다.
3. 일반 row data packet은 실행 domain과 무관하게 동일한 물리 timing 제약을 따른다.
4. 공유 bus에서는 한 cycle에 허용된 수보다 많은 packet을 발행하지 않는다.
5. read completion은 해당 domain의 실제 연산 발행 이후에만 완료될 수 있다.
6. `HIERARCHY_SOURCE_QUEUES=false`에서 기존 bank-PIM 경로의 동작을 보존한다.

## RTL 대응

- Bank control: `bank_side_pim_subsystem` + `pim_crf`
- Logic control: `logic_command_coalescer` + `logic_epoch_barrier`
- Operand context: `logic_operand_context_buffer`
- Bank-to-logic arbitration: `logic_die_link_arbiter`
- Logic execution: `logic_die_pim_top` + `logic_pcu_scheduler`

## 완료 기준

- Bank와 logic issue가 모두 0보다 크고 독립 PC로 진행한다.
- 잘못된 조기 completion이 없다.
- 공유 bus backpressure에서 valid/data/domain metadata가 안정적이다.
- source queue ON/OFF 회귀가 모두 통과한다.
