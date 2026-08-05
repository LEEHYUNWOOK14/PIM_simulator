# 74차: Depthwise 부분합 전송 overlap과 link bandwidth crossover

## 1. 목적

73차 logic-die accumulator는 전체 UIB 정확도와 DRAM write 감소를 검증했지만 64 B/cycle 부분합 전송을 tap마다 직렬 대기해 기준 구조보다 느렸다. 이번 실험은 bank MUL stage와 accumulator link를 겹치고, link bandwidth를 64/128/256 B/cycle로 바꿔 최초 성능 crossover를 찾는다.

## 2. 모델링 방법

`LOGIC_ACCUMULATOR_OVERLAP=true`이면 tap별 bank stage가 진행된 cycle만큼 link transfer를 동시에 진행한다.

```text
raw_transfer_cycle = ceil(partial_bytes / bandwidth) + latency
overlap_cycle      = min(raw_transfer_cycle, bank_stage_window)
wait_cycle         = raw_transfer_cycle - overlap_cycle
```

Raw, overlap, wait cycle을 별도로 기록한다. 이 모델은 bank stage 전체에서 streaming이 가능하다는 1차 상한 모델이며, RTL에는 FIFO와 `partial_valid/partial_ready` handshake가 필요하다.

## 3. 실제 shape depthwise 결과

| 경로 | BW | Cycle | Bank-only 대비 | 정확도 |
|---|---:|---:|---:|---:|
| Bank-only | - | 36,426 | 기준 | 37,632 PASS |
| Logic serial | 64 B/cycle | 66,716 | +83.16% | PASS |
| Logic overlap | 64 B/cycle | 59,023 | +62.04% | PASS |
| Logic overlap | 128 B/cycle | 42,639 | +17.06% | PASS |
| Logic overlap | 256 B/cycle | 34,447 | -5.43% | PASS |

256 B/cycle에서 처음으로 bank-only depthwise보다 1,979 cycle 빨라졌다.

## 4. 전체 MobileNetV4 UIB 결과

| 경로 | Total cycle | Depthwise cycle | Modeled writes | 정확도 |
|---|---:|---:|---:|---:|
| Bank-depthwise 기준 | 235,182 | 38,884 | 220,342 | 18,816 PASS |
| Logic serial 64 B/cycle | 265,022 | 68,724 | 199,350 | PASS |
| Logic overlap 64 B/cycle | 256,484 | 59,928 | 199,350 | PASS |
| Logic overlap 256 B/cycle | 231,650 | 35,352 | 199,350 | PASS |

256 B/cycle 후보는 기준보다 3,532 cycle(1.50%) 빠르고 modeled write를 20,992회(9.53%) 줄였다. Logic serial과 비교하면 33,372 cycle(12.59%) 개선됐다.

## 5. 설계 판단

- 계층형 누산은 기능적으로 검증됐고, 충분한 link bandwidth와 streaming이 있으면 cycle과 I/O를 동시에 개선할 수 있다.
- 현재 crossover는 256 B/cycle이다. 이는 2,048-bit/cycle이므로 배선·TSV·주파수·전력 비용이 작지 않을 수 있다.
- 따라서 256 B/cycle을 곧바로 확정 사양으로 선택하면 안 된다.
- 다음 최적화는 link를 넓히는 것만이 아니라 bank-side에서 여러 partial을 local aggregation한 뒤 보내 bytes 자체를 줄이는 것이다.
- 128 B/cycle에서 tile aggregation으로 wait 13,168 cycle을 줄일 수 있다면 더 현실적인 후보가 될 수 있다.

## 6. 다음 실험

1. Tap 2개 또는 3개를 bank-side에서 local accumulation한 뒤 logic die로 전송한다.
2. 64/128 B/cycle에서 aggregation factor 1/3/9를 교차 실험한다.
3. Accumulator FIFO depth와 backpressure를 유한하게 모델링한다.
4. Verilog에서 256 B/cycle 배선 후보와 128 B/cycle+aggregation 후보를 각각 합성한다.
5. 면적·전력·timing 결과를 simulator 파라미터에 다시 입력한다.

## 8. 후속 결과

75차에서 bank-local aggregation을 추가한 결과 128 B/cycle·factor 3은 231,727 cycle, 64 B/cycle·factor 9는 231,178 cycle을 달성했다. 따라서 넓은 256 B/cycle link보다 depthwise 지역성을 활용해 bytes를 줄이는 구조가 더 좋은 후보로 갱신됐다.

## 7. 근거 파일

- `results/depthwise_overlap_bandwidth_sweep.csv`
- `results/depthwise_hierarchical_overlap_64b.log`
- `results/depthwise_hierarchical_overlap_128b.log`
- `results/depthwise_hierarchical_overlap_256b.log`
- `results/full_uib_depthwise_overlap_64b.log`
- `results/full_uib_depthwise_overlap_256b.log`
