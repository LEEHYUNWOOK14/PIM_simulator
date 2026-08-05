# Logic-die PIM command frontend contract

## 1. 목적

계층형 PIM은 bank-side PCU와 logic-die PCU가 서로 다른 연산 상태를 유지하면서,
실제 HBM 데이터 전송 자원만 공유해야 한다. 현재 `HIERARCHY_SOURCE_QUEUES=true`
경로는 태그와 PC/CRF/mode만 분리하고 동일한 DRAM `CommandQueue`와 `BankState`를
사용하므로 이 계약을 만족하지 못한다.

## 2. 패킷 분류

| 실행원 | 패킷 역할 | 대표 태그/주소 | 소유 상태 | 공유 자원 |
|---|---|---|---|---|
| Bank PCU | Bank 제어 | `BANK_DOMAIN_`, PIM 예약 주소 | bank CRF, PC, mode, GRF | command bus |
| Logic PCU | Logic 제어 | `LOGIC_DOMAIN_` + PIM 예약 주소 | logic CRF, PC, mode, GRF | command bus만 중재 |
| Bank PCU | 데이터 | 일반 HBM row의 operand/result | 물리 HBM bank/row | HBM bank state, data bus |
| Logic PCU | 데이터 | weight/input/output 일반 HBM row | 물리 HBM bank/row, logic weight buffer | HBM bank state, data bus |

PIM 예약 주소는 `PIMRank::isReservedRA()`가 판정한다. 태그 문자열만으로 제어와
데이터를 구분하지 않는다. 예를 들어 `LOGIC_WEIGHT_FILL`은 logic용 데이터지만
일반 HBM row를 접근하므로 물리 bank timing을 따라야 한다.

## 3. 구현 불변조건

1. Bank와 logic은 각각 독립된 CRF, PC, 반복/점프 상태, mode latch를 가진다.
2. Logic 제어 패킷의 ACT/PRE 상태는 bank PCU의 열린 row를 변경하지 않는다.
3. 일반 row 데이터 패킷은 실행원과 무관하게 동일한 물리 HBM timing을 따른다.
4. command/data bus가 같은 cycle에 두 패킷을 전송하지 않도록 최종 중재한다.
5. read completion은 해당 실행원의 실제 연산 발행 후에만 완료될 수 있다.
6. `HIERARCHY_SOURCE_QUEUES=false`는 기존 bank-PIM 기준 동작을 그대로 보존한다.

## 4. 구현 순서

1. `BusPacket`을 `{BANK, LOGIC} x {CONTROL, DATA}`로 분류하는 단일 함수를 만든다.
2. Logic CONTROL용 command queue와 가상 bank-state를 추가한다.
3. 물리 DATA queue와 logic CONTROL queue의 발행 결과를 command bus 앞에서 중재한다.
4. Logic CONTROL은 `logicMode_`와 `logicContext_`만 갱신한다.
5. 공유 drain 테스트에서 정확도와 `logic_issues > 0`을 먼저 확인한다.
6. 이후 `overlapping_window_cycles > 0`을 확인하고 전체 MobileNetV4 UIB를 회귀한다.

## 5. 완료 판정

- source queue OFF: 실제 UIB `outputs_checked=18816`, 테스트 통과
- source queue ON: shared drain `logic_outputs_checked=12`, 테스트 통과
- source queue ON: `bank_issues>0`, `logic_issues>0`
- 잘못된 조기 완료 없음: logic issue가 0인 상태에서 logic read가 반환되지 않음
- 전체 정확도 테스트와 기존 bank-PIM 테스트 회귀 통과
