# Phase 5 Logic normalization engine 복제 비용 보고서

## 판정

**PASS WITH ARCHITECTURE LIMIT** — 4개 Logic normalization engine이 서로 다른 row를 완전 병렬 처리하는 RTL 테스트를 통과했고, 1/2/4/8/16-engine array가 모두 strict synthesis 문제 0건으로 합성됐다.

그러나 현재 `full_pim_system_top`에는 normalization engine이 한 개뿐이며, array wrapper에는 row dispatcher와 shared partial interconnect가 없다. 16-engine 결과는 복제 가능한 계산 블록의 면적/처리량 상한이지 production top 통합 완료 증거가 아니다.

## 병렬 기능 검증

4 engines에 서로 다른 tag를 가진 RMSNorm transaction을 동시에 시작하고, 각 engine에 2-bank partial을 병렬 공급했다.

검증 항목:

- 4개 begin 동시 수락
- engine별 독립 bank mask와 tag
- partial SUM/SUMSQ 병렬 수신
- LUT RSQRT 결과 `0x3bfa` bit-exact
- engine 0만 response stall하고 나머지 3개 독립 완료
- stalled response payload 유지
- duplicate/context error 미발생

```text
LOGIC_NORMALIZATION_ENGINE_ARRAY_TB PASS engines=4 parallel_responses=4 cycles=14
```

## 합성 결과

조건: BANKS=16, Yosys generic synthesis.

| Logic engines | generic cells | engine당 cells | strict check |
|---:|---:|---:|---|
| 1 | 27,525 | 27,525 | 문제 0 |
| 2 | 55,050 | 27,525 | 문제 0 |
| 4 | 110,100 | 27,525 | 문제 0 |
| 8 | 220,200 | 27,525 | 문제 0 |
| 16 | 440,400 | 27,525 | 문제 0 |

면적은 정확히 선형 증가한다. 16-engine 병렬성을 simulator에서 가정할 경우 Logic area도 반드시 440,400 cells로 계산해야 하며, 단일 engine 27,525 또는 과거 다른 synthesis context의 39,064 cells만 사용하면 안 된다.

## RTL 처리율 보정

현재 engine은 reduction tree가 아니라 한 cycle에 bank partial pair 하나를 순차 수신한다.

```text
per-row engine service ≈ active_banks + scalar_finalize_rsqrt
                       = 16 + 5
                       = 21 cycles
```

따라서 E개 engine의 steady-state proxy는 `E/21 rows/cycle`이다. 모델의 기존 `statistic_count × log2(banks)` 식을 제거하고 이 RTL 구조를 반영했다. SUM과 SUMSQ는 paired partial이므로 같은 cycle에 처리된다.

## GR00T engine-count sweep

4-lane multi-row Bank reducer, 16 banks, 100 MHz, 333 calls 기준이다.

| Logic engines | Logic cells | Hierarchical cells proxy | Hierarchical latency | Logic-only latency | GPU full assumed |
|---:|---:|---:|---:|---:|---:|
| 1 | 27,525 | 715,653 | 94.575 ms | 280.054 ms | 36.773 ms |
| 2 | 55,050 | 743,178 | 62.172 ms | 141.108 ms | 36.773 ms |
| 4 | 110,100 | 798,228 | 45.970 ms | 71.635 ms | 36.773 ms |
| 8 | 220,200 | 908,328 | 37.869 ms | 36.898 ms | 36.773 ms |
| 16 | 440,400 | 1,128,528 | 33.796 ms | 19.507 ms | 36.773 ms |

현재 가정에서 Hierarchical이 GPU full보다 빨라지는 첫 측정 구성은 16 engines다. 8-engine은 GPU full보다 약 1.097 ms 느리다. 즉 Logic-PCU RSQRT 하나를 추가하는 수준이 아니라, row 병렬성을 위해 normalization engine을 대량 복제해야 우위가 생긴다.

## 해석

- RSQRT 자체는 latency 1, II 1이며 지배 병목이 아니다.
- 병목은 16-bank partial의 순차 수신과 single-context scalar FSM이다.
- engine 복제는 처리량을 선형 개선하지만 generic area도 정확히 선형 증가한다.
- 16-engine Hierarchical proxy 1.129M cells는 배선, dispatcher, FIFO, Bank-PCU 기존 면적 및 physical overhead를 제외한 하한이다.
- Logic-only 19.507 ms는 빠르지만 raw tensor reduction/apply 및 전체 tensor 이동 하드웨어 면적이 빠져 있으므로 면적 대비 우승으로 확정할 수 없다.

## 권고

단순 16-engine 복제를 production 구조로 확정하지 않는다. 우선순위는 다음과 같다.

1. 여러 bank partial을 cycle당 병렬 수신하는 reduction tree/fabric
2. scalar engine의 5-stage pipeline화 또는 context interleave
3. 4/8-engine + shared frontend로 16-engine과 동일 row throughput을 달성 가능한지 비교
4. dispatcher/FIFO/interconnect를 포함한 top-level 합성
5. technology-mapped area/timing/power 후 8 대 16 engine 결정

## 재현

```bash
bash verification/groot_normalization/run_logic_normalization_engine_array_test.sh
bash verification/groot_normalization/run_logic_normalization_engine_array_synthesis.sh
python tools/analyze_logic_engine_replication.py
```

산출물:

- `rtl/logic_normalization_engine_array.sv`
- `results/logic_normalization_engine_array_e{1,2,4,8,16}_yosys.log`
- `results/logic_engine_replication_tradeoff.csv`
