# 16차 기술 구현 보고서: Global Logic-PCU Scheduler

## 1. 구현 목적

15차 spatial-group 결과는 각 HBM 채널의 `PIMRank`가 독립적인 logic PCU 상태를 가져, logic die 전체 자원 수를 제한하지 못했다. 이번 구현은 64개 채널과 모든 rank가 하나의 logic-die scheduler를 공유하도록 바꾸고 다음 항목을 모델링한다.

- logic die 전체 PCU 개수
- 앞선 logic 명령으로 인한 queue 대기
- PCU 개수에 따른 병렬 service lane
- logic 내부 bandwidth에 따른 service time

## 2. 설정 변수

```ini
LOGIC_GLOBAL_SCHEDULER=false
```

- `false`: 기존 채널별 독립 logic 자원 모델
- `true`: 모든 채널이 하나의 global logic-PCU scheduler 공유

기존 실험 결과를 보존하기 위해 기본값은 `false`다. 전역 실험에서는 다음 설정을 함께 사용했다.

```ini
ENABLE_BANK_SIDE_PIM=true
ENABLE_LOGIC_DIE_PIM=true
PIM_TARGET=hybrid
LOGIC_COMPACT_OUTPUT=true
LOGIC_SPATIAL_GROUPING=true
LOGIC_GLOBAL_SCHEDULER=true
LOGIC_PIM_LATENCY=2
LOGIC_PIM_BW=64
HIERARCHY_PIM_BW=64
```

## 3. 구현 구조

`MultiChannelMemorySystem`이 `LogicDieScheduler`를 한 번 생성한다. 같은 `shared_ptr`가 다음 생성자 경로를 통해 모든 PIM rank에 전달된다.

```text
MultiChannelMemorySystem
  -> MemorySystem (64 channels)
    -> Rank
      -> PIMRank
```

각 logic 명령은 다음 값을 계산한다.

```text
compute_cycles  = ceil(blocks / units_per_command) x LOGIC_PIM_LATENCY
transfer_cycles = ceil(transfer_bytes / LOGIC_PIM_BW)
service_cycles  = max(compute_cycles, transfer_cycles)
queue_cycles    = selected_lane_busy_until - current_cycle
completion_delay = queue_cycles + service_cycles
```

PCU가 8개이고 명령 하나가 8 blocks를 사용하면 service lane은 1개다. PCU가 16개면 2개, 32개면 4개, 64개면 8개 명령을 병렬 서비스할 수 있다.

## 4. Scheduler 단위 검증

```bash
./sim --gtest_filter=LogicDieSchedulerTest.*
```

```text
[ RUN      ] LogicDieSchedulerTest.EightUnitsSerializeTwoEightBlockCommands
[       OK ] LogicDieSchedulerTest.EightUnitsSerializeTwoEightBlockCommands
[ RUN      ] LogicDieSchedulerTest.SixteenUnitsRunTwoEightBlockCommandsInParallel
[       OK ] LogicDieSchedulerTest.SixteenUnitsRunTwoEightBlockCommandsInParallel
[  PASSED  ] 2 tests.
```

- 8 PCU: 첫 명령 4 cycle, 두 번째 명령은 4 cycle 대기 후 8 cycle 시점 완료
- 16 PCU: 두 명령 모두 대기 없이 4 cycle 시점 완료

## 5. Pointwise PCU 수 Sweep

실행 명령:

```bash
bash experiment/run_global_logic_unit_sweep.sh
```

결과 파일:

```text
experiment/results/global_logic_unit_sweep.csv
```

| Global PCU | 병렬 lane | Queue cycles 합 | Busy until | Pointwise cycle | Bank pointwise 대비 |
|---:|---:|---:|---:|---:|---:|
| 8 | 1 | 3,404,944,095 | 171,070 | 170,580 | 0.70x |
| 16 | 2 | 1,612,607,199 | 86,398 | 86,244 | 1.39x |
| 32 | 4 | 716,438,751 | 44,062 | 44,076 | 2.73x |
| 64 | 8 | 268,354,527 | 22,894 | 22,992 | 5.23x |

Bank-side pointwise 기준은 120,164 cycle이다. 이 조건에서는 8 PCU가 부족하고 16 PCU부터 bank-side 기준을 넘어선다. PCU 수를 늘려도 queue가 0이 되지 않는 이유는 21개 spatial group이 최대 8개 service lane보다 많고, 각 group이 여러 MAC 명령을 발생시키기 때문이다.

## 6. 실제 MobileNetV4 UIB PCU Sweep

```bash
bash experiment/run_global_logic_actual_uib.sh
```

```bash
bash experiment/run_global_logic_actual_uib_sweep.sh
```

결과 파일은 `experiment/results/global_logic_actual_uib_sweep.csv`다. 네 조건 모두 18,816개 최종 출력을 통과했다.

| 구조 | 전체 UIB cycle | Bank 기준 speed-up |
|---|---:|---:|
| Bank-side | 346,600 | 1.00x |
| Global logic PCU 8개 | 400,340 | 0.87x |
| Global logic PCU 16개 | 215,687 | 1.61x |
| Global logic PCU 32개 | 123,376 | 2.81x |
| Global logic PCU 64개 | 76,842 | 4.51x |
| 채널별 독립 logic 자원 | 52,277 | 6.63x |

