# 21차 기술 구현 보고서: Row-interleaved 가중치 Fill 레이아웃

> **최신 정정:** 22차에서 fill-ready barrier를 추가한 결과 무제한 port의 cycle은 229,856이다. 이 문서의 219,729는 fill과 compute가 잘못 겹친 이전 모델 결과이므로 최신 성능 주장에 사용하지 않는다. 4 write ports와 명시적 barrier를 적용한 최신 결과는 215,969 cycle이다.

## 1. 목적

64개 HBM channel 전체를 중앙 공유 버퍼 fill에 연결하지 않고도 no-buffer hybrid 성능 기준을 통과할 수 있는 가중치 source layout을 찾는다.

20차 진단에서 32채널 round-robin은 fill-induced PRE 768개 때문에 224,150 cycle이었다. 이번 구현은 전용 staging row 안에서 bank를 교차 사용해 row locality와 bank-level parallelism을 동시에 확보한다.

## 2. 추가 설정

```ini
LOGIC_WEIGHT_FILL_POLICY=row_interleaved
LOGIC_WEIGHT_STAGING_ROW=2048
```

`row_interleaved` 주소 순서:

```text
bank0-col0, bank1-col0, ... bank15-col0,
bank0-col1, bank1-col1, ... bank15-col1
```

한 channel의 한 staging row는 `16 banks × 16 transaction columns = 256 bursts`를 저장한다. MobileNetV4 UIB에서 16채널은 channel당 최대 224 burst, 32채널은 112 burst이므로 모두 한 row 안에 들어간다.

중앙 버퍼 canonical 주소는 기존과 동일하며 source HBM layout만 변경한다. 따라서 logic MAC의 weight 의미와 정확도는 바뀌지 않는다.

## 3. 재현 명령

```bash
FILL_POLICY=row_interleaved \
FILL_CHANNELS_LIST='16 32 64' \
RESULT_FILE=experiment/results/shared_weight_fill_row_interleaved.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

32채널 아래 경계:

```bash
FILL_POLICY=row_interleaved \
FILL_CHANNELS_LIST='20 24 28 30 31' \
RESULT_FILE=experiment/results/my_row_interleaved_refinement.csv \
bash experiment/run_shared_weight_fill_channel_sweep.sh
```

## 4. 레이아웃 비교

| Policy | Channels | ACT | PRE | Fill completion | Total cycle |
|---|---:|---:|---:|---:|---:|
| Round-robin | 16 | 768 | 384 | 109,941 | 223,414 |
| Row-local contiguous | 16 | 112 | 0 | 110,328 | 223,747 |
| Row-interleaved | 16 | 512 | 0 | 109,889 | 221,870 |
| Round-robin | 32 | 1,536 | 768 | 109,528 | 224,150 |
| Row-local contiguous | 32 | 128 | 0 | 109,714 | 227,073 |
| **Row-interleaved** | **32** | **1,024** | **0** | **109,388** | **219,729** |
| Round-robin | 64 | 1,536 | 0 | 108,496 | 219,405 |
| Row-local contiguous | 64 | 128 | 0 | 108,553 | 219,752 |
| Row-interleaved | 64 | 2,048 | 0 | 108,495 | 219,404 |

Contiguous row-local은 PRE는 제거하지만 한 bank를 연속 사용해 bank 병렬성을 잃는다. Row-interleaved는 PRE 0을 유지하면서 여러 bank에 command를 분산한다.

## 5. 32채널 경계 실험

| Channels | Min/max writes/channel | PRE | Cycle | No-buffer 기준 통과 |
|---:|---:|---:|---:|---|
| 20 | 178/180 | 0 | 228,615 | 실패 |
| 24 | 149/150 | 0 | 222,098 | 실패 |
| 28 | 127/129 | 0 | 224,099 | 실패 |
| 30 | 119/121 | 0 | 226,940 | 실패 |
| 31 | 115/117 | 0 | 226,757 | 실패 |
| **32** | **112/112** | **0** | **219,729** | **통과** |

현재 측정 범위에서 32채널이 최초 crossover다. 32는 전체 fill burst가 균등하게 배치되고 channel/bank 주소 패턴이 대칭인 지점이다.

## 6. 성능과 트래픽

No-buffer hybrid 기준은 219,854 cycle이다.

```text
32-channel row-interleaved = 219,729 cycle
cycle 감소               = 125 cycle, 0.057%
가중치 트래픽 감소       = 96.34%
전체 write 감소          = 29.47%
```

정확도와 기능 통계:

```text
outputs checked       = 18,816
buffer hits           = 702,464
buffer misses         = 0
fill writes completed = 3,584 / 3,584
```

## 7. 설계 판단

32채널 row-interleaved는 64채널 round-robin과 비교해 logic-die fill 입력 수를 절반으로 줄이면서 성능 기준을 통과했다. 따라서 면적을 고려한 1차 RTL 후보로 더 적합하다.

다만 no-buffer 대비 성능 여유가 0.057%로 매우 작다. RTL arbitration, buffer write latency, 배선 지연을 추가하면 crossover가 사라질 수 있다. 다음 두 후보를 함께 유지해야 한다.

| 후보 | 장점 | 위험 |
|---|---|---|
| 32ch row-interleaved | crossbar·arbiter 입력 절반 | 성능 여유 125 cycle뿐 |
| 64ch row-interleaved | 219,404 cycle, 더 큰 여유 | 면적·배선·write port 부담 |

## 8. RTL 요구사항

```systemverilog
parameter int WEIGHT_BUFFER_BYTES  = 65536;
parameter int WEIGHT_FILL_CHANNELS = 32;
parameter int WEIGHT_STAGING_ROW   = 2048;
parameter string WEIGHT_FILL_POLICY = "row_interleaved";
```

필요한 기능:

1. 32개 channel 입력 arbitration
2. bank-interleaved source address generator
3. 중앙 buffer canonical address 변환
4. 계층 경계 buffer invalidate/refill
5. fill 완료 barrier와 logic MAC 시작 조건

## 9. 다음 단계

현재 중앙 버퍼는 data를 즉시 저장하고 DRAM transaction으로 fill timing을 반영한다. 다음 구현은 buffer write port 수와 arbitration latency를 명시적인 설정으로 추가해 32채널 후보가 현실적인 1/2/4/8 write-port 조건에서도 crossover를 유지하는지 검증하는 것이다.
