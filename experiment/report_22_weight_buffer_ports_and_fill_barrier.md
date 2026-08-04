# 22차 기술 구현 보고서: 공유 버퍼 Fill Barrier와 Write Port

## 1. 목적

21차까지 중앙 버퍼 데이터는 transaction enqueue 시 즉시 보였기 때문에 logic MAC이 모든 DRAM fill 완료 전에 시작할 수 있었다. 이번 단계는 실제 데이터 의존성을 보장하고 중앙 버퍼 write port의 수와 latency를 모델링한다.

## 2. 모델 정정

공유 가중치를 사용하는 각 pointwise 계층은 다음 순서를 따른다.

```text
HBM source read/write timing 완료
-> 모든 fill burst 중앙 buffer write 완료
-> layer fill-ready barrier 해제
-> logic MAC 시작
```

추가 설정:

```ini
LOGIC_WEIGHT_BUFFER_WRITE_PORTS=0
LOGIC_WEIGHT_BUFFER_WRITE_LATENCY=1
```

- `WRITE_PORTS=0`: 중앙 버퍼 port 병목이 없는 상한선
- `WRITE_PORTS=N`: 동시에 N개 burst write 가능
- `WRITE_LATENCY`: 한 port가 burst 하나를 처리하는 cycle

## 3. 단위 테스트

2개 port, latency 3 cycle에 같은 cycle의 burst 4개를 넣으면 완료 시점은 다음과 같아야 한다.

```text
13, 13, 16, 16 cycle
```

이 scheduler 테스트를 포함해 logic scheduler/weight buffer 단위 테스트 7개가 통과했다.

## 4. 재현 명령

```bash
bash experiment/run_weight_buffer_port_sweep.sh
```

결과:

```text
experiment/results/shared_weight_buffer_port_sweep.csv
```

특정 latency:

```bash
PORTS_LIST=4 BUFFER_WRITE_LATENCY=4 \
RESULT_FILE=experiment/results/my_ports4_latency4.csv \
bash experiment/run_weight_buffer_port_sweep.sh
```

## 5. Fill Barrier 영향

32채널 row-interleaved, 무제한 port 조건:

| 모델 | Cycle |
|---|---:|
| 기존 즉시-visible 모델 | 219,729 |
| Fill-ready barrier 적용 | 229,856 |

이전 모델은 fill과 compute의 데이터 의존성이 보장되지 않은 채 약 10,000 cycle을 겹쳐 실행했다. 따라서 21차의 219,729 cycle crossover는 최신 성능 근거로 사용하면 안 된다.

## 6. Write Port Sweep

Port latency 1 cycle:

| Ports | Port wait | Dispatches | Coalesced | Total cycle |
|---:|---:|---:|---:|---:|
| Unlimited(0) | 0 | 9,430 | 83,082 | 229,856 |
| 1 | 3,354 | 별도 원본 CSV 참조 | - | 218,957 |
| 2 | 1,562 | 별도 원본 CSV 참조 | - | 217,189 |
| **4** | **666** | **2,336** | **90,176** | **215,969** |
| 8 | 218 | 5,622 | 86,890 | 222,845 |
| 16 | 2 | 9,430 | 83,082 | 229,857 |
| 32 | 0 | 9,430 | 83,082 | 229,856 |

Port 수에 따라 cycle이 단조 감소하지 않는다. 4-port의 666-cycle wait 동안 fill에 사용된 DRAM bank timing 제약이 정리되고, 이후 32 channel의 동일 logic 명령이 같은 cycle에 더 많이 정렬된다.

Logic request 수는 모든 경우 92,512개로 같다. 4-port에서는 dispatch가 9,430에서 2,336으로 줄고 coalesced request가 83,082에서 90,176으로 늘어 global service cycle이 407,768에서 379,392로 감소했다.

즉 4-port 결과는 port가 무제한보다 계산이 빠른 것이 아니라 **fill 완료와 command broadcast 사이의 synchronization 효과**다.

## 7. Port Latency Sweep

4 ports:

| Latency | Port wait | Dispatches | Coalesced | Total cycle | 219,854 기준 |
|---:|---:|---:|---:|---:|---|
| 1 | 666 | 2,336 | 90,176 | 215,969 | 통과 |
| 2 | 1,562 | 2,320 | 90,192 | 217,189 | 통과 |
| 4 | 3,354 | 2,306 | 90,206 | 218,957 | 통과 |
| 8 | 6,940 | 4,432 | 88,080 | 226,757 | 실패 |

현재 모델에서 허용 가능한 검증 범위는 4 ports, latency 1~4 cycles다.

## 8. 정확도와 트래픽

모든 sweep 행에서 다음 값이 유지됐다.

```text
MobileNetV4 outputs checked = 18,816
physical weight bytes       = 114,688
physical writes             = 225,460
buffer fill completed       = 3,584 / 3,584
buffer read hits/misses     = 702,464 / 0
```

따라서 port 모델은 기능값이나 트래픽 감소량을 바꾸지 않고 timing만 변경한다.

## 9. 최신 RTL 후보

```systemverilog
parameter int WEIGHT_BUFFER_BYTES          = 65536;
parameter int WEIGHT_FILL_CHANNELS         = 32;
parameter string WEIGHT_FILL_POLICY        = "row_interleaved";
parameter int WEIGHT_BUFFER_WRITE_PORTS    = 4;
parameter int WEIGHT_BUFFER_WRITE_LATENCY  = 1; // 1~4 cycle 검증 통과
```

필수 제어:

1. 모든 layer weight fill 완료를 나타내는 barrier
2. 4-port ready/valid arbitration
3. buffer-ready 후 channel command release 동기화
4. 동일 command의 channel-mask broadcast coalescing

## 10. 주의점과 다음 단계

4-port 최적점은 DRAM timing과 command coalescing의 상호작용으로 생겼다. RTL에서 동일한 이득을 주장하려면 “buffer ready 후 32 channel command를 같은 epoch에 release한다”는 제어가 실제로 구현되어야 한다.

다음 구현은 port wait에 우연히 의존하지 않고 명시적인 post-fill synchronized release를 모델링한다. guard cycle을 sweep해 4-port latency 변화에도 dispatch 약 2,300개 수준을 안정적으로 유지하는지 검증한다.
