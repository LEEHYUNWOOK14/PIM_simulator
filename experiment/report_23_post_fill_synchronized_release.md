# 23차 실험 보고서: Post-fill Synchronized Release

## 1. 목적

공유 weight buffer의 4-port 조건에서 나타난 성능 개선이 port 수 자체가 아니라 fill 완료 후 32개 HBM channel의 logic 명령이 같은 시점에 정렬되는 효과인지 검증한다.

## 2. 구현

`LOGIC_POST_FILL_GUARD_CYCLES`를 추가했다. 공유 weight의 DRAM fill과 buffer write가 모두 끝난 뒤, 각 pointwise layer의 첫 logic 명령을 release하기 전에 지정 cycle만큼 기다린다. 실제 누적 대기는 `logic_post_fill_guard_cycles`로 출력한다.

이 guard는 기능 정확도를 바꾸는 계산 지연이 아니라 buffer-ready/barrier와 command broadcast 사이의 제어 지연 모델이다. 기본값은 기존 동작을 유지하는 `0`이다.

## 3. 재실행 명령

WSL 터미널에서 저장소 루트로 이동한 뒤 실행한다.

```bash
bash experiment/run_post_fill_guard_sweep.sh
```

범위를 직접 지정할 수도 있다.

```bash
GUARD_LIST="0 64 128 256 333 512 666" \
  bash experiment/run_post_fill_guard_sweep.sh
```

결과는 `experiment/results/post_fill_guard_sweep.csv`에 저장된다. 스크립트는 실험 전 설정을 백업하고 종료 시 복원하며, 동시 실행 lock으로 두 sweep이 같은 설정 파일을 동시에 수정하지 못하게 한다.

## 4. 실험 조건

```text
MobileNetV4 UIB       : 14x14x96 -> 192 -> 96
Weight fill policy   : row_interleaved
Weight fill channels : 32
Write ports          : unlimited (0)
Write latency        : 1 cycle
Shared buffer        : 65,536 B
No-buffer 기준       : 219,854 cycles
4-port 비교점        : 215,969 cycles
```

## 5. 결과

| Guard/layer | 실제 누적 guard | Dispatch | Coalesced | Logic service | Total cycle | No-buffer 대비 |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 9,430 | 83,082 | 407,768 | 229,856 | +10,002 |
| 64 | 128 | 9,456 | 83,056 | 407,872 | 230,399 | +10,545 |
| **128** | **256** | **2,314** | **90,198** | **379,304** | **215,865** | **-3,989** |
| 256 | 512 | 2,240 | 90,272 | 379,008 | 215,968 | -3,886 |
| 333 | 666 | 2,244 | 90,268 | 379,024 | 216,116 | -3,738 |
| 512 | 1,024 | 3,484 | 89,028 | 383,984 | 218,956 | -898 |
| 666 | 1,332 | 8,504 | 84,008 | 404,064 | 229,327 | +9,473 |

모든 행에서 최종 출력 18,816개가 CPU 기준값과 일치했고, buffer read는 702,464 hit / 0 miss였다.

## 6. 출력 해석

```text
logic_post_fill_guard_cycles[256]
global_logic_dispatches[2314]
global_logic_coalesced[90198]
global_logic_service_cycles[379304]
total_cycle[215865]
```

- `logic_post_fill_guard_cycles[256]`: expand와 project 두 계층에 각각 128 cycle이 적용됐다.
- `global_logic_dispatches[2314]`: 92,512개 logic request가 실제 2,314번의 broadcast dispatch로 병합됐다.
- `global_logic_coalesced[90198]`: 동일 release epoch의 90,198개 request가 추가 dispatch 없이 합쳐졌다.
- `global_logic_service_cycles[379304]`: guard 0보다 28,464 cycle 감소했다.
- `total_cycle[215865]`: guard 비용 256 cycle을 추가하고도 command 정렬 이득이 더 커 최종 시간이 감소했다.

## 7. 판단

128 cycle/layer의 명시적 guard가 기존 4-port 자연 대기 결과보다 104 cycle 빠르며 거의 같은 dispatch 감소를 재현했다. 따라서 crossover의 직접 원인은 제한된 write port가 아니라 **buffer-ready 이후 channel command의 synchronized release와 broadcast coalescing**이다.

128은 현재 DRAM timing과 workload에서 얻은 후보값이지 RTL 상수의 정답은 아니다. RTL에서는 고정 시간 대기보다 `fill_done`, `buffer_ready`, `epoch_id`, `channel_ready_mask`를 이용해 모든 대상 channel을 같은 release epoch에 내보내는 handshake가 필요하다.

## 8. 다음 실험

1. 4 write ports와 명시적 release를 함께 켜 중복 대기가 생기는지 확인한다.
2. guard를 고정 cycle 대신 대상 channel ready-mask가 완성되는 조건으로 대체한다.
3. expand와 project의 fill 완료 시점이 다르므로 layer별 release 통계를 분리한다.
