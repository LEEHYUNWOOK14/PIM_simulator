# 78차 실험 보고서: Banked accumulator와 shape 확장

## 1. 실험 목적

기존 finite bank-local accumulator는 rank마다 하나의 중앙 map과 전체 port 수만 제한했다. 실제 RTL에서는 여러 write port를 가진 큰 중앙 SRAM보다 여러 bank로 나눈 작은 SRAM이 구현하기 쉬울 수 있다. 이번 실험은 accumulator를 bank로 나누고 다음을 확인한다.

1. PIM block별 update가 accumulator bank에 분산되는가.
2. bank별 port 충돌이 cycle과 stall에 반영되는가.
3. 14×14에서 측정한 128-entry가 더 큰 tensor에도 충분한가.

## 2. 구현 원리

- 새 설정 `BANK_LOCAL_ACCUMULATOR_BANKS`를 추가했다.
- PIM block `p`는 accumulator bank `p % BANK_LOCAL_ACCUMULATOR_BANKS`에 연결된다.
- `BANK_LOCAL_ACCUMULATOR_PORTS`는 이제 accumulator bank 하나당 update port 수다.
- 총 entry는 bank 수로 균등 분할하며, 각 bank가 자기 용량을 넘으면 overflow를 발생시킨다.
- 한 direct packet의 service cycle은 다음과 같다.

```text
updates_per_bank = NUM_PIM_BLOCKS / ACCUMULATOR_BANKS
service_cycles = ceil(updates_per_bank / PORTS_PER_BANK) × UPDATE_LATENCY
```

현재 PIM block은 rank당 8개이므로 4-bank는 bank당 2 update, 8-bank는 bank당 1 update를 받는다.

## 3. 재실행 방법

`system_hbm_64ch.ini`에서 공통 설정을 다음과 같이 바꾼다.

```ini
HIERARCHY_SOURCE_QUEUES=true
LOGIC_DEPTHWISE_ACCUMULATION=true
LOGIC_ACCUMULATOR_OVERLAP=true
BANK_LOCAL_AGGREGATION_TAPS=9
BANK_LOCAL_ACCUMULATOR_ENTRIES=128
BANK_LOCAL_ACCUMULATOR_PORTS=1
BANK_LOCAL_ACCUMULATOR_LATENCY=1
BANK_LOCAL_ACCUMULATOR_BANKS=4
```

14×14 실제 shape 실행:

```bash
./sim --gtest_filter=MobileNetV4WorkloadTest.DepthwiseHierarchicalActualShape
```

28×28 확장 shape는 entry를 256, bank를 8로 설정한 뒤 실행한다.

```bash
./sim --gtest_filter=MobileNetV4WorkloadTest.DepthwiseHierarchicalExpandedShape
```

실험 후에는 설정을 기본값인 accumulation `false`, overlap `false`, aggregation taps `1`, entries/ports `0`, banks `1`로 복원한다.

## 4. 결과

| Shape | 구조 | 총 peak | Bank당 peak | Stall | Cycle | 정확도 |
|---|---:|---:|---:|---:|---:|---:|
| 14×14×192 | 1 bank × 4 ports | 128 | 128 | 43,968 | 33,622 | 37,632/37,632 PASS |
| 14×14×192 | 4 banks × 1 port | 128 | 32 | 43,968 | 33,622 | 37,632/37,632 PASS |
| 14×14×192 | 8 banks × 1 port | 128 | 16 | 25,344 | 33,138 | 37,632/37,632 PASS |
| 28×28×192 | 8 banks × 1 port | 256 | 32 | 50,688 | 63,910 | 150,528/150,528 PASS |

원본 로그는 `experiment/results/depthwise_banked_accum_b4_p1.log`, `depthwise_banked_accum_b8_p1.log`, `depthwise_banked_accum_28x28_b8_p1.log`에 저장했다.

## 5. 출력 해석

```text
DEPTHWISE_HIERARCHICAL_EXPANDED_SHAPE_RESULT
outputs_checked[150528] padded_elements[262144]
accumulator_banks[8] bank_local_peak_entries[256]
bank_local_peak_entries_per_bank[32] mismatches[0]
total_cycle[63910]
```

- `outputs_checked`: CPU 기준값과 비교한 논리 출력 개수다.
- `padded_elements`: 64채널 PIM mapping을 위해 실제로 배치한 물리 tensor 크기다.
- `bank_local_peak_entries`: 한 rank에서 동시에 살아 있던 전체 partial-sum entry의 최대값이다.
- `bank_local_peak_entries_per_bank`: accumulator bank 하나가 감당한 최대 entry다.
- `mismatches[0]`: corner 4, edge 6, center 9의 FP16 결과가 모두 맞았다는 뜻이다.
- `total_cycle`: 이 depthwise 단계의 cycle-level 모델 결과다.

## 6. 해석과 설계 판단

4 banks × 1 port와 1 bank × 4 ports가 같은 33,622 cycle을 보였다. 두 구조 모두 packet 하나를 2 cycle에 처리하기 때문이다. 8 banks × 1 port는 각 PIM block update를 독립 bank가 받아 1-cycle service가 가능해졌고 cycle이 33,138로 줄었다.

28×28에서는 총 peak가 128에서 256으로 증가했지만 bank당 peak는 32로 유지됐다. 따라서 128-entry는 MobileNetV4 전체에 통용되는 고정 사양이 아니라 현재 spatial tile 수에 종속된 값이다. RTL 용량은 최대 지원 tile 수를 정하거나, tile별 flush/scheduling으로 live entry 수를 제한한 뒤 결정해야 한다.

## 7. 다음 단계

1. accumulator bank hash가 실제 address 분포에서도 균등한지 random shape와 channel 수로 확인한다.
2. tile 완료마다 entry를 flush하는 scheduling을 추가해 총 용량을 128로 제한할 수 있는지 비교한다.
3. 8-bank × 1-port 후보를 전체 MobileNetV4 UIB에 적용해 231,309-cycle 후보와 비교한다.
4. Verilog에서는 8개 accumulator bank, bank당 1 write port, valid/ready backpressure를 우선 후보로 작성한다.
