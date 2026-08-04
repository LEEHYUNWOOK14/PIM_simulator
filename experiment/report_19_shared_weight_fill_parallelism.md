# 19차 기술 구현 보고서: 공유 가중치 버퍼 Fill 병렬화

> 후속 21차 실험에서 32채널 `row_interleaved`가 219,729 cycle로 기준을 통과했다. 64채널 round-robin은 최초 결과이며, 면적을 고려한 최신 후보는 32채널 row-interleaved다.

## 1. 목적

18차 실험에서 64 KiB 공유 버퍼는 가중치 트래픽을 96.34% 줄였지만, 한 벌의 가중치를 2~3개 compact channel로만 적재해 cycle이 5.11% 증가했다. 이번 실험은 동일한 한 벌을 여러 HBM channel에서 중앙 버퍼로 가져오는 striping 경로를 추가하고 필요한 fill 병렬도를 찾는다.

## 2. 추가 변수

```ini
LOGIC_WEIGHT_FILL_CHANNELS=0
```

- `0`: 기존 compact group channel을 그대로 사용한다. expand는 3개, project는 2개 channel이다.
- `1~NUM_CHANS`: 가중치 fill source write를 지정한 수의 channel에 round-robin 배치한다.
- 중앙 버퍼의 canonical weight 주소는 바뀌지 않는다. source transaction의 물리 channel만 바뀐다.
- 기본값은 0이므로 이전 실험 결과를 보존한다.

## 3. 실험 조건

```text
Global logic PCU        = 16
Logic/hierarchy BW      = 64 B/cycle
Command overhead        = 4 cycles
Command coalescing      = true
Shared weight buffer    = 65,536 B
Workload                = MobileNetV4 actual UIB
No-buffer hybrid cycle  = 219,854
Bank-side cycle         = 346,600
```

## 4. 재현 명령

```bash
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

세부 구간을 지정할 수도 있다.

```bash
FILL_CHANNELS_LIST='40 48 56 60 64' \
RESULT_FILE=experiment/results/my_fill_sweep.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

스크립트는 설정 파일을 백업·복원하며 일시적인 OneDrive/WSL 파일 열기 실패에 최대 3회 재시도한다.

통합 결과:

```text
experiment/results/shared_weight_fill_channel_sweep_full.csv
```

## 5. 결과

| Fill channels | Weight B | Actual writes | Buffer hits | Misses | Cycle |
|---:|---:|---:|---:|---:|---:|
| Natural(0) | 114,688 | 225,460 | 702,464 | 0 | 231,084 |
| 4 | 114,688 | 225,460 | 702,464 | 0 | 225,540 |
| 8 | 114,688 | 225,460 | 702,464 | 0 | 224,716 |
| 16 | 114,688 | 225,460 | 702,464 | 0 | 223,414 |
| 32 | 114,688 | 225,460 | 702,464 | 0 | 224,150 |
| 40 | 114,688 | 225,460 | 702,464 | 0 | 226,365 |
| 48 | 114,688 | 225,460 | 702,464 | 0 | 225,208 |
| 56 | 114,688 | 225,460 | 702,464 | 0 | 230,085 |
| 60 | 114,688 | 225,460 | 702,464 | 0 | 232,383 |
| 64 | 114,688 | 225,460 | 702,464 | 0 | 219,405 |

모든 실행에서 최종 출력 18,816개가 일치했고 buffer miss는 0이었다.

## 6. 해석

64채널 fill은 자연 매핑보다 11,679 cycle, 5.05% 빠르다. 또한 공유 버퍼 없는 동일 hybrid 기준 219,854 cycle보다 449 cycle, 0.20% 빠르다. 따라서 다음 두 효과를 동시에 확보했다.

```text
가중치 트래픽 감소 = 96.34%
전체 write 감소 = 29.47%
no-buffer 대비 cycle 감소 = 0.20%
```

4~60채널 결과는 단조 감소하지 않는다. round-robin channel 수가 달라지면 각 channel의 bank/row 순서와 compute transaction과의 경합도 함께 달라지기 때문이다. 이 결과를 순수한 대역폭 곡선으로 해석하면 안 된다.

현재 측정점에서는 64채널만 no-buffer 기준을 통과했다. 이는 **현재 round-robin 주소 매핑 정책에서 확인된 crossover**이며, 모든 fill 정책에 대한 수학적 최소 채널 수를 뜻하지 않는다.

## 7. 설계 판단

MobileNetV4 UIB 기반 1차 RTL 후보는 다음과 같다.

```systemverilog
parameter int WEIGHT_BUFFER_BYTES = 65536;
parameter int WEIGHT_FILL_CHANNELS = 64;
```

하지만 64채널 전체에서 데이터가 들어오려면 channel-to-logic-die crossbar, arbitration, buffer write port 수가 필요하다. 면적과 배선 비용을 포함하지 않은 상태에서 64를 최종 설계값으로 확정하면 안 된다.

## 8. 다음 기술 구현

추가로 `LOGIC_WEIGHT_FILL_POLICY=bank_aware`를 구현해 16/32/64채널에서 비교했다.

| Channels | Round-robin | Bank-aware |
|---:|---:|---:|
| 16 | 223,414 | 223,414 |
| 32 | 224,150 | 224,150 |
| 64 | 219,405 | 219,405 |

현재 weight preload 순서가 이미 bank를 고르게 순회하므로 bank별 요청 개수만 균등화하는 정책은 효과가 없었다. 비단조성의 원인을 찾으려면 요청 개수가 아니라 row 전환과 command queue 완료 시점을 측정해야 한다.

20차 계측에서 16/32/64채널의 channel별 write는 완전히 균등했으며, fill PRE는 각각 384/768/0으로 측정됐다. 상세 내용은 `report_20_shared_weight_fill_timing_diagnosis.md`에 기록한다.

다음 단계는 fill channel 수와 bank/row 충돌을 분리하는 것이다.

1. channel별 fill transaction과 마지막 완료 cycle을 출력한다.
2. row activation/precharge 수를 fill transaction만 따로 집계한다.
3. compute 시작 전에 전 채널 fill barrier가 필요한 경우와 overlap 가능한 경우를 분리한다.
4. 필요한 buffer write port 수와 RTL arbitration 입력으로 변환한다.
