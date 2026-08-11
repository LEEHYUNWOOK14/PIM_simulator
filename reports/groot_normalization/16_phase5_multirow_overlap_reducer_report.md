# Phase 5 multi-row overlap Bank reducer 보고서

## 판정

**PASS** — 4-lane pipelined SUM/SUMSQ reducer가 연속 row를 겹쳐 처리하도록 확장됐다. 이전 row의 마지막 vector와 다음 row begin을 같은 cycle에 수락하고, result FIFO credit으로 output backpressure를 제한한다.

현재 GRoot `[8960,64]`, 16-bank mapping에서는 bank당 row element가 4개이므로 한 row가 정확히 4-lane vector 하나다. 신규 RTL은 이 조건에서 bubble 없이 row II=1을 달성했다.

## 구조

입력 pipeline payload:

- FP16 vector
- row tag
- first/last flag
- valid

출력 구조:

- balanced/pipelined SUM tree
- balanced/pipelined SUMSQ tree
- row-boundary aware accumulator
- ordered result FIFO
- outstanding-row credit counter

`outstanding < FIFO_DEPTH`인 경우에만 새 row를 받는다. 따라서 output이 무기한 stall되어도 FIFO보다 많은 row 결과를 생성하지 않는다.

## 기능 검증

4-lane, 1-vector/row 조건에서 두 FIFO 구성을 검증했다.

| FIFO depth | 연속 row | row input II | result stall | tag/order/SUM/SUMSQ |
|---:|---:|---:|---:|---|
| 4 | 4 | 1 | 3 cycles | PASS |
| 8 | 8 | 1 | 3 cycles | PASS |

depth 8에서는 첫 결과가 마지막 row vector보다 먼저 발생했다. 이는 tree pipeline fill과 후속 row 입력이 실제로 겹쳤다는 관측이다.

입력은 row별로 1.0 또는 2.0을 반복했으며 기대 결과는 다음과 같다.

- 1.0 × 4: SUM=4.0, SUMSQ=4.0
- 2.0 × 4: SUM=8.0, SUMSQ=16.0

모든 결과가 tag 순서와 FP16 bit pattern까지 일치했다.

## 합성

조건: LANES=4, Yosys generic synthesis.

| Result FIFO depth | cells/bank | 기존 single-row pipeline 대비 증가 | generic path | strict check |
|---:|---:|---:|---:|---|
| 4 | 43,008 | 1.29% | 333 | 문제 0 |
| 8 | 43,634 | 2.76% | 333 | 문제 0 |
| 16 | 44,834 | 5.59% | 333 | 문제 0 |

최소 depth 4가 tree latency와 backpressure credit에 충분하며 면적 증가가 가장 작으므로 현재 선택값이다.

## row-aware 성능 반영

single-row pipeline은 매 row마다 `log2(lanes)` drain cycle을 부담했다.

```text
single-context cycles = rows × (vectors_per_row + tree_levels)
multi-row cycles      = rows × vectors_per_row + tree_levels
```

16 banks, 4 lanes/bank, 100 MHz, 전체 333 calls:

| 구조 | projected Hierarchical latency |
|---|---:|
| non-pipelined 4-lane | 33.789 ms |
| single-row pipelined 4-lane | 39.967 ms |
| multi-row pipelined 4-lane | 33.796 ms |
| assumed GPU full | 36.773 ms |

multi-row 구조는 pipeline timing boundary를 유지하면서 non-pipeline 처리량에 거의 복귀한다. 실제 Logic engine의 bank-partial 직렬 수신과 16-engine 복제를 반영한 analytical model에서 assumed GPU full보다 1.088배 빠르다. GPU 값이 실측이 아니므로 실제 GPU speedup 주장은 할 수 없다.

## 아키텍처 의미

- 작은 hidden/많은 row workload의 핵심은 lane 수보다 row overlap이다.
- 4→8 lanes 확장보다 4-lane multi-row scheduling이 훨씬 면적 효율적이다.
- 16-bank 복제 시 raw reducer proxy는 688,128 generic cells다.
- 16개 Logic normalization engine array 440,400 cells를 더한 Hierarchical lower-bound proxy는 1,128,528 cells다.
- 기존 Bank-PCU apply datapath를 재사용하므로 dedicated apply engine 복제는 제외한다.

## 남은 한계

- module은 아직 `full_pim_system_top` 내부 raw activation 경로에 연결되지 않았다.
- FIFO는 register array로 합성됐으며 SRAM macro mapping이 아니다.
- technology-mapped timing/power가 없다.
- 실제 GR00T activation에서 balanced-tree FP16 rounding 정확도를 재검증하지 않았다.
- model은 각 invocation 사이에는 pipeline을 drain한다고 본다.
- downstream Logic reducer 및 scalar engine은 single-row context이므로 전체 row II=1은 아직 아니다.

## 재현

```bash
bash verification/groot_normalization/run_bank_normalization_multirow_vector_reducer_test.sh
bash verification/groot_normalization/run_bank_normalization_multirow_vector_reducer_synthesis.sh
python tools/analyze_bank_reducer_tradeoff.py
```

산출물:

- `rtl/bank_normalization_multirow_vector_reducer.sv`
- `results/bank_multirow_vector_reducer_l4_d{4,8,16}_yosys.log`
- `results/bank_vector_reducer_tradeoff.csv`
