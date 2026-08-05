# WRITE completion class 및 bulk data 파이프라인 보고서

## 1. 목적

보고서 49에서 실패한 전체 WRITE 완화를 대신해, 일반 데이터와 PIM 제어 WRITE를
구조화된 메타데이터로 분리하고 안전한 일반 데이터만 파이프라인한다.

## 2. 구현

`WriteCompletionClass`를 `Transaction`과 `BusPacket`에 추가했다. 분류 정보는 caller에서
WRITE command와 DATA completion까지 전달된다. 상세 계약은
`design/write_completion_class_contract.md`에 있다.

현재 파이프라인 대상은 확실한 일반 데이터인 `LOGIC_WEIGHT_FILL`뿐이다. 새 WRITE의
`[WL, WL + BL/2)` 구간과 예약된 WRITE 구간이 겹치지 않을 때 연속 발행한다.
Mode, CRF, GRF writeback 및 미분류 WRITE는 기존의 완전 직렬화를 유지한다.

## 3. 재현 명령

```bash
bash experiment/run_source_queue_stall_breakdown.sh
```

마이크로 회귀는 다음과 같다.

```bash
HIERARCHY_SOURCE_QUEUES=true bash experiment/run_hierarchy_shared_drain.sh
```

## 4. 결과

| 항목 | 기존 보수 정책 | Completion class 정책 | 변화 |
|---|---:|---:|---:|
| 전체 UIB 출력 | 18,816 PASS | 18,816 PASS | 동일 |
| 총 cycle | 239,847 | 239,421 | -426 (-0.18%) |
| Weight fill 완료 cycle | 126,507 | 125,409 | -1,098 |
| Weight fill barrier | 1,354 | 406 | -948 (-70.0%) |
| 최초 후보 predicate reject | 1,304,360 | 1,283,610 | -20,750 |
| WRITE busy 평가 | 22,401,726 | 22,255,445 | -146,281 |

마이크로는 출력 12개 PASS이며 `1,483 → 1,413 cycles`로 70 cycles 감소했다.

## 5. 해석

구조화된 분류로 일반 데이터만 파이프라인하면 Rank mode 오류 없이 정확도를 유지할 수
있다. Weight fill barrier는 크게 감소했지만 전체 UIB 개선은 0.18%에 그쳤다. 따라서
전체 10.5% 오버헤드의 대부분은 weight fill이 아니라 이후 PIM 제어/writeback과 epoch
경계에 남아 있다.

현재 ON은 여전히 Source queue OFF 기준 216,976 cycles보다 22,445 cycles 느리다.
다음 단계는 completion class별 실제 완료 시점을 epoch outstanding과 연결해, 독립적인
일반 output data와 다음 tile의 logic 연산을 겹치는 것이다. PIM mode/control 순서는
계속 직렬화한다.
