# 79차 실험 보고서: Tile-batch 용량 제한과 전체 UIB A/B

## 1. 목적

78차 실험에서 28×28×192 depthwise는 두 spatial tile을 동시에 유지해 rank당 256 accumulator entry가 필요했다. 이번 실험은 tile 하나의 9개 tap을 완결한 뒤 다음 tile을 처리해 128-entry로 제한할 수 있는지 확인하고, 최종 8-bank 후보를 전체 MobileNetV4 UIB에서 동일 설정으로 비교한다.

## 2. 구현

새 설정을 추가했다.

```ini
BANK_LOCAL_ACCUMULATOR_TILE_BATCH=0
```

- `0`: 기존처럼 모든 tile을 tap마다 함께 처리한다.
- `1`: tile 하나의 모든 tap을 처리하고 accumulator entry를 반환한 뒤 다음 tile로 이동한다.
- `N`: 최대 N개 tile을 동시에 유지한다.

기존 순서는 `tap → tile`이고 batch 실행 순서는 `tile batch → tap → tile`이다. Batch마다 CRF programming과 PIM mode 전환을 다시 수행하므로 저장공간은 줄지만 제어 cycle은 증가할 수 있다.

## 3. 재실행 설정

28×28 batch 실험의 `system_hbm_64ch.ini` 주요 설정:

```ini
HIERARCHY_SOURCE_QUEUES=true
LOGIC_DEPTHWISE_ACCUMULATION=true
LOGIC_ACCUMULATOR_OVERLAP=true
BANK_LOCAL_AGGREGATION_TAPS=9
BANK_LOCAL_ACCUMULATOR_ENTRIES=128
BANK_LOCAL_ACCUMULATOR_PORTS=1
BANK_LOCAL_ACCUMULATOR_LATENCY=1
BANK_LOCAL_ACCUMULATOR_BANKS=8
BANK_LOCAL_ACCUMULATOR_TILE_BATCH=1
```

실행 명령:

```bash
./sim --gtest_filter=MobileNetV4WorkloadTest.DepthwiseHierarchicalExpandedShape
./sim --gtest_filter=MobileNetV4WorkloadTest.ActualShapeUibRunsEndToEnd
```

## 4. 28×28 용량·성능 결과

| 정책 | 총 entry 설정 | 총 peak | Bank당 peak | Cycle | 정확도 |
|---|---:|---:|---:|---:|---:|
| 모든 tile 동시 | 256 | 256 | 32 | 63,910 | 150,528/150,528 PASS |
| 1 tile batch | 128 | 128 | 16 | 65,250 | 150,528/150,528 PASS |

Tile batch는 accumulator data array를 rank당 8 KiB에서 4 KiB로 줄이는 대신 1,340 cycle, 약 2.10%의 제어 비용을 추가했다. 이 결과는 128-entry로 더 큰 shape를 처리할 수 있음을 증명하지만, 128-entry가 항상 최적이라는 뜻은 아니다.

## 5. 전체 MobileNetV4 UIB controlled A/B

세 실험은 output buffer를 끈 동일한 현재 설정에서 실행했다.

| 구조 | 전체 cycle | Depthwise cycle | Writes | 최종 출력 |
|---|---:|---:|---:|---:|
| Bank-depthwise 기준 | 233,365 | 37,590 | 225,460 | 18,816 PASS |
| 중앙 1 bank × 4 ports | 230,514 | 34,489 | 204,468 | 18,816 PASS |
| 분산 8 banks × 1 port | 230,075 | 34,381 | 204,468 | 18,816 PASS |

8-bank 후보는 bank-depthwise 기준보다 3,290 cycle, 1.41% 빠르고 write를 20,992건, 9.31% 줄였다. 중앙 accumulator보다도 439 cycle, 0.19% 빠르다. 14×14 UIB는 물리 tile이 하나라 `TILE_BATCH=1`의 추가 반복 비용은 발생하지 않는다.

## 6. 출력 예시와 해석

```text
DEPTHWISE_HIERARCHICAL_EXPANDED_SHAPE_RESULT
outputs_checked[150528] accumulator_banks[8] tile_batch[1]
bank_local_peak_entries[128] bank_local_peak_entries_per_bank[16]
mismatches[0] total_cycle[65250]
```

- `tile_batch[1]`: 한 번에 한 physical tile만 live 상태로 유지했다.
- `peak_entries[128]`: 256-entry 없이 확장 shape를 처리했다.
- `mismatches[0]`: corner, edge, center를 포함한 모든 출력이 CPU 기준값과 일치했다.

```text
MOBILENETV4_ACTUAL_UIB_RESULT
outputs_checked[18816] depthwise_bank_local_accumulator_banks[8]
depthwise_bank_local_accumulator_peak_entries_per_bank[16]
writes[204468] total_cycle[230075]
```

- `outputs_checked[18816]`: 전체 UIB의 최종 FP16 tensor를 끝까지 검증했다.
- `writes[204468]`: 단순 depthwise 단독 추정이 아니라 전체 UIB에서 발생한 modeled write다.
- `total_cycle[230075]`: expand, depthwise, project, residual과 readback을 포함한다.

## 7. 설계 판단

현재 C++ 후보는 다음과 같다.

- 8 accumulator SRAM banks
- bank당 FP16 burst update port 1개
- 총 128 entries/rank, bank당 16 entries
- update latency 1 cycle
- 9-tap bank-local aggregation
- 64 B/cycle bank↔logic accumulator link
- spatial tile batch 1

이 후보는 기능과 cycle-level 성능이 검증됐지만 물리 사양 확정은 아니다. Verilog 합성에서 8-bank decoder, crossbar, valid/ready, metadata와 mode/program overhead의 면적·주파수·전력을 확인해야 한다.

## 8. 다음 단계

1. Tile batch를 MobileNetV4의 7×7, 14×14, 28×28, 56×56 shape에 적용해 용량·cycle 곡선을 만든다.
2. Channel 수가 8 accumulator bank에 고르게 매핑되지 않는 경우를 검증한다.
3. C++ 후보를 Verilog module의 parameter와 valid/ready interface로 구체화한다.
4. Verilog 합성 결과로 accumulator latency와 maximum frequency를 다시 보정한다.
