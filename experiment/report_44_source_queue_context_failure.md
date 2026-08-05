# 44차 실험 보고서: Source queue와 공유 execution context 실패

## 1. 실험 목적

Transaction queue와 command queue에서 bank/logic source를 독립적으로 선택해 43차의 완전 직렬 issue를 해소한다. Source별 barrier와 동일 주소 dependency를 분리하고 round-robin transaction 공급을 적용한다.

## 2. 실험 구현

설정값을 추가했다.

```ini
HIERARCHY_SOURCE_QUEUES=false
```

`true`일 때 다음 실험 동작을 적용한다.

- 모든 PIM transaction에 `BANK_DOMAIN_` 또는 `LOGIC_DOMAIN_` 태그 부여
- Transaction queue에서 bank/logic round-robin 선택
- Command queue barrier를 같은 source에만 적용
- 같은 물리 주소 dependency도 같은 source context 안에서만 적용

기본값은 `false`이며 기존 simulator 동작을 유지한다.

## 3. 활성화 실험 결과

실험 명령:

```bash
HIERARCHY_SOURCE_QUEUES=true bash experiment/run_hierarchy_shared_drain.sh
```

관측 결과:

| 항목 | 값 |
|---|---:|
| Shared drain cycle | 1,596 |
| Bank issues | 2,024 |
| Logic issues | 0 |
| Logic 출력 통과 | 0/12 |
| Logic 출력 값 | 모두 0 |

Cycle은 짧아졌지만 logic 작업 자체가 실행되지 않았으므로 성능 결과로 사용할 수 없다.

## 4. 실패 원인

CRF는 42차에서 bank/logic으로 분리했지만 다음 execution context는 여전히 공유된다.

- `Rank::mode_`
- `PIMRank::pimPC_`
- Jump/repeat counter
- `crfExit_`
- HAB/HAB_PIM mode transition state

Source queue가 control packet을 교차 발행하면 bank stream의 mode 전환과 PC reset이 logic stream 상태를 덮어쓴다. 그 결과 logic MAC packet이 올바른 HAB_PIM context에서 decode되지 않아 issue 0, 출력 0이 됐다.

## 5. 결론

독립 command queue만 추가하는 것은 충분하지 않다. 계층형 PCU가 실제 독립 하드웨어라면 다음 상태가 모두 source별로 분리돼야 한다.

| Context | Bank-side | Logic-die |
|---|---|---|
| CRF | 분리 완료 | 분리 완료 |
| PC | 공유 중 | 공유 중 |
| Jump/repeat counter | 공유 중 | 공유 중 |
| PIM mode | 공유 중 | 공유 중 |
| Exit state | 공유 중 | 공유 중 |
| Command queue/barrier | 실험 구현 | 실험 구현 |

## 6. 안전 조치

- `HIERARCHY_SOURCE_QUEUES` 기본값은 `false`다.
- 일반 재현 스크립트도 기본 off로 실행한다.
- Off 회귀는 logic 출력 12/12, bank/logic issue 2,048/288로 통과했다.
- 전체 MobileNetV4 UIB도 출력 18,816개와 기존 214,228 cycle을 정확히 유지했다.
- True 결과는 실패 진단 데이터이며 speedup으로 보고하지 않는다.

## 7. 다음 구현

1. `PIMExecutionContext`에 PC, jump/repeat, exit 상태를 묶는다.
2. Bank/logic context를 각각 보유한다.
3. Packet domain에 따라 control/decode context를 선택한다.
4. `Rank::mode_` 의존성을 bank/logic mode로 분리한다.
5. Source queue를 다시 켜고 logic issue와 정확도를 먼저 복구한다.
6. 그 후 issue window overlap과 순차 대비 cycle을 평가한다.
