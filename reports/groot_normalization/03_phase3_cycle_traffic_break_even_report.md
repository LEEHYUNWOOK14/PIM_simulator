# Phase 3 보고서: Cycle/Traffic 모델과 Offload Break-even Sweep

- 수행일: 2026-08-11
- 모델: `tools/groot_normalization_model.py`
- 기준 parameter: `common_model_parameters.json`
- 결과: `results/reference_architecture_comparison.csv`, `results/offload_break_even_sweep.csv`
- 판정: **PARTIAL PASS — latency/traffic 모델 완료, energy/area와 실측 GPU 보정은 미완료**

## 1. 구현 결과

7개 GR00T normalization profile을 다음 다섯 case로 계산하는 재현 가능한 Python 모델을 구현했다.

1. GPU full-tensor offload
2. GPU partial-statistic offload
3. Bank-only PIM + GPU/host fallback
4. Logic-only PIM
5. Hierarchical Bank-PCU + Logic-PCU PIM

모델은 다음 값을 profile별, invocation별로 출력한다.

- total latency와 equivalent cycle
- local reduction
- partial transfer
- global reduction
- finalize
- RSQRT
- scalar return/broadcast
- element-wise apply
- queue/synchronization
- tensor/partial/return traffic
- evidence class와 assumptions ID

energy와 area는 아직 근거가 없으므로 CSV에서 빈 값(null)으로 유지했다.

## 2. 검증

내장 self-test 결과:

```text
GROOT_NORMALIZATION_MODEL_SELF_TEST PASS
WROTE reference_rows=35 sweep_rows=252
```

self-test가 확인하는 항목:

- manifest profile 7개 및 호출 333회
- `[280,2048]`와 `[8960,64]`의 동일 element/byte 수
- Q/K RMSNorm의 더 큰 RSQRT scheduling cost
- offload latency 증가 시 GPU latency 증가
- offload parameter가 on-die Hierarchical 결과에 영향을 주지 않음
- 모든 reference latency가 양수
- 근거 없는 energy/area가 0으로 채워지지 않음

## 3. Reference point

다음은 실측 시스템 사양이 아니라 sensitivity를 위한 기준 가정이다.

| Parameter | Reference | Evidence |
|---|---:|---|
| clock | 100 MHz | 기존 10 ns constraint에서 가져왔으나 timing 미수렴 |
| banks | 16 | architecture reference |
| Bank-PCUs | 8 | architecture reference |
| Logic-PCUs | 16 | architecture reference |
| vector lanes/PCU | 16 | 현재 256-bit FP16 datapath |
| offload one-way latency | 2,500 ns | assumed |
| offload bandwidth | 64 Gbps | assumed |
| on-die one-way latency | 50 ns | assumed |
| on-die bandwidth | 1,024 Gbps | assumed |
| GPU launch | 5,000 ns | assumed |
| GPU HBM bandwidth | 1,000 GB/s | assumed roofline |
| GPU normalization throughput | 32 rows/ns | assumed proxy |
| Logic RSQRT | latency 16 cycle, II 1 | assumed |

따라서 아래 수치는 architecture 선택의 최종 측정 결과가 아니라 RTL 구현 우선순위를 정하기 위한 모델 결과다.

## 4. Reference 결과

333회 호출의 projected 합계:

| Case | Projected latency | 현재 evidence |
|---|---:|---|
| Logic-only | 14.158 ms | Logic throughput proxy |
| Hierarchical | 22.457 ms | measured element-wise + assumed Logic/interconnect |
| Bank-only + fallback | 26.903 ms | measured element-wise + assumed offload/GPU |
| GPU partial | 26.903 ms | Bank-only와 같은 경계로 모델링 |
| GPU full tensor | 36.773 ms | assumed GPU roofline/offload |

Reference parameter에서는 7개 profile 모두 Logic-only가 가장 짧게 계산됐다. 그러나 이 결과는 Logic-PCU vector apply throughput을 Bank-PIM 측정 cycle에서 PCU 수 비율로 환산한 proxy에 크게 의존한다. 현재 RTL의 Logic-only normalization engine이나 해당 throughput 실측이 없으므로 “Logic-only가 최종 승자”라는 근거로 사용할 수 없다.

반대로 Hierarchical 결과는 기존 Bank-PIM element-wise cycle을 그대로 유지하므로 더 보수적이다.

## 5. Traffic 결과

모델 1회 projected 기준:

| Case | tensor-domain traffic | bank partial traffic | scalar return traffic |
|---|---:|---:|---:|
| GPU full tensor | 265.417 MB | 0 | 0 |
| Logic-only | 265.417 MB | 0 | 0 |
| Bank-only/GPU partial | 0 | 20.611 MB | 1.288 MB |
| Hierarchical | 0 | 20.611 MB | 1.288 MB |

