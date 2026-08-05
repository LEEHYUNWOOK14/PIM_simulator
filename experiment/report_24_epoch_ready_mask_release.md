# 24차 실험 보고서: Epoch Ready-mask Release

## 1. 목적

23차의 고정 `128 cycle/layer` guard를 실제 RTL 제어에 가까운 동기화 규칙으로 교체한다. 시간만 기다리는 대신 fill 완료 후 대상 channel의 ready mask를 확인하고, 동일한 명령 순번을 하나의 broadcast로 release한다.

## 2. 구현 규칙

`LOGIC_EPOCH_RELEASE=true`이면 다음 키가 같은 logic 명령을 병합한다.

```text
release key = epoch_id + command_ordinal + command_signature
```

- `epoch_id`: 공유 weight layer의 fill barrier가 완료될 때 증가한다.
- `command_ordinal`: 각 channel/rank stream에서 해당 epoch의 몇 번째 명령인지 나타낸다.
- `command_signature`: opcode와 operand encoding을 나타낸다.
- `channel_ready_mask`: 해당 epoch에 참여해야 하는 stream이 모두 실제 명령을 제출했는지 검증한다.

서로 다른 cycle에 도착해도 세 필드가 같으면 한 번의 channel-mask broadcast로 처리한다. 같은 stream의 다음 명령은 ordinal이 달라 잘못 병합되지 않는다.

## 3. 재실행 명령

```bash
bash experiment/run_epoch_release_comparison.sh
```

ready-mask 검증만 다시 실행하려면 다음 명령을 사용한다.

```bash
FILL_POLICY=row_interleaved \
FILL_CHANNELS_LIST=32 \
BUFFER_WRITE_PORTS=0 \
POST_FILL_GUARD_CYCLES=0 \
EPOCH_RELEASE=true \
RESULT_FILE=experiment/results/epoch_release_ready_mask_validation.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 비교 결과

| 조건 | Guard | Port wait | Epoch | Dispatch | Coalesced | Service | Total cycle |
|---|---:|---:|---:|---:|---:|---:|---:|
| 기존, guard 0 | 0 | 0 | 0 | 9,430 | 83,082 | 407,768 | 229,856 |
| 고정 guard 128/layer | 256 | 0 | 0 | 2,314 | 90,198 | 379,304 | 215,865 |
| **Epoch release** | **0** | **0** | **2** | **1,616** | **90,896** | **376,512** | **214,228** |
| 4-port + epoch release | 0 | 666 | 2 | 1,616 | 90,896 | 376,512 | 214,903 |

기준값은 no-buffer hybrid `219,854 cycle`이다. Epoch release는 기준보다 5,626 cycle, 고정 guard 최적점보다 1,637 cycle 빠르다.

## 5. Ready-mask 검증

```text
logic_release_epochs[2]
logic_release_max_streams[64]
logic_release_complete_masks[2]
logic_release_incomplete_masks[0]
outputs_checked[18816]
logic_weight_buffer_read_hits[702464]
logic_weight_buffer_read_misses[0]
```

- expand는 21 spatial group x 3 channels로 63개 stream을 예상한다.
- project는 32 spatial group x 2 channels로 64개 stream을 예상한다.
- 두 epoch 모두 예상 mask와 실제 참여 mask가 일치했다.
- 최종 출력 18,816개가 모두 CPU 기준값과 일치했다.
- 공유 weight buffer read miss는 없었다.

## 6. 해석

Epoch release는 임의의 128-cycle 상수를 쓰지 않고도 더 많은 명령을 병합했다. 따라서 이 구조의 성능 근거는 대기 시간 튜닝이 아니라 **채널 간 명령 스트림을 epoch와 ordinal로 정렬해 broadcast하는 제어 구조**로 설명할 수 있다.

4-port 결합 결과는 무제한 port보다 675 cycle 느리며 측정된 port wait 666 cycle과 거의 같다. Epoch 제어가 이미 명령 정렬을 담당하므로 port 제한은 순수한 buffer write 비용으로 분리된다.

## 7. 설계 주의점

현재 command ordinal은 simulator가 channel별 도착 순서로 생성한다. RTL에서는 packet 또는 command queue에 `epoch_id`와 `command_ordinal`을 명시적으로 저장해야 한다. 분기나 channel별 명령 생략이 있는 workload에서는 활성 channel mask를 ordinal마다 축소하거나 predication bit를 보내야 한다.

다음 구현은 ordinal을 명시적 command context로 이동하고, stream별 명령 수가 다른 경우에도 마지막 ordinal에서 deadlock 없이 mask를 축소하는 규칙을 검증한다.

이 후속 구현과 검증은 `report_25_explicit_command_context.md`에 기록했다. scheduler 내부 도착 순서 추정값을 제거하고 `PIMRank`가 명시적인 context를 생성하도록 변경했다.