Global PCU 8개는 queue 병목 때문에 bank-side보다 15.5% 느리다. 16개부터 전체 UIB에서도 bank-side 기준을 넘어선다. 64개를 사용해도 채널별 독립 자원 모델보다 느리므로 shared scheduler와 data-return serialization 비용이 남아 있음을 알 수 있다.

실험 후 설정 파일은 다음 기본값으로 복구된다.

```ini
NUM_LOGIC_PIM_UNITS=8
LOGIC_GLOBAL_SCHEDULER=false
PIM_TARGET=bank_side
```

## 7. 시뮬레이터 교착 수정

16-PCU 이상에서는 여러 service lane의 read가 발행 순서와 다른 시점에 완료된다. 이 과정에서 기존 DRAMSim 코드의 두 문제가 드러났다.

1. `readReturnCountdown`이 `unsigned`인데 0 이후에도 감소해 언더플로됐다.
2. global scheduler busy 시간을 read 반환 지연에 더한 뒤 command queue에서도 모든 DRAM 명령을 차단해 지연을 이중 적용했다.

수정 내용:

- countdown은 0에서 포화한다.
- data bus가 비었을 때 준비된 선두 read만 반환한다.
- 반환 큐를 `vector`에서 `deque`로 바꿔 `pop_front()` 비용을 O(1)로 만든다.
- global scheduler에서는 일반 DRAM command queue를 막지 않고 logic read 반환에만 `queue + service` 지연을 적용한다.

수정 전 16-PCU 실행은 `END_SB_TO_HAB_BAR` 앞에서 channel 1 transaction queue가 가득 찬 채 종료되지 않았다. 수정 후 동일 테스트가 약 45초에 완료됐다.

## 8. Logic 내부 Bandwidth Sweep

Global PCU를 16개로 고정하고 `LOGIC_PIM_BW`를 변경했다.

```bash
bash experiment/run_global_logic_bandwidth_sweep.sh
```

결과 파일은 `experiment/results/global_logic_bandwidth_sweep.csv`다.

| Logic BW (B/cycle) | Service cycles 합 | Pointwise cycle | Bank 기준 speed-up |
|---:|---:|---:|---:|
| 16 | 677,376 | 339,252 | 0.35x |
| 32 | 338,688 | 170,580 | 0.70x |
| 64 | 169,344 | 86,244 | 1.39x |
| 128 | 84,672 | 44,076 | 2.73x |
| 0 (무제한) | 84,672 | 44,076 | 2.73x |

PCU 16개만 늘려도 logic 내부 bandwidth가 32 B/cycle 이하이면 bank-side보다 느리다. 현재 설정에서는 `16 PCU + 64 B/cycle 이상`이 pointwise crossover의 공동 최소 조건이다.

128 B/cycle과 무제한 결과가 같은 이유는 명령당 compute 지연 2 cycle과 transfer 지연 2 cycle이 같아지기 때문이다. 128 B/cycle 이상에서는 bandwidth를 더 늘려도 이 모델의 cycle이 줄지 않는다.

Hierarchy bandwidth는 전체 UIB에서 225,792 bytes를 네 번의 tensor 경계로 나눠 전송한다. PCU 16개 결과에서 hierarchy 64 B/cycle의 3,528 cycle은 전체 215,687 cycle의 약 1.64%이므로, 현재 후보점의 1차 병목은 hierarchy 링크보다 global logic service queue다.

## 9. 설계 의미

현재 결과가 보여주는 핵심은 단순히 logic PCU를 추가하는 것만으로는 부족하다는 점이다.

1. PCU 8개 중앙 공유 구조는 MobileNetV4 pointwise와 전체 UIB 요청량을 감당하지 못한다.
2. 현재 latency 조건에서는 `PCU 16개 + logic BW 64 B/cycle`이 최초 crossover 설계점이다.
3. 채널별 독립 PCU 구조는 빠르지만 PCU 수와 면적이 크게 증가한다.
4. weight multicast와 command coalescing은 dispatch 수와 weight 이동을 줄일 수 있지만, 서로 다른 position의 MAC 계산량까지 제거하지는 않는다.
5. 최종 RTL 설계점은 PCU 수, interconnect, multicast buffer의 면적·전력과 함께 결정해야 한다.

서로 다른 spatial position은 입력이 다르므로 MAC 계산 자체를 단순 병합할 수 없다. 다음 기술 구현은 command dispatch overhead와 weight multicast를 계산량과 분리해 모델링하고, `16 PCU + 64 B/cycle` 후보의 면적·전력 입력을 받을 수 있는 RTL 파라미터 표로 연결하는 것이다.

## 10. 전체 기본 회귀

모든 설정을 기본 bank-side 상태로 복구한 뒤 전체 테스트를 실행했다.

```bash
./sim
```

```text
[==========] 30 tests from 5 test suites ran.
[  PASSED  ] 28 tests.
[  SKIPPED ] 1 test.
[  FAILED  ] PIMBenchFixture.add
```

- Scheduler 단위 테스트 2개를 포함한 28개 테스트가 통과했다.
- 채널 범위 테스트 1개는 hybrid compact 전용이므로 기본 설정에서 정상 skip됐다.
- ADD benchmark 실패는 기존과 동일한 `1.98597x` 대 `2.0x 초과` 임계값 문제다.
- Bank-side 실제 UIB는 18,816개 출력과 346,600 cycle 기준선을 그대로 재현했다.

따라서 global scheduler와 read-return queue 수정으로 새 기능 회귀는 발견되지 않았다.
