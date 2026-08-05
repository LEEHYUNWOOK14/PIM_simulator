# 60차 실험 보고서: HAB 상주 실패와 출력 회수 인터페이스 요구사항

## 1. 실험 목적

Logic-die PIM의 GEMV 구간마다 `SB -> HAB -> HAB_PIM -> HAB -> SB` 모드 전환을 반복하지 않고,
여러 spatial group을 처리하는 동안 HAB 상태를 유지하면 mode 전환 및 barrier 대기를 줄일 수 있는지 확인했다.

이 실험은 성능 수치를 얻기 위한 최종 구현이 아니라, 현재 시뮬레이터에서 HAB 상주가 가능한지를 확인하는 구조 탐색 실험이다.

## 2. 시도한 변경

- `LOGIC_HAB_RESIDENCY` 실험 설정을 임시로 추가했다.
- `executeGemv()`에 HAB 진입/이탈 여부를 전달했다.
- 첫 spatial group에서 HAB에 진입하고 마지막 group이 끝날 때 SB로 복귀하도록 변경했다.
- group 사이에서는 기존 `HAB -> SB -> HAB` 전환을 생략했다.

## 3. 실험 결과

| 조건 | 결과 | 관찰 |
|---|---:|---|
| source queue ON + output callback ON | 시간 제한 초과 | 출력 callback이 완료되지 않아 진행이 멈춤 |
| source queue OFF + output buffer OFF | 실행 종료, 정확성 실패 | 예: raw `8`, expected `125`; raw `9`, expected `93` |

따라서 단순히 HAB 상태를 오래 유지하는 변경은 사용할 수 없다. 해당 실험용 설정과 코드 경로는 모두 제거했다.

## 4. 실패 원인

현재 결과 READ의 의미는 PIM mode에 의존한다.

1. 기존 안전 경로는 GEMV가 끝난 뒤 `HAB -> SB`로 복귀한다.
2. 그 다음 결과 READ는 SB readback 경로를 거쳐 계산 결과를 반환한다.
3. HAB 상주 상태에서 같은 READ를 발행하면 `readHab` 경로로 처리된다.
4. `readHab`는 read packet을 반환할 수 있지만, SB에 기록된 최종 GEMV 결과를 읽는 것과 의미가 같지 않다.
5. 그래서 즉시 복사 방식에서는 잘못된 값이 반환되고, READ completion callback 방식에서는 출력 버퍼가 기다리는 완료 사건이 발생하지 않아 교착된다.

즉, 문제는 단순한 timing parameter가 아니라 **출력 회수 명령의 의미와 데이터 경로가 HAB mode에 정의되어 있지 않다**는 점이다.

## 5. 복구 및 회귀 검증

다음 실험용 요소가 저장소에서 제거됐음을 확인했다.

```bash
rg -n "LOGIC_HAB_RESIDENCY|enter_hab|exit_hab|hab_resident|keep_hab_resident|HAB_RESIDENCY" .
```

출력이 없으면 제거가 완료된 것이다.

### 5.1 빌드

```bash
scons -j4
```

결과: 성공, `sim` 생성 완료.

### 5.2 기본 설정 회귀 테스트

```bash
./sim --gtest_filter=MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd
```

주요 결과:

```text
MOBILENETV4_MINI_UIB_RESULT elements[9] ... total_cycle[38664]
[  PASSED  ] 1 test.
```

- `elements[9]`: 검증한 최종 출력 원소 수다.
- `[ PASSED ]`: bank-side PIM과 logic-die PIM을 포함한 미니 UIB의 출력이 기준값과 일치한다.
- `total_cycle[38664]`: 기본 안전 경로의 비교 기준 cycle이다.

### 5.3 source queue + 유한 출력 버퍼 회귀 테스트

아래 스크립트는 설정 파일을 백업하고, 실험 설정을 적용해 테스트한 다음 원래 설정을 복구한다.

