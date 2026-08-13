# Phase 5 parallel bank-partial reduction tree 보고서

## 판정

**PASS, SELECTED LOGIC CANDIDATE** — 16개 bank의 SUM/SUMSQ partial을 row 단위로 동시에 받아 balanced pipeline tree에서 global statistic으로 합치고, 8개 scalar engine에 interleave하는 구조를 구현했다.

이 구조는 shared 1-port dispatcher의 80.104 ms 병목을 제거하면서, 16개의 완전한 reduction engine을 복제하는 방식보다 면적이 작다. 현재 Logic-side 우선 후보는 **16-bank parallel tree + 8 scalar engines**다.

## 데이터 경로

```text
16 bank partial SUM/SUMSQ pairs
→ 4-level balanced FP16 reduction tree
→ one global SUM/SUMSQ row per cycle
→ round-robin scalar-engine allocation
→ mean/variance/epsilon/LUT-RSQRT
→ response arbitration
```

tree와 함께 다음 context가 pipeline된다.

- row valid
- LayerNorm/RMSNorm mode
- row tag
- inv-hidden
- epsilon

outstanding credit은 tree 내부 row와 scalar engine에 할당된 row의 합이 engine 수를 넘지 않게 제한한다. output stall 시 신규 row 입력을 막아 pipeline overflow를 방지한다.

## 기능 검증

축소 BANKS=4, scalar engines=8 구성에서 8개 row를 연속 입력했다.

- row input II=1
- 4-bank SUM/SUMSQ 동시 입력
- 8개 tag 보존
- RMSNorm scalar bit-exact (`0x3bfa`)
- result stall 3 cycles
- response 중복/누락 없음
- allocation error 없음

```text
LOGIC_NORMALIZATION_PARALLEL_TREE_TOP_TB PASS rows=8 row_II=1 engines=8 cycles=19
```

## 합성 결과

조건: BANKS=16, Yosys generic synthesis.

| Scalar engines | Logic tree top cells | generic path | strict check |
|---:|---:|---:|---|
| 8 | 264,552 | 340 | 문제 0 |
| 16 | 431,390 | 340 | 문제 0 |

8 engines와 16 engines의 row throughput은 모두 II=1이다. scalar engine latency가 약 5 cycles이므로 8 engines만으로 tree의 one-row/cycle 출력을 숨길 수 있다. 16 engines는 166,838 cells를 더 사용하지만 projected throughput이 증가하지 않는다.

비교:

| Logic 구조 | cells | partial 처리율 | 비고 |
|---|---:|---:|---|
| 16-engine shared dispatcher | 445,337 | 1 pair/cycle | 현재 병목 구조 |
| 16 independent reduction engines | 440,400 | 최대 16 pairs/cycle | engine별 16-cycle row collection |
| parallel tree + 8 scalar engines | 264,552 | 16 pairs/cycle, 1 row/cycle | 선택 후보 |
| parallel tree + 16 scalar engines | 431,390 | 16 pairs/cycle, 1 row/cycle | over-provisioned |

## GR00T projected 결과

Bank 측은 4-lane multi-row reducer 16개를 사용한다. 각 invocation에서 Bank local reduction과 Logic tree/scalar service는 보수적으로 합산했으며 서로 겹치지 않는다고 모델링했다.

| Scalar engines | Bank reducer cells | Logic cells | Hierarchical cells proxy | projected latency | GPU full assumed |
|---:|---:|---:|---:|---:|---:|
| 8 | 688,128 | 264,552 | 952,680 | 32.833 ms | 36.773 ms |
| 16 | 688,128 | 431,390 | 1,119,518 | 32.833 ms | 36.773 ms |

8-engine 후보는 assumed GPU full 대비 1.120배 빠르다. 이 값은 GPU 실측이 아니며 실제 speedup 주장에 사용할 수 없다.

## 왜 crossbar보다 유리한가

16-port dispatcher/crossbar는 각 complete reduction engine에 partial을 분배하므로 bank accumulation adder와 context 상태가 engine마다 복제된다. parallel tree는 bank reduction을 한 번만 수행하고 latency 5의 scalar engine만 interleave한다.

따라서:

- global reduction hardware 중복 감소
- scalar engine 수 16→8 감소
- row throughput II=1 유지
- tag/epsilon/mode pipeline 유지

## 제한 사항

- 512-bit 상당의 16×(SUM,SUMSQ) 입력 배선 및 physical congestion은 generic cells에 포함되지 않는다.
- Bank reducer와 Logic tree를 연결하는 production top은 아직 없다.
- balanced tree FP16 rounding은 sequential accumulator와 순서가 달라 실제 activation 정확도 검증이 필요하다.
- technology-mapped timing/power가 없다.
- tree input은 한 row의 bank partial이 같은 cycle에 정렬된다고 가정한다.
- missing/late bank partial을 정렬하는 per-bank FIFO/barrier는 아직 없다.
- projected model은 Bank와 Logic stage overlap을 사용하지 않는 보수적 결과다.

## 다음 게이트

1. bank별 partial FIFO와 row-tag barrier
2. 16 bank가 같은 row를 준비하지 못할 때의 skew/backpressure 검증
3. multi-row Bank reducer 16개와 parallel Logic tree의 end-to-end top
4. random FP16/BF16-equivalent activation 정확도 비교
5. VCD/SAIF 및 technology timing 확보

## 재현

```bash
bash verification/groot_normalization/run_logic_normalization_parallel_tree_top_test.sh
bash verification/groot_normalization/run_logic_normalization_parallel_tree_top_synthesis.sh
python tools/analyze_parallel_partial_tree.py
```

산출물:

- `rtl/logic_normalization_parallel_tree_top.sv`
- `rtl/logic_normalization_scalar_engine_array.sv`
- `results/logic_normalization_parallel_tree_e{8,16}_yosys.log`
- `results/parallel_partial_tree_candidate.csv`
