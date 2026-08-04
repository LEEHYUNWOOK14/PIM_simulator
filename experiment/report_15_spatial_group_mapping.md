# 15차 기술 구현 보고서: Spatial-group Mapping

## 1. 실험 목적

Compact output mapping은 MobileNetV4 pointwise 출력에 필요한 채널만 활성화해 transaction을 줄였지만, 각 공간 위치를 순차 실행해 cycle은 줄지 않았다. 이번 구현은 비어 있는 채널을 서로 다른 공간 위치에 할당하고 같은 simulation 구간에서 병렬 실행하는 것을 목표로 한다.

## 2. 추가 설정

```ini
LOGIC_COMPACT_OUTPUT=true
LOGIC_SPATIAL_GROUPING=true
```

- `LOGIC_COMPACT_OUTPUT`: 논리 출력 크기에 필요한 최소 채널 수를 계산한다.
- `LOGIC_SPATIAL_GROUPING`: 서로 다른 공간 위치를 겹치지 않는 채널 그룹에 배치한다.
- 두 설정은 logic-die PIM 경로에서 함께 사용해야 한다.

## 3. 구현 내용

### 3.1 물리 채널 부분집합

기존 코드는 활성 채널 수가 3이면 항상 채널 0~2를 사용했다. 다음 경로가 `pim_chans_`의 실제 물리 채널 번호를 사용하도록 수정했다.

- GEMV weight preload
- GRF 입력 write와 barrier
- GEMV 결과 read
- tree GEMV zero 초기화
- SRF programming

따라서 `channel_start=5`, `channel_count=3`이면 transaction이 실제 채널 5~7에만 들어간다.

### 3.2 Spatial wave scheduler

한 채널은 `8 PIM blocks x 8 GRF_B = 64 outputs`를 담당한다.

```text
expand  192 outputs: 3 channels/group, floor(64/3) = 21 groups
project  96 outputs: 2 channels/group, floor(64/2) = 32 groups
```

196개 공간 위치는 다음 wave 수로 실행된다.

```text
expand : ceil(196/21) = 10 waves
project: ceil(196/32) = 7 waves
```

각 position의 transaction을 해당 group의 채널 큐에 넣고, 모든 채널 큐를 만든 후 `runPIM()`을 한 번 호출한다. 같은 채널 그룹의 position은 순차 처리되며 서로 다른 그룹은 HBM 채널 병렬성에 따라 함께 진행된다.

## 4. 실행 방법

저장소 루트의 WSL 터미널에서 실행한다.

```bash
bash experiment/run_channel_range_mapping_test.sh
bash experiment/run_spatial_group_pointwise_test.sh
bash experiment/run_spatial_group_actual_uib.sh
```

각 스크립트는 설정 파일을 임시 변경하고 종료 시 원래 설정으로 복구한다.

## 5. 핵심 출력 예시

```text
MOBILENETV4_BATCH_POINTWISE_RESULT ...
active_channels[3] physical_output_dim[192]
spatial_groups[21] batch_waves[10]
reads[94080] writes[46956] cycle[12667]
[  PASSED  ] 1 test.
```

- `active_channels[3]`: 공간 위치 하나가 사용하는 채널 수다.
- `spatial_groups[21]`: 동시에 배치 가능한 독립 공간 위치 수다.
- `batch_waves[10]`: 196개 위치를 처리하기 위해 필요한 그룹 반복 횟수다.
- `PASSED`: 37,632개 pointwise 출력이 CPU 기준값과 일치했다.

전체 UIB 출력은 다음과 같다.

```text
MOBILENETV4_ACTUAL_UIB_RESULT
shape[14x14x96_to_192_to_96] outputs_checked[18816]
expand_spatial_groups[21] expand_batch_waves[10]
project_spatial_groups[32] project_batch_waves[7]
reads[268800] writes[319668]
transfer_bytes[225792] transfer_cycles[3528]
total_cycle[52277]
[  PASSED  ] 1 test.
```

