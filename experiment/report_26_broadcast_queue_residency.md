# 26차 실험 보고서: Broadcast Queue Residency

## 1. 목적

명시적 command context를 이용해 channel mask가 조립되는 동안 필요한 broadcast queue entry 수를 측정한다. 각 mask는 첫 참여 channel 명령이 도착한 cycle에 열리고 마지막 참여 channel이 도착한 cycle에 완성되는 것으로 정의한다.

## 2. 계측 정의

| 지표 | 의미 |
|---|---|
| Mask count | epoch에서 생성된 서로 다른 ordinal/signature 수 |
| Total fanout | 모든 mask의 참여 stream 수 합계 |
| Residency | 마지막 도착 cycle - 첫 도착 cycle |
| Peak open masks | assembly 구간이 동시에 겹친 mask의 최대 수 |

Peak open masks는 workload scheduler가 ordinal별 expected mask를 제공해 마지막 참여 stream 도착 즉시 mask를 닫을 수 있을 때의 queue depth 하한이다.

## 3. 재실행 명령

```bash
FILL_POLICY=row_interleaved \
FILL_CHANNELS_LIST=32 \
BUFFER_WRITE_PORTS=0 \
BUFFER_WRITE_LATENCY=1 \
POST_FILL_GUARD_CYCLES=0 \
EPOCH_RELEASE=true \
RESULT_FILE=experiment/results/broadcast_queue_residency.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 결과

| Epoch | MobileNetV4 계층 | Masks | Fanout | 최대 residency | 총 residency | 평균 residency | Peak open masks |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | Expand 96→192 | 720 | 42,336 | 0 | 0 | 0.0 | 1 |
| 2 | Project 192→96 | 896 | 50,176 | 728 | 181,176 | 202.2 | **78** |
| 합계 | - | 1,616 | 92,512 | - | - | - | - |

전체 fanout 92,512는 global logic request 92,512와 일치하며 정확도와 total cycle은 각각 18,816개 일치, 214,228 cycle로 유지됐다.

## 5. 해석

Expand 명령은 참여 channel이 같은 cycle에 정렬되어 mask assembly queue가 사실상 한 entry만 필요하다. Project는 channel 도착이 어긋나 최대 78개 mask가 동시에 열린다.

따라서 현재 스케줄에서는:

```text
64 entries  : 부족, 관측 peak보다 14 entries 작음
78 entries  : 측정 조건의 최소 경계
128 entries : 첫 power-of-two RTL 후보
```

## 6. 저장 공간 하한

최소 entry 형식을 다음처럼 가정한다.

```text
channel mask 64 bit
command signature 32 bit
epoch ID 16 bit
command ordinal 16 bit
합계 128 bit = 16 byte/entry
```

128 entries는 최소 2,048 byte다. 실제 RTL에서는 valid/ready, source/destination, precision, timeout 상태가 더 필요하므로 총 크기는 이보다 커진다.

## 7. 중요한 제한

현재 peak 78은 완성된 실행 trace를 사후 분석한 하한이다. 하드웨어가 mask를 언제 닫아야 하는지 알려면 workload scheduler가 ordinal별 expected channel mask 또는 end-of-stream 정보를 미리 제공해야 한다. 이 정보가 없으면 마지막 참여 channel을 알 수 없어 queue entry를 epoch 끝까지 유지해야 한다.

## 8. 다음 단계

1. `LOGIC_BROADCAST_QUEUE_DEPTH` 설정을 추가한다.
2. 64/78/128 entries에서 overflow와 backpressure cycle을 모델링한다.
3. Queue full 시 command issue를 멈추고 DRAM/PIM scheduler에 stall을 전달한다.
4. 128-entry 후보가 실제 timing 모델에서도 정확도를 유지하는지 확인한다.
