# 31차 실험 보고서: MobileNetV4 pointwise shape별 queue depth 검증

## 1. 실험 목적

UIB 14 한 사례에서 얻은 broadcast-mask queue 용량 결론이 다른 MobileNetV4 pointwise 형상에서도 유지되는지 확인한다. 독립 레이어 결과와 실제 UIB 연산 체인 결과를 함께 비교한다.

## 2. 재현 명령

프로젝트 루트의 WSL 터미널에서 실행한다.

```bash
bash experiment/run_mobilenetv4_pointwise_shape_sweep.sh
```

특정 레이어와 depth만 실행하려면 다음처럼 범위를 지정한다.

```bash
LAYERS=uib14_extra_project \
DEPTH_LIST="32 64 128" \
RESULT_FILE=experiment/results/project_only.csv \
bash experiment/run_mobilenetv4_pointwise_shape_sweep.sh
```

## 3. 검증한 형상

| 레이어 | 공간 크기 | 입력→출력 채널 | 의미 |
|---|---:|---:|---|
| `uib14_extra_expand` | 28×28 | 64→192 | 큰 공간 크기의 expand |
| `uib14_ib_expand` | 14×14 | 96→192 | 기존 UIB expand |
| `uib14_extra_project` | 14×14 | 192→96 | project |

입력과 weight를 모두 1로 생성했기 때문에 각 출력의 기대값은 입력 채널 수와 같다. 세 형상 모두 전체 출력 원소를 기대값과 비교해 통과했다. 입력 채널이 128보다 큰 project는 물리 입력 폭을 256으로 올려 pack한다.

## 4. 결과

| 형상 | Depth | peak open masks | 막힌 channel-cycle | 막힌 wall-cycle | 총 cycle |
|---|---:|---:|---:|---:|---:|
| 28×28, 64→192 | 32 | 1 | 0 | 0 | 344,332 |
| 28×28, 64→192 | 64 | 1 | 0 | 0 | 344,332 |
| 28×28, 64→192 | 128 | 1 | 0 | 0 | 344,332 |
| 14×14, 96→192 | 32 | 1 | 0 | 0 | 86,284 |
| 14×14, 96→192 | 64 | 1 | 0 | 0 | 86,284 |
| 14×14, 96→192 | 128 | 1 | 0 | 0 | 86,284 |
| 14×14, 192→96 | 32 | 32 | 5,598 | 234 | 102,700 |
| 14×14, 192→96 | 64 | 64 | 0 | 0 | 102,700 |
| 14×14, 192→96 | 128 | 64 | 0 | 0 | 102,700 |

모든 depth에서 정확도와 expected stream mask completion이 통과했다. 원본 결과는 `experiment/results/mobilenetv4_pointwise_shape_sweep.csv`에 있다.

## 5. 출력 예시와 해석

```text
MOBILENETV4_BATCH_POINTWISE_RESULT
name[uib14_extra_project]
positions[196]
input_channels[192]
output_channels[96]
logic_epoch1_online_peak_open_masks[32]
logic_online_issue_blocked_channel_cycles[5598]
logic_blocked_wall_cycles[234]
total_cycle[102700]
```

- `positions`: pointwise GEMV를 수행한 공간 위치 수다.
- `online_peak_open_masks`: 동시에 조립 중이던 broadcast mask entry의 최대 개수다. Depth 32 실행에서는 backpressure로 32에 제한된다.
- `blocked_channel_cycles`: full queue 때문에 보류된 stream-cycle의 합이다.
- `blocked_wall_cycles`: 하나 이상의 stream이 보류된 실제 simulator cycle 수다.
- `total_cycle`: 해당 독립 pointwise 레이어의 완료 cycle이다.

## 6. 분석

### 6.1 공간 위치 수만으로 queue depth가 증가하지 않는다

`64→192` expand에서 위치 수를 196에서 784로 4배 늘려도 peak open mask는 1이었다. 현재 명령 순서에서는 각 ordinal mask가 다음 mask 유입 전에 완성되므로 공간 크기는 명령 수와 총 cycle을 늘리지만 동시 미완성 mask 수를 늘리지 않는다.

### 6.2 입력 channel block 수가 명령 조립 패턴을 바꾼다

`192→96` project는 독립 실행에서도 open mask가 최대 64개다. Depth 32에서는 234 wall-cycle의 역압력이 발생하지만 PCU busy 구간과 전부 겹쳐 총 cycle은 변하지 않았다. Depth 64부터 독립 레이어 역압력은 사라졌다.

### 6.3 독립 레이어만으로 RTL queue를 정하면 부족하다

30차 실제 UIB 연결 실행의 project peak는 78이었다. 동일한 `192→96` project 독립 실행의 peak 64보다 14 entries 크다. 선행 expand/depthwise 단계 이후의 PCU busy 상태와 project command 유입 위상이 겹치면서 미완성 mask가 더 쌓였기 때문이다.

따라서 queue depth는 다음 순서로 결정해야 한다.

1. 독립 연산 shape sweep으로 기본 동시성을 측정한다.
2. 실제 MobileNetV4 block 순서로 연결 실행해 epoch 경계의 위상 중첩을 측정한다.
3. PCU 수, latency, bandwidth를 바꾼 뒤 peak가 다시 증가하는지 확인한다.
4. 최악값에 설계 여유를 더해 RTL depth를 확정한다.

## 7. 설계 판단

- **64 entries:** 현재 독립 pointwise 세 형상은 수용하지만 실제 UIB 연결 실행에서는 53 wall-cycle의 역압력이 발생한다.
- **78 entries:** 현재 실제 UIB trace의 관측 최소치다. 2의 거듭제곱이 아니어서 RTL 제어와 메모리 구성이 불편하다.
- **128 entries:** 현재 검증 범위의 안전 후보이며 PCU/BW 변화와 다른 block을 위한 50-entry 여유가 있다.

현재 단계에서는 128 entries를 RTL 기준 후보로 유지한다. 64 entries는 면적 비교용 대안이며 성능 동등 사양으로 확정하지 않는다.

## 8. 한계와 다음 실험

현재 workload CSV는 MobileNetV4 ConvSmall 전체가 아니라 UIB 14 관련 일부 레이어만 포함한다. 다음 단계는 공식 block 목록에서 나머지 pointwise 형상을 workload CSV에 추가한 뒤, 독립 레이어가 아니라 block chain 단위로 자동 실행하는 것이다. 그 전에 PCU count와 logic bandwidth sweep을 queue depth와 교차해 128-entry 여유가 microarchitecture 변경에도 유지되는지 검증한다.
