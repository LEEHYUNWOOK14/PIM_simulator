# WRITE completion class 설계 계약

## 목적

HBM2-PIM의 WRITE는 같은 버스를 사용하더라도 완료 의미가 다르다. 일반 데이터 전송과
PIM mode/control/writeback을 구분해, 계층형 bank-side/logic-die 실행에서 안전한
파이프라이닝 범위를 명시한다.

## 클래스

| 클래스 | 의미 | 발행 정책 |
|---|---|---|
| `ORDERED` | 분류되지 않은 기존 WRITE | 모든 선행 WRITE data 완료 후 발행 |
| `BULK_DATA` | activation/weight/output 같은 일반 데이터 | 예약 data-bus 구간이 겹치지 않으면 파이프라인 가능 |
| `PIM_MODE` | SB/HAB/HAB_PIM mode 전환 | 선행 WRITE data 완료 후 순서대로 발행 |
| `PIM_CONTROL` | CRF 및 제어 레지스터 프로그램 | 선행 WRITE data 완료 후 순서대로 발행 |
| `PIM_WRITEBACK` | GRF 결과를 bank로 반영 | 선행 WRITE data 완료 후 순서대로 발행 |

기본값은 `ORDERED`다. 생성 지점이 의미를 명확히 아는 경우에만 다른 클래스를 지정한다.

## 전달 불변식

`WriteCompletionClass`는 다음 경로에서 보존되어야 한다.

```text
PIMKernel / caller
  -> MultiChannelMemorySystem
  -> MemorySystem
  -> Transaction
  -> MemoryController WRITE BusPacket
  -> writeDataToSend DATA BusPacket
  -> Rank completion
```

태그 문자열은 진단용이며 발행 정확성의 근거로 사용하지 않는다.

## 현재 적용 범위

- `LOGIC_WEIGHT_FILL`: `BULK_DATA`
- SB/HAB/HAB_PIM 전환: `PIM_MODE`
- Bank/logic CRF programming: `PIM_CONTROL`
- GEMV, ADD, MUL, ReLU의 GRF writeback: `PIM_WRITEBACK`
- 나머지 기존 WRITE: `ORDERED`

## 검증 조건

1. Source queue ON 마이크로 출력 12개가 모두 일치해야 한다.
2. 전체 MobileNetV4 UIB 출력 18,816개가 모두 일치해야 한다.
3. Rank mode 오류와 data-bus collision이 없어야 한다.
4. Source queue OFF 기존 bank-side 경로 결과가 변하지 않아야 한다.

## Epoch 완료 규칙

- READ transaction은 READ command가 Rank에 수락될 때 epoch outstanding에서 제거한다.
- WRITE transaction은 WRITE command 발행 시점이 아니라 DATA burst가 완료되는 시점에
  epoch outstanding에서 제거한다.
- BAR가 붙은 WRITE는 DATA burst 완료 후에만 다음 epoch를 연다.
- RTL에서는 이 규칙이 `write_data_done`과 `epoch_release`의 의존성으로 표현되어야 한다.

다음 epoch가 해당 output을 소비하지 않는다는 것이 tile dependency로 증명된 경우에만
별도의 비차단 release 정책을 적용할 수 있다.
