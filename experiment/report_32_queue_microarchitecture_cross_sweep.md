# 32차 실험 보고서: PCU·대역폭·queue depth 교차 검증

## 1. 실험 목적

Logic-die PCU 개수와 데이터 대역폭을 바꿨을 때 128-entry broadcast-mask queue 후보가 계속 안전한지 확인한다. 개별 pointwise가 아니라 실제 MobileNetV4 UIB의 expand→depthwise→project→add→ReLU 연결 실행을 사용한다.

## 2. 재현 명령

프로젝트 루트의 WSL 터미널에서 실행한다.

```bash
bash experiment/run_logic_queue_microarchitecture_sweep.sh
```

범위를 줄이려면 다음처럼 지정한다.

```bash
LOGIC_UNITS_LIST="8 16 32" \
LOGIC_BW_LIST="32 64 128" \
DEPTH_LIST="64 128" \
bash experiment/run_logic_queue_microarchitecture_sweep.sh
```

스크립트는 각 실행 전에 hybrid PIM, shared weight buffer, epoch release와 online backpressure를 설정하고 종료 시 원래 설정 파일을 복구한다.

## 3. 공통 조건

| 항목 | 값 |
|---|---:|
| workload | MobileNetV4 UIB 14 전체 연결 |
| logic PCU | 8, 16, 32 |
| logic bandwidth | 32, 64, 128 B/cycle |
| queue depth | 64, 128 |
| PCU latency | 2 cycles |
| shared weight buffer | 65,536 B |
| weight fill | 32 channels, `row_interleaved` |
| command overhead | 4 cycles |

## 4. 결과

다음 표의 peak는 backpressure가 없는 depth 128 실행에서 얻은 project epoch의 최대 open mask다. `D64 정지`는 depth 64에서의 blocked channel-cycle이다.

| PCU | BW (B/cycle) | Peak | D64 정지 | D64 wall-cycle | 총 cycle |
|---:|---:|---:|---:|---:|---:|
| 8 | 32 | 64 | 0 | 0 | 771,467 |
| 8 | 64 | 78 | 211 | 53 | 402,168 |
| 8 | 128 | 64 | 0 | 0 | 217,408 |
| 16 | 32 | 70 | 91 | 23 | 398,486 |
| 16 | 64 | 78 | 211 | 53 | 214,228 |
| 16 | 128 | 64 | 0 | 0 | 121,471 |
| 32 | 32 | 76 | 191 | 48 | 212,287 |
| 32 | 64 | 78 | 211 | 53 | 120,229 |
| 32 | 128 | 65 | 15 | 4 | 74,016 |

각 행에서 depth 64와 128의 총 cycle은 같았다. 18개 실행 모두 출력 정확도 통과, release incomplete mask 0, weight-buffer read miss 0을 유지했다.

## 5. 출력 예시와 주석

```text
logic_units[16]
logic_bw[64]
logic_epoch2_online_peak_open_masks[78]
logic_online_issue_blocked_channel_cycles[211]
logic_online_issue_busy_overlap_channel_cycles[211]
logic_blocked_wall_cycles[53]
global_logic_service_cycles[376512]
total_cycle[214228]
```

- `online_peak_open_masks`: 동시에 조립 중인 project mask entry 최대치다.
- `blocked_channel_cycles`: depth 64가 새 mask를 받지 못해 stream별로 대기한 cycle의 합이다.
- `busy_overlap_channel_cycles`: 위 대기 중 logic PCU가 이미 바빴던 부분이다. 모든 조합에서 blocked 값과 같았다.
- `global_logic_service_cycles`: 모든 logic command의 service 비용을 누적한 통계다. 여러 PCU의 병렬 실행을 합한 값이므로 총 wall-clock cycle과 직접 비교하면 안 된다.
- `total_cycle`: 전체 UIB가 끝난 simulator cycle이다.

## 6. 분석

### 6.1 128 entries는 현재 microarchitecture 범위를 수용한다

depth 128에서 최대 peak는 78이었다. PCU 8~32, BW 32~128 B/cycle의 모든 조합에서 queue full과 online issue 정지가 없었다. 현재 검증 범위에서 50 entries의 관측 여유가 있다.

### 6.2 queue 압력은 PCU나 BW에 대해 단조롭지 않다

BW 64에서는 PCU 개수와 무관하게 peak 78이지만 BW 32에서는 PCU 증가에 따라 peak가 64→70→76으로 증가했다. BW 128에서는 64~65로 낮아졌다. 이는 queue 점유가 단순 연산량이 아니라 다음 세 시간축의 상대 위상으로 결정되기 때문이다.

1. HBM channel별 command 도착 시간
2. mask를 완성하는 마지막 stream의 도착 시간
3. logic PCU가 이전 command를 비우는 시간

따라서 RTL queue 식을 `fanout × channel 수`처럼 정적인 값 하나로 만들면 안 된다. cycle-accurate 연결 실행의 peak를 사용해야 한다.

### 6.3 depth 64의 정지는 현재 critical path 밖에 있다

depth 64에서 발생한 정지는 모두 PCU busy와 겹쳤고 총 cycle을 늘리지 않았다. 그러나 이것은 64 entries가 항상 안전하다는 뜻이 아니다. RTL에서는 upstream command buffer 점유, bank-side command 공정성, 다른 workload와의 동시 실행에 영향을 줄 수 있다. 64 entries는 성능 동등 사양이 아니라 면적 절감용 실험 후보로 남긴다.

### 6.4 PCU와 BW는 모두 성능에 큰 영향을 준다

기준 `16 PCU, 64 B/cycle`은 214,228 cycle이다. 같은 PCU에서 BW를 32로 낮추면 398,486 cycle, 128로 높이면 121,471 cycle이다. 같은 BW 64에서 PCU를 8로 줄이면 402,168 cycle, 32로 늘리면 120,229 cycle이다. 현재 범위에서는 PCU와 BW 어느 한쪽만 크게 늘리는 것보다 두 자원의 균형과 면적·전력 비용을 함께 비교해야 한다.

## 7. 설계 판단

| 항목 | 현재 판단 |
|---|---|
| RTL queue 기준 후보 | 128 entries |
| 면적 비교 후보 | 64 entries |
| 관측 최대 peak | 78 entries |
| 기준 PCU/BW | 16 PCU, 64 B/cycle |
| 고성능 후보 | 32 PCU, 128 B/cycle, 74,016 cycle |

고성능 후보는 면적, 전력, 배선 폭을 아직 반영하지 않은 성능 상한 후보일 뿐이다. 최종 PCU/BW 값은 연구자가 정한 하드웨어 예산과 RTL 합성 결과가 필요하다.

## 8. 다음 단계

다음 기술 구현은 queue가 full일 때 한 MemoryController가 막힌 command 때문에 다른 독립 command까지 함께 보류하는 head-of-line blocking을 분리 계측하는 것이다. 그 후 bank-side와 logic-side가 동시에 요청을 낼 때의 arbitration 정책을 구현해 계층형 PIM의 실제 공유 자원 병목을 검증한다.
