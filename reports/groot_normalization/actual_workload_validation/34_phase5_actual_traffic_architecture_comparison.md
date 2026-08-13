# Phase 5 — 실제 Action-head Traffic 기반 Architecture 비교

## 결론과 decision gate

Architecture decision은 **`NO-GO`**다. 따라서 현재 단계에서 production activation replay/DRAM write-back RTL을 확장하지 않는다.

필수 근거는 두 가지다.

1. 현재 hierarchical BF16 RTL이 사전 정확도 기준을 6개 profile 중 1개에서만 통과했다.
2. RTX 4060 BF16 LayerNorm 실측 투영값은 3.121 ms인 반면, 현재 timing 근거에 맞춘 40 MHz hierarchical 모델은 replay와 write-back을 포함해 21.225 ms다. GPU 대비 speedup은 0.147×, 즉 약 6.8배 느리다.

단순 latency break-even은 약 **275.0 MHz**다. 이는 현재 Sky130 RTL의 40 MHz modeled safe target 및 기존 4-lane BF16 reducer 약 46.6 MHz 역수 근거보다 훨씬 높고, 통합 top에서 timing-close된 값도 아니다. 정확도 gate 실패는 주파수와 무관하게 남는다.

## 비교 범위와 증거 등급

이 비교는 full GR00T inference가 아니라 Phase 2에서 실제 pretrained action head를 실행해 캡처한 269개 normalization 호출에 한정된다.

- 모델/checkpoint: `nvidia/GR00T-N1.7-3B`, revision `2fc962b973bccdd5d8ce4f67cc63b264d6886495`
- 입력 분류: `PRETRAINED_ACTION_HEAD_SYNTHETIC_BOUNDARY_INPUT`
- dtype: BF16
- 호출: LayerNorm 계열 269회, 13,180 rows
- shape: `[1,280,2048]`, `[1,41,1536]`
- BF16 activation input: 43,069,440 B
- GPU latency: **CUDA event 측정**, 대표 profile median × 캡처 호출 수의 serial projection
- PIM latency: **RTL stage count + 명시적 parameter 모델**, silicon 또는 full-system 측정 아님
- traffic: exact shape/mapping에서 도출한 **logical payload**, HBM command trace 측정 아님
- energy: representative VCD/SAIF와 calibrated power model 부재로 산출하지 않음

## GPU BF16 측정

측정 환경:

- GPU: NVIDIA GeForce RTX 4060
- PyTorch: `2.9.0+cu128`
- CUDA runtime: 12.8
- 연산: `torch.nn.functional.layer_norm`
- warmup 100회, repeat당 1,000회, 7 repeats, CUDA event timing
- 실제 module의 `elementwise_affine` 여부를 유지

| profile | shape | calls | median/call | projected serial |
|---|---|---:|---:|---:|
| vlln | 1×280×2048 | 1 | 9.828 us | 9.828 us |
| VL norm1 | 1×280×2048 | 4 | 10.103 us | 40.411 us |
| VL norm3 | 1×280×2048 | 4 | 10.504 us | 42.017 us |
| AdaLN inner LN | 1×41×1536 | 128 | 9.184 us | 1,175.531 us |
| DiT norm3 | 1×41×1536 | 128 | 14.023 us | 1,794.929 us |
| norm_out | 1×41×1536 | 4 | 14.623 us | 58.491 us |

총 투영값은 3,121.208 us다. 동일 shape에서도 WSL/display GPU 환경의 repeat 변동이 관측되므로 raw 7-repeat 값과 min/median/max를 JSON/CSV에 모두 보존했다. 이는 normalization microbenchmark이며 action model E2E latency가 아니다.

## 공통 reference point

| parameter | 값 | 분류 |
|---|---:|---|
| banks / reducer lanes | 16 / 4 | RTL configuration |
| bank PCU vector | 16 BF16 elements | RTL interface |
| scalar engines | 8 | RTL-synthesized candidate |
| clock | 40 MHz | modeled safe target, 통합 timing 미검증 |
| reducer pipeline | 3 cycles | RTL measured |
| scalar pipeline | 5 cycles | RTL measured |
| LayerNorm commands | 4 / bank vector | RTL measured |
| replay / write-back | 각각 1 cycle / bank vector | explicit assumption |
| mode/sync | 8 cycles / call | explicit assumption |
| on-die link | 50 ns one-way, 128 GB/s | assumption |
| offload link | 2.5 us one-way, 8 GB/s | assumption |

전체 parameter는 `actual_groot_architecture_parameters.json`에 저장했고 `common_model_parameters.json`의 local GPU 및 actual validation block도 갱신했다.

## Traffic 분해

전체 workload의 logical traffic은 다음과 같다.

| architecture | memory-array bytes | cross-domain bytes | 합계 | GPU 대비 |
|---|---:|---:|---:|---:|
| GPU | 86,212,608 | 0 | 86,212,608 | 1.000× |
| Bank-only PIM | 129,282,048 | 1,687,040 | 130,969,088 | 1.519× |
| Logic-only PIM | 86,212,608 | 86,212,608 | 172,425,216 | 2.000× |
| Hierarchical PIM | 129,282,048 | 1,687,040 | 130,969,088 | 1.519× |

