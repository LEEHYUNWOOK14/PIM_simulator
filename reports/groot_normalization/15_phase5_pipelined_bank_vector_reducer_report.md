# Phase 5 pipelined Bank vector reducer 보고서

## 판정

**FUNCTIONAL/SYNTHESIS PASS, SYSTEM PERFORMANCE NOT YET PASS** — 2/4/8/16-lane balanced SUM/SUMSQ tree에 단계별 register를 넣어 vector II=1을 유지하면서 generic logic path를 모두 333으로 제한했다. 면적 증가는 0.3% 미만이다.

하지만 현재 RTL은 한 row context만 허용하여 row마다 pipeline을 drain한다. `[8960,64]` RMSNorm에서 이 overhead가 커져, pipelined Hierarchical은 어떤 lane 구성에서도 assumed GPU-full보다 빨라지지 못했다.

## RTL 동작

파이프라인은 다음 정보를 reduction tree와 함께 정렬한다.

- vector valid
- row의 마지막 vector 여부
- SUM tree 결과
- SUMSQ tree 결과

tree 출력은 row accumulator로 매 cycle 들어가며 같은 row의 vector는 II=1로 연속 수신한다. 마지막 vector가 accumulator에 반영되면 tagged 결과를 만들고, result backpressure 동안 payload와 valid를 유지한다.

## 기능 검증

각 구성에서 두 vector를 back-to-back으로 넣고 다음을 확인했다.

- vector acceptance II=1
- FP16 SUM/SUMSQ bit-exact
- row tag 유지
- 마지막 vector부터 결과까지 pipeline latency
- result stall 2 cycles 동안 valid/payload 유지
- protocol error 미발생

```text
lanes=2  PASS II=1 latency_from_last=2
lanes=4  PASS II=1 latency_from_last=3
lanes=8  PASS II=1 latency_from_last=4
lanes=16 PASS II=1 latency_from_last=5
```

## 합성 비교

Yosys generic synthesis이며 `check -assert`는 전 구성 문제 0건이다.

| lanes | non-pipeline cells | pipeline cells | area overhead | non-pipeline path | pipeline path | path 감소 |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 21,330 | 21,363 | 0.15% | 566 | 333 | 41.2% |
| 4 | 42,389 | 42,461 | 0.17% | 798 | 333 | 58.3% |
| 8 | 84,501 | 84,727 | 0.27% | 1,030 | 333 | 67.7% |
| 16 | 168,725 | 169,209 | 0.29% | 1,262 | 333 | 73.6% |

generic path length는 technology delay가 아니므로 10 ns timing 통과를 뜻하지 않는다. 다만 lane 수에 따라 증가하던 조합 깊이를 register boundary로 제한했다는 구조적 증거다.

## row-aware projected 결과

기존 lane 모델은 전체 tensor element를 vector lane에 연속 포장했지만 실제 normalization은 row 경계를 넘겨 vector를 채울 수 없다. 다음과 같이 수정했다.

```text
vectors_per_row = ceil(hidden / (banks × lanes))
non_pipeline_cycles = rows × vectors_per_row
current_pipeline_cycles = rows × (vectors_per_row + log2(lanes))
```

16 banks, 100 MHz, 333 calls 기준:

| lanes | non-pipeline Hierarchical | current pipeline Hierarchical | GPU full assumed | pipeline area/bank |
|---:|---:|---:|---:|---:|
| 2 | 89.196 ms | 92.285 ms | 36.773 ms | 21,363 cells |
| 4 | 80.097 ms | 86.274 ms | 36.773 ms | 42,461 cells |
| 8 | 76.981 ms | 86.247 ms | 36.773 ms | 84,727 cells |
| 16 | 75.423 ms | 87.777 ms | 36.773 ms | 169,209 cells |

4→8 lanes는 면적이 거의 2배인데 projected latency 차이는 0.027 ms뿐이다. hidden=64 profile에서 bank당 유효 element가 4개뿐이라 8/16 lane이 활용되지 않고 pipeline depth만 늘어나기 때문이다.

## 결론

- timing 구조 관점에서는 pipeline 삽입이 효과적이다.
- 현재 single-row context에서는 4 lanes가 합리적인 후보지만 GPU-full 가정값보다 약 0.89 ms 느리다.
- 8/16 lanes는 작은 hidden dimension의 lane underutilization과 row drain 때문에 제외한다.
- 다음 성능 개선은 lane 수 증가가 아니라 **row context overlap**이다.
- 연속 row의 tree processing을 겹치고 result FIFO로 backpressure를 흡수해야 pipeline fill/drain을 invocation마다 지불하지 않는다.

## 제한 사항

- OpenSTA/OpenROAD가 현재 PATH에 없어 실제 setup slack을 측정하지 못했다.
- FP16 tree의 수치 결과는 순차 accumulation과 balanced tree에서 rounding 순서가 달라질 수 있다.
- 현재 test는 exact representable 입력이며 실제 GR00T activation accuracy 재검증이 필요하다.
- pipeline stage의 clock/reset power는 산출하지 않았다.
- projected GPU 값은 실측이 아니다.

## 재현

```bash
bash verification/groot_normalization/run_bank_normalization_pipelined_vector_reducer_test.sh
bash verification/groot_normalization/run_bank_normalization_pipelined_vector_reducer_synthesis.sh
python tools/analyze_bank_reducer_tradeoff.py
```

산출물:

- `rtl/bank_normalization_pipelined_vector_reducer.sv`
- `results/bank_pipelined_vector_reducer_l{2,4,8,16}_yosys.log`
- `results/bank_vector_reducer_tradeoff.csv`
