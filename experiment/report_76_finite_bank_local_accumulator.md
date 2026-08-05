# 76차: 유한 Bank-local accumulator 자원 검증

## 1. 목적

75차의 bank-local accumulator는 기능적으로 무제한 map이었다. 이번 실험은 entry 수, update port 수, port latency를 설정 변수로 만들고 command-ready backpressure에 연결해 성능 이득이 유한 자원에서도 유지되는지 확인한다.

## 2. 추가한 설정

| 변수 | 의미 | 기본값 |
|---|---|---:|
| `BANK_LOCAL_ACCUMULATOR_ENTRIES` | rank당 동시에 유지할 output burst entry | 0, 무제한 |
| `BANK_LOCAL_ACCUMULATOR_PORTS` | cycle당 처리할 PIM-block partial 수 | 0, 무제한 |
| `BANK_LOCAL_ACCUMULATOR_LATENCY` | port service latency | 1 cycle |

Entry를 초과하면 설계 용량 부족으로 즉시 실패한다. Port가 busy이면 accumulator-direct command의 ready를 낮춰 command queue에서 기다리게 한다.

## 3. 필요한 entry 계산

현재 한 rank의 depthwise tile은 다음 entry를 동시에 보관한다.

```text
8 PIM blocks × 2 bank parity × 8 GRF columns = 128 entries/rank
```

실측 peak도 정확히 128 entries였다. Burst 하나는 FP16 16개, 즉 32 B이므로 data array만 계산하면 rank당 최소 4 KiB다. Valid, key, tap count, ECC, tag, banking 제어 bit는 별도 추가해야 한다.

## 4. 실제 shape micro 결과

| Entries | Ports | Cycle | Stalls | 정확도 |
|---:|---:|---:|---:|---:|
| 무제한 | 무제한 | 33,025 | 0 | 37,632 PASS |
| 128 | 8 | 33,138 | 25,344 | PASS |
| 128 | 4 | 33,622 | 43,968 | PASS |

Stalls는 후보 command의 ready 재시도 횟수 합계이며 wall-clock cycle과 같지 않다. 4 ports는 무제한보다 597 cycle 느리지만 bank-only 36,426보다 2,804 cycle(7.70%) 빠르다.

## 5. 전체 MobileNetV4 UIB 결과

| 구조 | Depthwise | Total | Writes | 정확도 |
|---|---:|---:|---:|---:|
| Bank-depthwise 기준 | 38,884 | 235,182 | 220,342 | 18,816 PASS |
| Local aggregation, 무제한 | 34,880 | 231,178 | 199,350 | PASS |
| 128 entries, 4 ports, latency 1 | **35,011** | **231,309** | **199,350** | **PASS** |

유한 후보는 무제한보다 131 cycle만 느리고 기준보다 3,873 cycle(1.65%) 빠르다. Modeled write 감소 20,992회(9.53%)도 유지됐다.

## 6. 현재 RTL 후보

```text
Hierarchy link                  64 B/cycle
Bank-local reduction factor    9 taps
Bank-local accumulator         128 entries/rank
Update ports                   4 partials/cycle
Port latency                   1 cycle
Logic-die final accumulator    8,192 burst entries (현재 workload peak)
```

이 값은 합성 전 simulator 후보다. 특히 rank마다 4 KiB 이상의 local data array를 둘지, 여러 bank가 소규모 register file을 분산 소유할지는 RTL에서 비교해야 한다.

## 7. 다음 작업

1. 128-entry buffer를 PIM block별 16-entry banked 구조로 분해한다.
2. Port conflict와 bank arbitration을 주소 기반으로 모델링한다.
3. Random FP16 입력에서 factor 1과 factor 9의 rounding 차이를 측정한다.
4. 다른 depthwise shape에서 peak entry가 128을 넘는지 확인한다.
5. Verilog 합성 결과로 entry/port latency와 주파수를 보정한다.

## 9. 후속 FP16 검증

77차 deterministic signed fractional 입력에서 factor 1과 factor 9 모두 FP16 golden 128개와 bit-equivalent하게 일치했다. FP32 기준 최대 절대오차도 0.00601459로 같았다. 현재 구현은 tap 순서를 유지하므로 aggregation이 FP16 결합 순서를 바꾸지 않는다.

## 8. 근거 파일

- `results/finite_bank_local_accumulator.csv`
- `results/depthwise_local_agg9_finite_e128_p8_l1.log`
- `results/depthwise_local_agg9_finite_e128_p4_l1.log`
- `results/full_uib_local_agg9_finite_e128_p4_l1.log`
