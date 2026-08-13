# Phase 5 Bank partial barrier 및 skew 민감도 보고서

## 판정

**FUNCTIONAL PASS, PERFORMANCE CONDITIONAL** — bank별 partial 도착 편차와 tag 불일치를 처리하는 barrier를 parallel Logic tree 앞에 통합했다. 기능과 합성은 통과했지만, 평균 row skew가 2 cycles만 되어도 현재 GPU 가정값보다 느려진다.

## Barrier 계약

config 입력:

- row tag
- expected bank mask
- LayerNorm/RMSNorm mode
- inv-hidden
- epsilon

bank 입력:

- bank별 valid
- bank별 row tag
- partial SUM/SUMSQ

barrier는 expected bank가 모두 valid이고 모든 tag가 config tag와 같을 때만 `row_valid`를 생성한다. tree가 row를 받을 때 expected bank를 같은 cycle에 원자적으로 consume한다.

## 기능 검증

축소 BANKS=4 구성에서 두 row를 실행했다.

1. row 0의 bank partial을 2 cycle 이상 어긋나게 제시
2. 마지막 bank가 도착하기 전에는 bank ready가 발생하지 않음을 확인
3. row 1의 bank 2에 잘못된 tag 제시
4. tag mismatch error 확인 후 올바른 tag로 교정
5. barrier → parallel tree → scalar engine 결과 확인
6. output stall 중 response 유지

```text
LOGIC_NORMALIZATION_BARRIER_TREE_TOP_TB PASS rows=2 skew_cycles=2 mismatch_detected=1 cycles=24
```

## 합성

조건: BANKS=16, scalar engines=8, Yosys generic synthesis.

| 구조 | generic cells | strict check |
|---|---:|---|
| parallel tree top | 264,552 | 문제 0 |
| barrier + parallel tree top | 265,421 | 문제 0 |
| barrier overhead | 869 (0.33%) | — |

Barrier control 자체의 면적은 작다. 실제 비용 위험은 bank FIFO 저장공간과 16-bank 배선/동기화다.

## Skew sensitivity

전체 manifest에는 projected normalization row가 308,860개 있다. 다음 모델은 각 row에서 가장 늦은 bank 때문에 생기는 평균 bubble을 독립적으로 더하는 보수적 sensitivity다.

| 평균 max bank skew/row | skew penalty | Hierarchical latency | GPU full assumed | winner |
|---:|---:|---:|---:|---|
| 0 cycles | 0.000 ms | 32.833 ms | 36.773 ms | Hierarchical |
| 1 cycle | 3.089 ms | 35.921 ms | 36.773 ms | Hierarchical |
| 2 cycles | 6.177 ms | 39.010 ms | 36.773 ms | GPU full |
| 4 cycles | 12.354 ms | 45.187 ms | 36.773 ms | GPU full |
| 8 cycles | 24.709 ms | 57.541 ms | 36.773 ms | GPU full |
| 16 cycles | 49.418 ms | 82.250 ms | 36.773 ms | GPU full |

현재 assumed GPU와의 여유는 3.940 ms뿐이다. 평균 skew가 약 1.28 cycles/row를 넘으면 분석상 우위가 사라진다.

## 해석

- barrier는 correctness 문제를 해결하지만 skew 자체를 없애지 않는다.
- `[8960,64]`는 row 수가 많아 작은 per-row bubble도 전체 latency에 크게 누적된다.
- bank별 FIFO가 일정한 고정 위상 차이를 흡수하면 실제 penalty는 이 단순 합보다 작을 수 있다.
- 반대로 bank conflict나 queue HOL blocking이 반복되면 2-cycle 이상이 쉽게 발생할 수 있다.
- 따라서 zero-skew 결과만으로 1.12배 speedup을 주장하면 안 된다.

## 현재 권고 조건

Parallel-tree Hierarchical을 권고하려면 simulator 또는 trace에서 다음 조건을 증명해야 한다.

```text
average max bank skew < 약 1.28 cycles/row
```

이 조건을 만족하지 못하면 GPU full 또는 Bank-only가 더 적합할 수 있다.

## 남은 한계

- barrier는 한 config context만 유지하지만 row consume과 다음 config를 같은 cycle에 받을 수 있도록 설계됐다. 해당 동시 경계는 아직 별도 directed test가 없다.
- wrong-tag entry의 자동 drop/recovery 정책이 없다. 현재는 upstream이 교정하거나 reset해야 한다.
- per-bank FIFO는 upstream Bank reducer result FIFO에 의존하며 Logic barrier 내부에는 없다.
- skew distribution은 실측이 아니라 sensitivity parameter다.
- 실제 HBM bank scheduling trace가 없다.
- technology timing/power가 없다.

## 다음 게이트

1. Bank reducer 16개와 barrier/tree를 연결한 end-to-end top
2. random bank delay와 output backpressure stress test
3. skew histogram 및 FIFO occupancy 출력
4. PIMSimulator bank scheduling에서 실제 skew 계측
5. measured skew로 architecture 결과 재산출

## 재현

```bash
bash verification/groot_normalization/run_logic_normalization_barrier_tree_top_test.sh
bash verification/groot_normalization/run_logic_normalization_barrier_tree_top_synthesis.sh
python tools/analyze_bank_skew_sensitivity.py
```

산출물:

- `rtl/logic_normalization_bank_barrier.sv`
- `rtl/logic_normalization_barrier_tree_top.sv`
- `results/logic_normalization_barrier_tree_e8_yosys.log`
- `results/bank_skew_sensitivity.csv`