여기서 20.611 MB는 `rows × statistic_count × 16 banks × FP32 scalar`로 계산한 payload다. 실제 mapping에서 모든 row가 16개 bank에 분산되지 않으면 감소할 수 있다. protocol/burst overhead는 아직 포함하지 않았다.

## 6. Latency 지배 항목

Reference 합계에서 관찰된 주요 병목:

- GPU full tensor: outbound tensor transfer 19.451 ms, return 15.391 ms
- Bank-only/GPU partial: Bank element-wise apply 20.404 ms, partial transfer 3.409 ms, launch/sync 1.665 ms
- Hierarchical: Bank element-wise apply 20.404 ms, global reduction 약 0.806 ms
- Logic-only: apply proxy 약 10.202 ms, on-die input/parameter transfer 약 1.180 ms

현재 가정에서는 RSQRT 하나만 빠르게 만드는 것보다 Bank element-wise pass 수와 throughput 개선이 전체 latency에 더 큰 영향을 준다. 다만 `[8960,64]`에서는 row 수가 많아 RSQRT II와 finalize scheduling의 영향이 다른 profile보다 크다.

## 7. Offload sweep

다음 252개 조합을 계산했다.

```text
7 profiles
× 6 offload one-way latency points (250 ns ~ 10 us)
× 6 bandwidth points (16 ~ 512 Gbps)
```

Hierarchical, Bank-only, GPU full tensor 중 winner 분포:

| Winner | 조합 수 |
|---|---:|
| Hierarchical | 129 |
| GPU full tensor | 123 |
| Bank-only | 0 |

Bank-only가 이 sweep에서 승리하지 않은 이유는 Hierarchical과 같은 Bank element-wise cost를 가지면서 off-die 왕복 및 launch 비용이 추가되기 때문이다. 이는 구조 정의에 따른 결과이며 실제 GPU 측정으로 반드시 보정해야 한다.

profile별 36개 offload 조합 중 Hierarchical 승리 수:

| Profile | Hierarchical wins |
|---|---:|
| VLLN `[280,2048]` | 18/36 |
| VL-SA `[280,2048]` | 18/36 |
| DiT AdaLN `[41,1536]` | 19/36 |
| DiT norm3 `[41,1536]` | 13/36 |
| DiT norm_out `[41,1536]` | 13/36 |
| Qwen input/post RMS `[280,2048]` | 24/36 |
| Qwen Q/K RMS `[8960,64]` | 24/36 |

현재 sweep에서는 offload latency보다 bandwidth와 tensor/partial payload 차이가 더 강한 변수다. 정확한 경계는 `offload_break_even_sweep.csv`의 profile/latency/bandwidth별 winner와 speedup에서 확인할 수 있다.

## 8. 해석

현재 모델이 지지하는 임시 결론은 다음과 같다.

1. RSQRT만 host/GPU로 보내는 비용은 scalar 계산보다 queue/왕복에 더 민감하다.
2. Hierarchical PIM은 full tensor 이동을 partial statistics와 row scalar 이동으로 줄이는 데 의미가 있다.
3. 그러나 기존 Bank-PIM element-wise cycle이 전체 latency 대부분을 차지하므로 RSQRT RTL만 추가해서 큰 E2E speedup을 주장하면 안 된다.
4. Logic-only의 잠재 성능은 높지만 현재 수치는 미구현 Logic vector normalization throughput proxy이므로 검증되지 않았다.
5. RSQRT unit의 latency보다 II가 `[8960,64]` workload에서 더 중요할 수 있다.

## 9. 남은 작업

Phase 3 전체 완료에는 다음이 필요하다.

- RTL 또는 microbenchmark로 local/global reduction cycle 보정
- RSQRT 후보별 latency/II 반영
- 실제 GPU 또는 공인 측정 기반 kernel/transfer parameter 보정
- protocol/burst/padding traffic 반영
- energy parameter와 결과
- RSQRT 및 normalization engine 합성 후 area 반영

따라서 Phase 3은 latency/traffic 및 break-even framework까지 `PARTIAL PASS`이며, Phase 4/5 측정값을 다시 받아 최종 보정해야 한다.

## 10. 재현 명령

```powershell
python .\tools\groot_normalization_model.py --self-test
python .\tools\groot_normalization_model.py
```

## 11. 현재 의사결정

Logic-PCU RSQRT RTL 구현 가능성은 충분하지만, 범용 exact unit을 바로 구현하기보다 Phase 4에서 LUT/NR1/NR2 정확도와 latency 후보를 비교한 후 하나를 선택한다. 또한 최종 구조는 RSQRT unit만이 아니라 row finalize 및 broadcast를 포함한 normalization scalar engine으로 설계해야 한다.
