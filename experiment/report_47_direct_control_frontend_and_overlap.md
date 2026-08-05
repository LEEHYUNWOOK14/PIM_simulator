# 실험 47: 직접 제어 frontend와 bank/logic 실행 중첩

## 1. 목적

PIM 예약주소 제어를 물리 HBM row-buffer 상태에서 분리하고, bank PCU와 logic PCU가
각자의 명령 순서를 유지하면서 실제 데이터 경로만 공유하도록 구현한다.

## 2. 주요 수정

- 예약주소 transaction은 ACT/PRE 없이 직접 control frontend에서 발행한다.
- ABMR/SBMR WRITE에 기존 mode latch 의미를 직접 적용한다.
- Logic과 bank source에 각각 독립 sequence를 부여한다.
- Logic result read도 `domainTag("output")`을 사용해 MAC 이후 순서에 포함한다.
- 두 source의 WRITE는 기존 write-data burst가 끝난 뒤 발행하도록 공용 data bus를 중재한다.
- Source queue OFF 경로는 기존 직렬 실행 assertion을 유지한다.

## 3. 재현 명령

```bash
# 중첩 실행 경로
HIERARCHY_SOURCE_QUEUES=true \
bash experiment/run_hierarchy_shared_drain.sh

# 기존 직렬 경로
HIERARCHY_SOURCE_QUEUES=false \
bash experiment/run_hierarchy_shared_drain.sh
```

## 4. 결과

| 항목 | Source queue ON | Source queue OFF |
|---|---:|---:|
| 정확도 비교 | 12개 통과 | 12개 통과 |
| Shared drain cycles | 1,483 | 1,942 |
| Bank issues | 2,048 | 2,048 |
| Logic issues | 288 | 288 |
| Window overlap | 404 cycles | 0 cycles |
| Pending after drain | 0 | 0 |
| 테스트 | PASS | PASS |

ON은 동일한 issue 수와 정확도를 유지하면서 OFF보다 459 cycles 짧다. 감소율은
`459 / 1942 = 23.6%`이고, OFF 대비 처리율 배수는 `1942 / 1483 = 1.310x`이다.
이는 소형 shared-drain workload에서 bank와 logic의 실행 window가 실제로 겹친 결과다.

원시 비교값은 `experiment/results/hierarchy_source_queue_comparison.csv`에 저장했다.

## 5. 전체 UIB 회귀 상태

```bash
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
HIERARCHY_SOURCE_QUEUES=true \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

전체 UIB는 transaction 단위 sequence 대신 barrier epoch로 순서를 보장하도록 수정한 뒤
Source queue ON/OFF 모두 18,816개 출력을 통과했다. 상세 결과와 성능 비교는
`experiment/report_48_full_uib_epoch_ordering.md`에 기록했다.

## 6. 다음 구현

1. 공유 WRITE bus 예약 때문에 발생하는 대기 cycle을 분리 측정한다.
2. epoch barrier와 command predicate reject 비용을 UIB 단계별로 기록한다.
3. MobileNetV4 tile 단위로 bank와 logic 실행 window를 겹친다.
4. Source queue OFF보다 총 cycle이 감소하는지 전체 UIB로 재검증한다.