- `outputs_checked[18816]`: 최종 14x14x96 출력 전체를 검사했다.
- expand와 project의 group/wave 수가 계산식과 일치한다.
- hierarchy transfer는 기존 hybrid와 같은 225,792 bytes다.
- 최종 출력의 모서리, 가장자리, 내부 기대값이 각각 5, 7, 10으로 모두 일치했다.

## 6. 비교 결과

원본 데이터는 `experiment/results/spatial_group_actual_uib.csv`에 저장했다.

| 구조 | Read | Write | Cycle | Bank 기준 speed-up |
|---|---:|---:|---:|---:|
| Bank fixed | 2,562,176 | 845,376 | 346,600 | 1.00x |
| Hybrid fixed | 2,562,176 | 845,376 | 436,861 | 0.79x |
| Hybrid compact | 237,600 | 218,635 | 436,861 | 0.79x |
| Hybrid spatial | 268,800 | 319,668 | 52,277 | 6.63x |

Spatial mapping은 bank 기준 read를 89.51%, write를 62.19% 줄였다. Hybrid fixed 대비 cycle은 8.36배, bank fixed 대비 6.63배 개선됐다.

Spatial은 compact 단독보다 transaction이 증가한다. 여러 channel group에 같은 weight를 preload하고 각 group에서 mode 전환 명령을 실행하기 때문이다. 하지만 position 병렬화로 cycle 감소 폭이 훨씬 크다.

## 7. 해석 시 필수 주의사항

현재 simulator의 logic-die 연산 상태와 `logicPimBlocks`는 각 채널의 `PIMRank` 객체 안에 존재한다. 따라서 이번 spatial 결과는 채널 그룹이 독립적인 logic 연산 자원을 사용할 수 있다는 구조를 모델링한다.

이 결과를 곧바로 “logic die 전체에 PCU 8개만 공유하는 실제 칩”의 성능으로 주장하면 안 된다. 실제 설계가 중앙 공유 PCU라면 다음 자원 경쟁 모델이 추가되어야 한다.

- 64채널 요청을 받는 global logic-PCU scheduler
- 전체 logic die가 공유하는 PCU 개수와 busy 상태
- 채널 그룹 간 arbitration과 queue 지연
- shared interconnect bandwidth와 multicast 비용
- weight를 그룹마다 복제할지 공유 buffer에서 공급할지

따라서 52,277 cycle은 현재 구현한 **채널 그룹 독립 서비스 구조의 검증값**이며, 중앙 공유형 logic die를 선택한다면 상한 성능에 가깝다.

## 8. 다음 구현

다음 단계는 global logic-PCU resource model이다. `NUM_LOGIC_PIM_UNITS=8`을 채널마다 복제하지 않고 logic die 전체에서 공유하도록 이동한 뒤, spatial group 수를 늘릴 때 PCU와 interconnect contention 때문에 cycle이 어떻게 변하는지 측정해야 한다. 이 단계가 완료되어야 RTL에서 사용할 PCU 개수와 scheduling 정책을 설계 근거로 연결할 수 있다.

## 9. 기본 설정 회귀 확인

Spatial 설정을 끈 원래 bank-side 설정에서도 기존 경로를 다시 실행했다.

```text
expand_spatial_groups[1] expand_batch_waves[196]
project_spatial_groups[1] project_batch_waves[196]
reads[2562176] writes[845376] total_cycle[346600]
[  PASSED  ] 2 tests.
[  SKIPPED ] 1 test.
```

두 실행 테스트는 기존 pointwise batch와 실제 UIB다. 채널 범위 전용 테스트 1개는 hybrid compact 설정에서만 유효하므로 기본 설정에서 정상적으로 skip됐다. 이 결과로 `LOGIC_SPATIAL_GROUPING=false`일 때 기존 bank-side 기준선이 보존됨을 확인했다.
