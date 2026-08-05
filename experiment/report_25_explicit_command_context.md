# 25차 실험 보고서: Explicit Command Context와 동적 Channel Mask

## 1. 목적

이전 epoch release 모델은 scheduler가 channel별 도착 순서를 내부에서 세어 command ordinal을 추정했다. 이번 단계에서는 PIM 명령이 해독되는 `PIMRank`에서 ordinal을 생성해 명시적인 command context로 scheduler에 전달하고, channel별 명령 수가 달라도 broadcast mask가 안전하게 축소되는지 검증한다.

## 2. Command Context

```cpp
struct LogicCommandContext {
    uint64_t epochId;
    uint64_t commandOrdinal;
    uint64_t streamId;
    bool valid;
};
```

- `epochId`: 현재 shared-weight layer의 release epoch다.
- `commandOrdinal`: 해당 channel/rank가 epoch 안에서 해독한 logic 명령 순번이다.
- `streamId`: `channel * NUM_RANKS + rank`로 계산한 실행 stream 식별자다.
- `valid`: bank-side 명령이나 epoch release가 꺼진 경우 context를 무시한다.

Scheduler는 `{epochId, commandOrdinal, commandSignature}`가 같은 요청들의 `streamId`를 모아 동적 channel mask를 만든다.

## 3. 불균형 Stream 단위 테스트

3개 stream이 ordinal 0에 참여하고, stream 0만 ordinal 1을 갖는 입력을 사용했다.

```text
ordinal 0 mask = {0, 1, 2}, fanout 3
ordinal 1 mask = {0},       fanout 1
mask count     = 2
total fanout   = 4
```

모든 예상 stream이 epoch에 한 번 이상 참여해 ready mask는 완료됐으며, 마지막 ordinal은 기다리지 않고 실제 참여 stream 하나로 축소됐다. 이 테스트를 포함한 scheduler/weight-buffer 단위 테스트 9개가 모두 통과했다.

## 4. MobileNetV4 재실행 명령

```bash
FILL_POLICY=row_interleaved \
FILL_CHANNELS_LIST=32 \
BUFFER_WRITE_PORTS=0 \
BUFFER_WRITE_LATENCY=1 \
POST_FILL_GUARD_CYCLES=0 \
EPOCH_RELEASE=true \
RESULT_FILE=experiment/results/explicit_command_context_validation.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 5. 실제 UIB 결과

```text
outputs checked               = 18,816
release epochs                = 2
complete / incomplete masks   = 2 / 0
broadcast masks               = 1,616
broadcast total fanout        = 92,512
broadcast min / max fanout    = 8 / 64
global logic requests         = 92,512
dispatch / coalesced          = 1,616 / 90,896
total cycle                   = 214,228
```

`broadcast total fanout == global logic requests`이므로 모든 logic request가 정확히 하나의 mask에 포함됐다. 최소 fanout 8은 마지막 spatial wave처럼 일부 stream만 남은 동적 mask이며, 최대 64는 전체 channel이 같은 ordinal에 참여한 broadcast다.

## 6. 정확도와 트래픽 불변성

```text
CPU 기준과 일치한 출력       = 18,816 / 18,816
shared weight read hit/miss  = 702,464 / 0
physical weight bytes        = 114,688
physical writes              = 225,460
```

명시적 command context는 계산값과 메모리 트래픽을 바꾸지 않고 command dispatch 표현만 구체화했다. 이전 epoch 모델의 `214,228 cycle`도 그대로 재현됐다.

## 7. RTL 대응

RTL command queue는 최소한 다음 context를 명령과 함께 저장해야 한다.

```text
epoch_id | command_ordinal | opcode/signature | source/destination | stream/channel id
```

Coalescer는 같은 epoch와 ordinal의 명령을 모아 channel mask를 만든다. 모든 64 channel을 무조건 기다리면 마지막 wave에서 deadlock이 생길 수 있으므로 workload scheduler가 ordinal별 expected mask 또는 end-of-stream 정보를 함께 제공해야 한다.

## 8. 다음 단계

1. Expand와 project epoch별 fanout histogram을 분리한다.
2. 동시에 열려 있는 broadcast mask 수와 queue residency를 계측한다.
3. 그 결과로 RTL broadcast queue depth와 timeout 정책의 후보값을 정한다.