Hierarchical/Bank-only의 array traffic이 GPU보다 큰 이유는 reduction read 43,069,440 B, apply replay 43,069,440 B, final write-back 43,069,440 B가 모두 포함되기 때문이다. 추가로 affine 73,728 B가 있다. Hierarchical cross-domain payload는 16 bank × 13,180 rows에 대한 SUM/SUMSQ 843,520 B와 mean/inv_std return 843,520 B다.

정확 mapping에서 reduction packet은 5,383,680개(각 8 B), modeled 256-bit replay/write packet은 각각 1,345,920개다. 부분 통계와 scalar return은 각각 210,880 transactions다. architecture/component별 byte와 transaction은 `architecture_traffic_breakdown.csv`에 있다.

## Latency 비교

| architecture | latency | GPU 대비 speedup | 근거 | 정확도/구현 상태 |
|---|---:|---:|---|---|
| GPU | 3,121.208 us | 1.000× | CUDA event measured + call projection | PyTorch golden |
| Bank-only PIM | 24,085.355 us | 0.130× | RTL cycle model + assumed external offload | 정확도 미검증, partial |
| Logic-only PIM | 11,349.736 us | 0.275× | vector throughput + on-die link model | 정확도 미검증, model only |
| Hierarchical PIM | 21,224.555 us | 0.147× | RTL stages + explicit replay/writeback | 정확도 FAIL, production replay 미구현 |

Bank-only는 global reduction/RSQRT 외부 offload 왕복을 profile call마다 batch한다고 가정했다. Logic-only는 원본 activation과 결과 전체가 bank↔logic 경계를 지난다. Hierarchical는 원본 activation을 bank 쪽에 유지하지만 현재 low clock과 두 번째 activation read/apply/write path가 latency를 지배한다.

## Sensitivity와 break-even

### Clock

| clock | hierarchical latency | GPU 대비 |
|---:|---:|---:|
| 40 MHz | 21.225 ms | 0.147× |
| 50 MHz | 16.988 ms | 0.184× |
| 100 MHz | 8.514 ms | 0.367× |
| 250 MHz | 3.430 ms | 0.910× |
| 500 MHz | 1.735 ms | 1.799× |

모델상 break-even 275.0 MHz 이후에만 latency 우위가 생긴다. 100 MHz 이상 행은 모두 `UNVERIFIED_FREQUENCY`이며 현재 물리 근거로 달성됐다고 주장할 수 없다.

### 구조 및 비용

- bank 4→8→16→32에서 40 MHz latency는 84.305→42.248→21.225→10.723 ms다. 32-bank도 GPU보다 느리다.
- replay/write-back을 비현실적으로 0 cycle로 제거해도 17.019 ms로 GPU보다 느리다. 각각 2/4/8 cycles이면 25.431/33.843/50.667 ms다.
- scalar engine 1→16 증가는 21.507→21.201 ms에 그친다. scalar가 병목이 아니다.
- bank skew 0→20%는 21.225→22.911 ms로 악화한다.
- on-die bandwidth 16~512 GB/s와 one-way latency 10~500 ns sweep은 전체 결론을 바꾸지 않는다. payload가 작아 compute/replay가 지배한다.
- 실제 affine module schedule에서는 각 affine module이 한 번씩 호출되어 gamma/beta 재사용 이득이 없다. profile identity를 무시한 이상적 once-per-profile cache도 49,152 B만 줄이며 latency 결론을 바꾸지 않는다.
- hidden/row 영향은 `per_profile_architecture_comparison.csv`에 두 actual shape별로 분리했다. 두 shape 모두 40 MHz에서 GPU를 이기지 못한다.

## Architecture gate 평가

| 질문 | 결과 |
|---|---|
| 실제 확보 workload에서 hierarchical가 GPU보다 유리한가? | NO, modeled 0.147× |
| replay/write-back 포함 후 이득이 유지되는가? | 이득 자체가 없음 |
| 정확도 기준을 만족하는가? | NO, 1/6 profile PASS |
| 특정 shape에서만 유리한가? | 두 actual shape 모두 불리함 |
| area/energy 증가 근거가 있는가? | NO, comparable energy 없음; generic-cell 결과만 존재 |

최종 판정: **`NO-GO`**.

다음 조건을 모두 만족하면 재검토할 수 있다.

1. accumulation/scalar/apply precision을 개선하고 6/6 정확도 gate 통과
2. 통합 datapath를 모델 break-even 이상의 주파수에서 timing closure
3. production replay/write-back RTL의 실측 cycle 및 activity 기반 energy 확보
4. gated backbone 접근과 16 GB 이상 GPU가 가능해질 경우 full GR00T inference trace 확보

## 재현 및 산출물

```bash
/home/chandler/.cache/stob-groot-runtime/bin/python tools/benchmark_groot_normalization_gpu.py
python3 tools/compare_actual_groot_architectures.py
```

- `reports/groot_normalization/results/actual_groot/gpu_benchmark/gpu_layernorm_latency.csv/json`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/actual_workload_traffic.csv`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/architecture_traffic_breakdown.csv`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/per_profile_architecture_comparison.csv`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/architecture_comparison.csv/json`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/sensitivity.csv`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/decision_gate.json`
- `reports/groot_normalization/results/actual_groot/architecture_comparison/actual_groot_architecture_parameters.json`
