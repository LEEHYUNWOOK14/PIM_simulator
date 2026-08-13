# Phase 6 RTL 측정값 연동 system simulation 보고서

## 판정

**PARTIAL PASS** — RTL에서 측정한 RSQRT와 scalar engine latency, generic synthesis cell 수를 공통 parameter 및 discrete-event simulator에 연결했다. 네 기본 구조의 동일 333-call trace에서 latency, queue, traffic, utilization 및 area proxy를 출력한다. 그러나 raw SUM/SUMSQ producer, 실제 GPU, 전력/energy 및 technology-mapped PPA가 없으므로 Phase 6 전체 완료는 아니다.

## RTL calibration

| 입력값 | 반영값 | 단위 | 증거 분류 |
|---|---:|---|---|
| LUT256 RSQRT latency | 1 | cycle | RTL_MEASURED |
| LUT256 RSQRT II | 1 | cycle | RTL_MEASURED |
| scalar finalize+RSQRT | 5 | cycle/row | RTL_MEASURED |
| Logic normalization shared dispatcher | 445,337 | 16-engine, 1-port Yosys generic cells | RTL_MEASURED_GENERIC_SYNTHESIS |
| Bank local scalar reducer | 1 | element/cycle/bank | RTL_MEASURED_FROM_INTERFACE |
| Bank local scalar reducer | 15,307 | Yosys generic cells/bank | RTL_MEASURED_GENERIC_SYNTHESIS |
| affine RMSNorm apply | 2 | Bank-PCU arithmetic commands/vector | RTL_MEASURED |
| affine LayerNorm apply | 4 | Bank-PCU arithmetic commands/vector | RTL_MEASURED |

공통 parameter의 기존 RSQRT 16-cycle 가정을 1-cycle 측정값으로 교체했다. scalar engine 전체 5-cycle에서 RSQRT 1-cycle을 분리해 finalize proxy를 4-cycle/row로 두었다. 또한 기존의 `bank_pcus × 16 lanes` local reduction 처리량 가정을 제거하고, 현재 RTL이 증명하는 bank당 1 element/cycle을 반영했다. SUM과 SUMSQ는 같은 cycle에 함께 생성된다.

## Simulator 구조

`groot_normalization_system_sim.py`는 manifest의 7개 profile, 총 333 invocation을 실제 event로 재생한다. 네 case는 동일한 profile 순서와 arrival rate를 사용한다.

- GPU full: launch → full tensor offload → GPU normalize → tensor return
- Bank-only: local reduction → partial offload → GPU scalar → scalar return → Bank apply
- Logic-only: tensor on-die 이동 → Logic normalize/apply → tensor return
- Hierarchical: Bank local reduction → partial 이동 → Logic scalar → broadcast → Bank apply

resource별 finite capacity와 availability를 추적해 queue delay와 utilization을 계산한다. arrival rate와 resource capacity는 실측이 아닌 `common_model_parameters.json`의 명시적 가정이다.

## Base scenario 결과

조건: 8 channels, channel당 2,500 requests/s, 100 MHz, FP16 simulator workload. latency는 333개 event의 simulator 측정 결과다.

| 구조 | 평균 latency | p95 latency | 평균 queue | 주요 utilization | incremental area proxy |
|---|---:|---:|---:|---|---:|
| GPU full | 4,925.6 us | 14,608.0 us | 4,815.2 us | offload link 99.23% | 미측정 |
| Bank-only | 487.1 us | 2,770.2 us | 298.2 us | Bank 34.96% | 244,912 cells |
| Logic-only | 416.9 us | 2,404.6 us | 367.7 us | on-die link | 445,337 cells 하한 |
| Hierarchical | 2,668.3 us | 24,679.3 us | 2,345.8 us | shared partial input | 690,249 cells |

base 가정에서는 Logic-only가 가장 낮고 Bank-only가 뒤따른다. Hierarchical은 shared partial input 1-port가 queue와 service를 지배해 2.67 ms까지 증가한다. GPU full은 offload link가 99% 이상 사용되어 queue가 지배한다.

## Arrival-rate sensitivity

평균 latency 기준 우승 구조:

| scenario | channel request rate | winner | winner mean latency |
|---|---:|---|---:|
| low | 500 requests/s | Logic-only | 49.2 us |
| base | 2,500 requests/s | Logic-only | 416.9 us |
| high | 10,000 requests/s | Bank-only | 2,203.0 us |

낮은 부하에서는 Logic-only의 짧은 단일 요청 service time이 유리하지만, 부하가 증가하면 full-tensor on-die 이동 queue 때문에 hierarchical이 역전한다. 이는 “Logic-PCU가 항상 최선”이 아니라 traffic과 동시성 조건에 따라 배치가 달라진다는 증거다.

## 업데이트된 analytical projection

RTL calibration 후 333회 projected 합계:

| 구조 | projected normalization latency | 분류 |
|---|---:|---|
| Logic-only | 16.397 ms | mixed measured/assumed analytical lower bound |
| Hierarchical | 107.395 ms | mixed measured/assumed analytical |
| Bank-only/GPU partial | 62.909 ms | mixed measured/assumed analytical |
| GPU full | 36.773 ms | assumed GPU roofline |

offload sweep 252점에서는 GPU full 186점, Bank-only 42점, Hierarchical 24점이 우승했다. 현재 shared partial port에서는 Hierarchical의 이점이 크게 줄어든다. system simulation과 analytical 합계의 순위가 다른 것은 queue/resource concurrency가 system simulation에만 들어가기 때문이다.

## 제한 사항

- GPU latency, bandwidth 효율 및 kernel launch는 가정이며 GPU 실측이 아니다.
- 실제 GR00T activation 대신 deterministic synthetic FP16 profile을 사용한다. 공식 dtype BF16과 다르다.
- Bank-only/Hierarchical area proxy는 15,307-cell scalar reducer를 16 bank에 선형 복제하고, Hierarchical/Logic-only에는 16-engine shared dispatcher 445,337 cells를 반영한다. Logic-only에는 raw tensor reducer와 apply datapath가 없어 여전히 하한이다.
- generic cell 수는 technology-mapped area가 아니며 서로 다른 top의 단순 합이다.
- power/energy는 근거가 없어 null을 유지한다.
- trace는 profile별 invocation을 묶은 고정 순서이며 실제 GR00T runtime timestamp가 아니다.
- Bank/Logic/link resource capacity와 arrival rate는 sensitivity 가정이다.

따라서 위 수치는 아키텍처 조건 비교 및 병목 탐색에는 사용할 수 있지만 실제 제품 latency, GPU speedup 또는 에너지 절감을 주장하는 근거로 사용할 수 없다.

## 재현

```bash
python tools/groot_normalization_model.py --self-test
python tools/groot_normalization_model.py
python tools/groot_normalization_system_sim.py --self-test
```

산출물:

- `results/system_simulation_summary.csv`
- `results/system_simulation_trace.csv`
- `results/reference_architecture_comparison.csv`
- `results/offload_break_even_sweep.csv`
- `common_model_parameters.json`

## 다음 게이트

1. 4-lane multi-row Bank reducer와 Logic engine array의 dispatcher/top 통합
2. Bank/Logic broadcast와 FIFO depth를 simulator resource로 calibration
3. 가능한 GPU 환경에서 동일 shape FP16/BF16 profiler 실행
4. technology mapping 또는 명시적 cell-library 기반 area/timing
5. VCD/SAIF 또는 측정된 event energy 확보 전까지 energy 결과는 null 유지
