# 64차 실험 보고서: Direct output frontend 수정과 Full UIB 재검증

## 1. 목적

63차 실험에서 `LOGIC_HAB_RESIDENCY=true`인 MobileNetV4 UIB가 끝나지 않은 원인을 확정하고, logic-die PIM 출력 회수 경로를 수정한 뒤 축소 workload와 full UIB에서 정확성과 진행성을 다시 검증한다.

## 2. Watchdog 진단 결과

`PIM_RUN_WATCHDOG_CYCLES`를 추가하여 일정 cycle 동안 완료되지 않으면 다음 상태를 출력하도록 했다.

- channel별 on-fly transaction, pending transaction, command queue, return queue
- bank mode와 logic mode
- 각 mode의 ready cycle
- 마지막 command 종류와 operation tag

3-channel 최소 재현에서 모든 channel은 `LOGIC_OUTPUT_DRAIN`을 기다리고 있었다. Logic PIM 계산은 끝났지만 일반 bank는 weight staging row 2048이 열린 상태였고, output READ는 row 0을 요구했다. 출력 회수가 logic-die register를 읽는 동작인데도 DRAM bank READ처럼 row hit와 ACT/PRE 상태를 요구한 것이 교착의 직접 원인이었다.

## 3. 코드 수정

### 3.1 Direct output transaction 분류

`logicOutputDirect=true`인 transaction/packet을 source queue 설정과 무관하게 logic-control command로 분류한다.

- `MemoryController::isLogicControlTransaction()`
- `MemoryController::isLogicControlPacket()`

이제 output drain은 일반 DRAM command queue의 row scheduling을 통과하지 않는다.

### 3.2 Rank bank-state 우회

Rank가 direct output packet을 받을 때 일반 bank의 `check()`와 `updateState()`를 실행하지 않는다. 실제 데이터는 `PIMRank::readLogicOutput()`이 logic PIM의 `GRF_B`에서 직접 읽는다.

### 3.3 Wave 경계 보존

HAB에 이미 상주해 `parkIn()`을 생략하는 다음 wave 앞에는 `addBarrier()`를 유지한다. 이전 wave의 channel별 command가 끝나기 전에 다음 wave가 섞이지 않도록 하는 ordering 조건이다.

## 4. 재현 명령

빠른 3-channel/6-channel 회귀 검증:

```bash
bash experiment/run_hab_direct_output_regression.sh
```

42-position 실제 expand 크기까지 포함:

```bash
INCLUDE_LONG=true bash experiment/run_hab_direct_output_regression.sh
```

Full MobileNetV4 UIB:

```bash
RAW_TEST_FILTER=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd \
RAW_FILL_CHANNELS=32 HIERARCHY_SOURCE_QUEUES=true \
OUTPUT_BUFFER_ENABLE=true OUTPUT_BUFFER_ENTRIES=2 \
OUTPUT_DRAIN_LATENCY=4 OUTPUT_DRAIN_BW=8 \
HAB_RESIDENCY=true MODE_TRANSITION_LATENCY=32 \
PIM_RUN_WATCHDOG_CYCLES=0 EPOCH_RELEASE=true \
ONLINE_QUEUE_BACKPRESSURE=true BROADCAST_QUEUE_DEPTH=128 \
HIERARCHY_READY_BYPASS=true FILL_POLICY=row_interleaved \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 5. 수정 후 결과

| 검증 범위 | 출력 수 | HAB entry/exit | Total cycle | 결과 |
|---|---:|---:|---:|---:|
| 3 channels, 1 group, 2 waves | 384 | 1 / 1 | 1,706 | PASS |
| 6 channels, 2 groups, 2 waves | 768 | 2 / 2 | 2,515 | PASS |
| 42 positions, expand 96 -> 192 + depthwise | 5,376 | 계측 대상 아님 | 56,572 | PASS |
| Full ActualShape UIB, residency ON | 18,816 | workload 합산 | 235,182 | PASS |

`PIM_RUN_WATCHDOG_CYCLES`를 켠 축소 실험에서도 watchdog이 발생하지 않았다. 원본 비교 결과는 `experiment/results/full_uib_hab_residency_validation.csv`에 저장했다.

## 6. Full UIB A/B 비교

| 지표 | Residency OFF | Residency ON | 차이 |
|---|---:|---:|---:|
| 정확성 검증 출력 | 18,816 PASS | 18,816 PASS | 동일 |
| Total cycle | 235,182 | 235,182 | 0 |
| Modeled writes | 225,460 | 220,342 | -5,118 (-2.27%) |

HAB 상주는 full UIB의 총 cycle을 줄이지 않았지만 mode 전환과 관련된 modeled write를 2.27% 줄였다. 여러 HBM channel의 mode 전환이 병렬로 겹쳐 critical path가 변하지 않았기 때문이다. 따라서 이 결과는 “효과 없음”이 아니라 제어 트래픽 감소가 현재 timing model의 전체 실행시간에 드러나지 않은 것으로 해석한다.

## 7. 출력 예시와 읽는 법

```text
outputs_checked[18816]
total_cycle[235182]
[  PASSED  ] 1 test.
```

- `outputs_checked[18816]`: 기준값과 비교한 logic/bank PIM 출력 수다.
- `total_cycle[235182]`: 전체 UIB가 완료된 simulator cycle이다.
- `[ PASSED ]`: 수치 비교와 진행성 조건을 모두 통과했다.
- watchdog dump가 없다: 설정한 제한 cycle 전에 정상 종료했다는 뜻이다.

## 8. RTL 설계에 반영할 조건

Logic-die PIM 출력 포트는 DRAM bank의 open row 상태에 종속되면 안 된다. Verilog에서는 최소한 다음 계약이 필요하다.

```systemverilog
logic output_valid;
logic output_ready;
logic [OUTPUT_WIDTH-1:0] output_data;
```

출력 register 또는 FIFO와 controller 사이에 독립적인 `valid/ready` 경로를 두고, bank ACT/PRE/READ 상태기계와 별도의 arbitration을 해야 한다. 실제 RTL에서 공유 bus를 사용한다면 bus 점유 비용은 모델링하되 bank row hit 조건을 출력 가용 조건으로 재사용하면 안 된다.

## 9. 결론과 다음 단계

HAB residency timeout은 multi-channel 계산 자체가 아니라 direct logic output을 일반 DRAM READ frontend에 넣은 모델 불일치였다. 이를 분리한 뒤 축소 workload와 full MobileNetV4 UIB가 모두 통과했다. 다음 구현 단계는 full workload에서 cycle을 지배하는 `rank_command_rejects`와 channel별 critical path를 분해하여, HAB 제어 트래픽 감소가 실행시간 감소로 연결되지 않는 다음 병목을 찾는 것이다.