```bash
RAW_TEST_FILTER=MobileNetV4WorkloadTest.MiniatureUibRunsEndToEnd \
RAW_FILL_CHANNELS=32 \
HIERARCHY_SOURCE_QUEUES=true \
OUTPUT_BUFFER_ENABLE=true \
OUTPUT_BUFFER_ENTRIES=2 \
OUTPUT_DRAIN_LATENCY=4 \
OUTPUT_DRAIN_BW=8 \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

주요 결과:

```text
MOBILENETV4_MINI_UIB_RESULT elements[9] ...
command_predicate_reject_cycles[1235140]
epoch_mismatch_rejects[4519808]
barrier_outstanding_rejects[440373]
write_bus_busy_rejects[21712290]
total_cycle[55629]
[  PASSED  ] 1 test.
```

- 정확성은 유지됐다.
- 기본 설정보다 `16965` cycle, 약 `43.88%` 증가했다.
- `write_bus_busy_rejects`와 `epoch_mismatch_rejects`가 큰 값이므로, 다음 성능 개선은 출력값을 우회 복사하는 방식보다 명령 완료와 출력 drain의 의존성을 명확히 하는 방향이어야 한다.
- reject 값은 채널별 재시도 누적치이므로 `total_cycle`과 직접 같은 단위의 지연으로 더하면 안 된다.

## 6. 다음 구현에 필요한 인터페이스

HAB 상주를 다시 시도하려면 최소한 다음 상태와 명령 의미가 필요하다.

| 항목 | 필요한 정의 | 시뮬레이터 구현 위치 후보 | RTL 대응 신호/상태 |
|---|---|---|---|
| 출력 슬롯 | GEMV 결과가 어느 logic output slot에 저장되는가 | `LogicDieOutputBuffer`, `PIMRank` | output slot RAM/register |
| 결과 유효성 | 결과가 읽을 수 있는 시점인가 | output buffer completion state | `out_valid` |
| drain 요청 | HAB mode와 무관하게 결과 회수를 요청하는 명령 | transaction/bus command, `MemoryController` | `out_ready` 또는 drain command |
| backpressure | 출력 슬롯이 가득 찼을 때 새 연산을 막는 조건 | controller admission predicate | `out_full`, issue stall |
| 완료 조건 | 어떤 drain 완료가 다음 epoch/barrier를 해제하는가 | completion class/epoch tracker | completion token/ack |
| 순서 보장 | tile/epoch/stream별 결과 순서를 어떻게 식별하는가 | transaction metadata | tile ID, epoch ID, stream ID |
| PC 처리 | HAB 상주 중 다음 CRF 실행 시작점을 어떻게 설정하는가 | `PIMExecutionContext` | explicit `RESET_PC` 또는 start-PC field |

## 7. 권장 구현 순서

1. `LOGIC_OUTPUT_DRAIN`과 같은 명시적 내부 명령을 정의한다.
2. 이 명령이 현재 PIM mode와 무관하게 logic output slot을 대상으로 동작하게 한다.
3. READ callback은 DRAM/HAB READ가 아니라 drain 완료 사건에 연결한다.
4. output slot이 가득 차면 해당 logic stream만 backpressure하고 bank-side stream은 계속 진행할 수 있게 한다.
5. tile/epoch ID로 drain 완료를 barrier release 조건과 연결한다.
6. 미니 UIB에서 SB 복귀 없는 2개 spatial group을 먼저 검증한다.
7. 정확성이 확보된 뒤에만 full UIB cycle과 barrier raw-tag 감소량을 비교한다.

## 8. 결론

HAB 상주 자체는 제거할 최적화가 아니라, 현재 시뮬레이터에 **mode-independent output retirement 경로가 없다는 사실을 드러낸 실험**이다.
다음 코드 수정의 우선순위는 mode 전환을 먼저 없애는 것이 아니라, logic-die 결과를 명시적으로 저장하고 완료시키는 인터페이스를 구현하는 것이다.
